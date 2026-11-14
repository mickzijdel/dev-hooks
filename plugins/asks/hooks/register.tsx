import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer, UiPressArgument } from 'claude-code'

import type { Ask, PaneView, Presence, Receipt } from '../types'
import { ago, describe, inOrder, type Described, type Kind } from './describe'
import { parseAsk, questionText, sessionName, statesMove, titleFrom, topicPrompt } from './parse'

const PANE = 'asks'
const TITLE = 'Asks'
const POLL_MS = 3000
const LABEL_LENGTH = 60
const TOPIC_MODEL = 'haiku'
/** A session that has said nothing for this long is left out of the "need nothing" list. */
const QUIET_MS = 24 * 3_600_000
/** A turn that "runs" for this long has most likely died with its process. */
const STUCK_MS = 6 * 3_600_000
const KEPT_SESSIONS = 40
/** A message no session picked up in this time is dropped: a live session reads its messages every few seconds. */
const UNREAD_MS = 2 * 60_000
/** An ask must have been the memo for this long before a press answers it. */
const GUARD_MS = 600
const ASKED_LENGTH = 120
/** A fact longer than this, or of several lines, is drawn under its label, not beside it. */
const FACT_ROW_LENGTH = 60

/** `$.store` is one file for every session, so each record has the session in its key. */
const askKey = (session: string) => `ask:${session}`
/** The prefix of a session's messages; each message adds its own time and count, so none overwrites another. */
const sendKey = (session: string) => `send:${session}:`
const hereKey = (session: string) => `here:${session}`

/** The text each button sends: fixed here, never written by a model. */
const SENDS = { yes: 'Yes, go ahead.', no: 'No.', done: 'done' }

/** One colour per kind of ask, and coral for "blocks other work" alone. */
const COLOUR: Record<Kind, string> = {
  'go-ahead': '#e3ad55',
  choose: '#e3ad55',
  reply: '#e3ad55',
  do: '#7db0e6',
  review: '#86c58a',
}
const CORAL = '#e08a80'
const RULE = '#33332f'
const KIND_WORD: Record<Kind, string> = {
  'go-ahead': 'GO-AHEAD',
  choose: 'CHOOSE',
  reply: 'ANSWER',
  do: 'DO',
  review: 'REVIEW',
}

const EMPTY_VIEW: PaneView = { focus: null, mode: 'view', target: null, receipt: null }

const asks = atom({ plugin: 'asks', key: 'list' } as const, [], { shape: 'asks-1' })
const sessions = atom({ plugin: 'asks', key: 'sessions' } as const, [], { shape: 'sessions-1' })
const view = atom({ plugin: 'asks', key: 'view' } as const, EMPTY_VIEW, { shape: 'view-1' })
/** The sessions that have a message of the pane's waiting to be picked up. */
const pending = atom({ plugin: 'asks', key: 'pending' } as const, [], { shape: 'pending-1' })

let poll: Timer | null = null
let sends = 0
let named: { session: string; label: string } | null = null
/** The session whose ask stays the memo until it is answered or the person moves on, whatever arrives meanwhile. */
let pinned: string | null = null
/** The ask the memo shows, and since when. */
let shown: { session: string; at: number; since: number } | null = null

/** The title the app gave the session, read from its transcript. Empty when there is none or it cannot be read. */
async function appTitle($: EngineInterface, session: string): Promise<string> {
  const home = await $.env.get('HOME')
  const config = (await $.env.get('CLAUDE_CONFIG_DIR')) || (home ? `${home}/.claude` : '')
  if (!config) return ''
  // `--include` holds the search to this session's transcript, whichever project folder it is in.
  const found = await $.process.run(
    ['grep', '-rho', '--include', `${session}.jsonl`, '"customTitle":"[^"]*"', `${config}/projects`],
    { timeoutMs: 5000 },
  )

  return titleFrom(found.stdout)
}

/** The app's title for the session; else its first prompt, cut short; else its folder's name. */
async function sessionLabel($: EngineInterface, session: string): Promise<string> {
  const title = await appTitle($, session).catch(() => '')
  const label = title || (await firstPrompt($))
  named = { session, label }

  return label
}

/** The label last found for this session: the search for the title is too slow to run at every turn's start. */
const knownLabel = async ($: EngineInterface, session: string) =>
  named?.session === session ? named.label : sessionLabel($, session)

async function firstPrompt($: EngineInterface): Promise<string> {
  const messages = await $.session.messages().catch(() => [])
  for (const m of messages) {
    const name = m.role === 'user' ? sessionName(m.text, LABEL_LENGTH) : ''
    if (name) return name
  }
  const cwd = await $.session.cwd().catch(() => '')

  return cwd.split('/').filter(Boolean).pop() ?? 'session'
}

async function record($: EngineInterface, kind: Ask['kind'], parts: Pick<Ask, 'move' | 'changed' | 'context'>) {
  const [session, at] = await Promise.all([$.session.id(), $.clock.now()])
  const ask: Ask = { session, label: await knownLabel($, session), at, kind, ...parts }
  await $.store.set(askKey(session), ask)
  await refresh($)
  if (kind === 'move') void addTopic($, ask).catch(() => undefined)
}

/** Heads the ask with its subject, from one small model call. The ask stays as it is when the call fails. */
async function addTopic($: EngineInterface, ask: Ask) {
  const r = await $.model.complete({
    model: TOPIC_MODEL,
    prompt: topicPrompt(ask.label, ask),
    maxTokens: 40,
    timeoutMs: 10_000,
  })
  const topic = r.isAnswered ? r.text.trim().split('\n')[0]!.replace(/[."]+$/, '') : ''
  if (!topic) return
  // The ask may have been answered or replaced while the model wrote.
  const now = (await $.store.get(askKey(ask.session))) as Ask | undefined
  if (now?.at !== ask.at) return
  await $.store.set(askKey(ask.session), { ...now, topic })
  await refresh($)
}

async function clear($: EngineInterface, session: string) {
  await $.store.delete(askKey(session))
  await refresh($)
}

/** Says this session runs a turn or has ended one, for the other sessions' panes. */
async function present($: EngineInterface, state: Presence['state']) {
  const [session, at] = await Promise.all([$.session.id(), $.clock.now()])
  // The app can rename a session at any time; the end of a turn is when the name is read again.
  const label = await (state === 'idle' ? sessionLabel($, session) : knownLabel($, session))
  const here: Presence = { session, label, state, at }
  await $.store.set(hereKey(session), here)
  const all = await stored<Presence>($, 'here:')
  const stale = all.sort((a, b) => b.at - a.at).slice(KEPT_SESSIONS)
  await Promise.all(stale.map(old => $.store.delete(hereKey(old.session))))
  await refresh($)
}

async function stored<T extends { session: string }>($: EngineInterface, prefix: string): Promise<T[]> {
  const keys = (await $.store.keys()).filter(k => k.startsWith(prefix))
  const found = (await Promise.all(keys.map(k => $.store.get(k)))) as (T | undefined)[]

  return found.filter((one): one is T => !!one && typeof one.session === 'string')
}

/** A message the pane left for another session, and the ask it answers so the ask can come back if nobody reads it. */
type Queued = { session: string; text: string; at: number; ask?: Ask }

/**
 * Reads every session's ask, presence and unread messages from the store into the pane's values. A message no
 * session picked up in time is dropped, and the ask it answered is put back, so an answer is never lost in silence.
 */
async function refresh($: EngineInterface) {
  const [list, here, queued, now] = await Promise.all([
    stored<Ask>($, 'ask:'),
    stored<Presence>($, 'here:'),
    queuedMessages($),
    $.clock.now(),
  ])
  for (const { key, message } of queued) {
    if (now - message.at < UNREAD_MS) continue
    await $.store.delete(key)
    const back = message.ask
    if (back && !list.some(a => a.session === back.session)) {
      await $.store.set(askKey(back.session), back)
      list.push(back)
    }
  }
  const unread = [...new Set(queued.filter(q => now - q.message.at < UNREAD_MS).map(q => q.message.session))].sort()
  list.sort((a, b) => a.at - b.at)
  here.sort((a, b) => a.label.localeCompare(b.label))
  // A value is written only when it differs, so a poll that finds nothing new draws nothing.
  await update($, asks, was => (isSame(was, list) ? was : list))
  await update($, sessions, was => (isSame(was, here) ? was : here))
  await update($, pending, was => (isSame(was, unread) ? was : unread))
}

const isSame = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b)

/** The messages waiting in the store, oldest first: `$.store.keys()` lists keys in the order they were set. */
async function queuedMessages($: EngineInterface, prefix = 'send:'): Promise<{ key: string; message: Queued }[]> {
  const keys = (await $.store.keys()).filter(k => k.startsWith(prefix))
  const found = await Promise.all(keys.map(async key => ({ key, message: (await $.store.get(key)) as Queued })))

  return found.filter(q => !!q.message && typeof q.message.text === 'string' && typeof q.message.at === 'number')
}

/** Submits text as the person's own words: it comes from a button they pressed or a field they typed in. */
const say = ($: EngineInterface, text: string) => void $.prompt.submit({ text, asUser: true })

/** Submits, as prompts of this session, the messages the panes of other sessions left for it, oldest first. */
async function deliver($: EngineInterface) {
  const [session, now] = await Promise.all([$.session.id(), $.clock.now()])
  for (const { key, message } of await queuedMessages($, sendKey(session))) {
    // A message that waited too long was written for a moment that has passed, as when a closed session is
    // resumed. It is left for `refresh`, which drops it and puts its ask back.
    if (now - message.at >= UNREAD_MS) continue
    await $.store.delete(key)
    say($, message.text)
  }
}

/** Sends `text` to a session: at once when it is this one, else through the store, one key per message. */
async function send($: EngineInterface, session: string, text: string, ask?: Ask) {
  if (session === (await $.session.id())) return say($, text)
  const at = await $.clock.now()
  sends += 1
  const message: Queued = { session, text, at, ...(ask ? { ask } : {}) }
  await $.store.set(`${sendKey(session)}${at}-${sends}`, message)
  await refresh($)
}

const patch = ($: EngineInterface, change: Partial<PaneView>) => update($, view, was => ({ ...was, ...change }))

/**
 * Whether `ask` is the memo the person has had in view long enough to have read it. A press that lands on an ask
 * which only just took the memo's place (a second key press, a new ask arriving) is not an answer to it.
 */
async function isRead($: EngineInterface, ask: Ask): Promise<boolean> {
  const now = await $.clock.now()
  return !!shown && shown.session === ask.session && shown.at === ask.at && now - shown.since >= GUARD_MS
}

/** What the session reads: the answer, and the session's own question so a late answer cannot be misread. */
function answerText(ask: Ask, text: string): string {
  const line = ask.move.split('\n')[0]!.trim()
  const asked = line.length > ASKED_LENGTH ? `${line.slice(0, ASKED_LENGTH)}…` : line

  return `${text}\n\n(This answers your ask: “${asked}”)`
}

/** Answers an ask: sends the text, clears the ask, shows the receipt and moves the memo to the next ask. */
async function answer($: EngineInterface, ask: Ask, text: string) {
  if (!(await isRead($, ask))) return
  const undo = describe(ask).facts.find(f => f.key === 'UNDO')?.value ?? ''
  await $.store.delete(askKey(ask.session))
  await send($, ask.session, answerText(ask, text), ask)
  await refresh($)
  pinned = null
  const receipt: Receipt = { session: ask.session, label: ask.label, sent: text, undo, askAt: ask.at }
  await patch($, { mode: 'view', focus: null, receipt })
}

/** Clears an ask with nothing sent, as "Seen" on a review. The receipt can put it back. */
async function seen($: EngineInterface, ask: Ask) {
  if (!(await isRead($, ask))) return
  await clear($, ask.session)
  pinned = null
  const receipt: Receipt = { session: ask.session, label: ask.label, sent: '', undo: '', cleared: ask }
  await patch($, { mode: 'view', focus: null, receipt })
}

/** Sets an ask aside ("Not now"), or brings it back. Nothing is sent, and the session's next ask replaces it. */
async function setAside($: EngineInterface, ask: Ask, isAside: boolean) {
  if (!(await isRead($, ask))) return
  const { later: _was, ...rest } = ask
  await $.store.set(askKey(ask.session), isAside ? { ...rest, later: true } : rest)
  await refresh($)
  pinned = null
  await patch($, { mode: 'view', focus: isAside ? null : ask.session, receipt: null })
}

async function putBack($: EngineInterface, ask: Ask) {
  await $.store.set(askKey(ask.session), ask)
  await refresh($)
  await patch($, { receipt: null, focus: ask.session })
}

/** Removes what a session that has ended left in the store: its ask, its presence and the messages for it. */
async function forget($: EngineInterface, session: string) {
  const keys = (await $.store.keys()).filter(
    k => k === askKey(session) || k === hereKey(session) || k.startsWith(sendKey(session)),
  )
  await Promise.all(keys.map(k => $.store.delete(k)))
}

/** Only web links are opened, by the system's own opener: `open` on macOS, `xdg-open` elsewhere. */
async function openLink($: EngineInterface, url: string) {
  if (!/^https?:\/\//.test(url)) return
  const opened = await $.process.run(['open', url], { timeoutMs: 10_000 }).catch(() => null)
  if (opened?.exitCode !== 0) await $.process.run(['xdg-open', url], { timeoutMs: 10_000 }).catch(() => undefined)
}

// shortcut: a fullscreen terminal docks a pane too, but can't be told apart here; it gets /asks.
const DOCKING_SURFACES = new Set(['vscode', 'desktop'])

/** Unasked, the pane opens without taking the focus from the prompt. */
async function openPaneUnasked($: EngineInterface, surface: string | null) {
  if (surface === null || !DOCKING_SURFACES.has(surface)) return
  if ((await $.env.get('ASKS_PANE')) === 'false') return
  void $.ui.open({ id: PANE, title: TITLE }).catch(() => undefined)
}

export const register: Register = on => {
  on('session.attach', async ($, e, next) => {
    await openPaneUnasked($, e.surface).catch(() => undefined)

    return next(e)
  })

  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'asks', description: 'Show what every session is waiting on you for' })
    poll?.cancel()
    poll = $.clock.every(POLL_MS, () => {
      void refresh($).catch(() => undefined)
      void deliver($).catch(() => undefined)
    })
    await present($, 'idle').catch(() => undefined)
    await openPaneUnasked($, e.surface).catch(() => undefined)

    return next(e)
  })

  on('command.run', { command: 'asks' }, async $ => {
    await $.ui.open({ id: PANE, title: TITLE, focus: true })

    return { text: 'Asks pane opened.' }
  })

  on('session.end', async ($, e, next) => {
    await forget($, e.sessionId).catch(() => undefined)
    // After /clear the same process goes on under a new id with no new session.start, so its poll must keep running.
    if (e.reason !== 'clear') poll?.cancel()

    return next(e)
  })

  // A prompt the person wrote answers whatever this session was waiting for, wherever they wrote it. A slash
  // command, a notification or another session's message does not.
  on('prompt.submit', async ($, e, next) => {
    const isPerson = ['composer', 'bridge', 'sdk'].includes(e.origin.kind) && !e.command && !e.isMeta
    if (isPerson) await clear($, await $.session.id()).catch(() => undefined)

    return next(e)
  })

  on('turn.start', async ($, e, next) => {
    if (e.agentId === undefined) await present($, 'running').catch(() => undefined)

    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const r = await next(e)
    if (e.agentId !== undefined) return r
    await present($, 'idle').catch(() => undefined)
    if (e.reason !== 'answer') return r
    const parsed = parseAsk(e.answer)
    if (parsed) await record($, 'move', parsed).catch(() => undefined)
    // A stated move of "nothing" closes the ask. A reply that states no move leaves the ask open.
    else if (statesMove(e.answer)) await clear($, await $.session.id()).catch(() => undefined)

    return r
  })

  on('tool.call', { tool: 'AskUserQuestion' }, async ($, e, next) => {
    if (e.agentId !== undefined) return next(e)
    await record($, 'question', { move: questionText(e), changed: '', context: '' }).catch(() => undefined)
    try {
      return await next(e)
    } finally {
      // Nothing here may replace the tool call's own result or error.
      const session = await $.session.id().catch(() => null)
      if (session) await clear($, session).catch(() => undefined)
    }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button, Input, Select, Markdown, Code } = $.ui.resolve(e)
    const [all, everyone, state, unread, own, now] = await Promise.all([
      read($, asks),
      read($, sessions),
      read($, view),
      read($, pending),
      $.session.id(),
      $.clock.now(),
    ])
    const every = inOrder(all)
    const list = every.filter(a => !a.later)
    // The memo stays on the ask the person chose or was last shown; a more urgent ask that arrives waits in the list.
    // An ask set aside is the memo only while the person has opened it.
    const memo =
      every.find(a => a.session === state.focus) ?? list.find(a => a.session === pinned) ?? list[0]
    const aside = every.filter(a => a.later && a !== memo)
    pinned = memo?.session ?? null
    if (!memo) shown = null
    else if (shown?.session !== memo.session || shown.at !== memo.at) shown = { session: memo.session, at: memo.at, since: now }
    const others = list.filter(a => a !== memo)
    const at = memo ? list.indexOf(memo) : -1
    const waiting = new Set(every.map(a => a.session))
    // A session that has not been heard from for long has most likely been closed.
    const here = everyone.filter(s => now - s.at < (s.state === 'running' ? STUCK_MS : QUIET_MS))
    const quiet = here.filter(s => !waiting.has(s.session))
    const target = here.find(s => s.session === state.target) ?? quiet[0] ?? here[0]
    // A text field that has lost what it was for (its ask answered elsewhere, its receipt gone) gives way to the buttons.
    const mode: PaneView['mode'] =
      (state.mode === 'reply' && memo?.session !== state.focus) ||
      (state.mode === 'followup' && !state.receipt) ||
      (state.mode === 'prompt' && !target)
        ? 'view'
        : state.mode
    // While a text field is open every key must go into it, so no button has a key.
    const keys = mode === 'view'
    const key = (letter: string) => (keys ? { hotkey: letter } : {})
    const focusOn = (session: string | null) => void patch($, { focus: session, mode: 'view' })
    const cancel = () => void patch($, { mode: 'view' })
    /** The keys that answer the memo, then the keys that move about: listed in that order under the pane. */
    const legend: string[] = []
    const moves: string[] = []

    const hint = (text: string) => (
      <Text dimColor size="footnote">
        {text}
      </Text>
    )

    const answers = (ask: Ask, d: Described) => {
      if (mode === 'reply') {
        return (
          <Box flexDirection="column" gap={1}>
            <Input
              key={`reply-${ask.session}`}
              label={`Other answer to ${ask.label}`}
              placeholder="Type your answer"
              submitLabel="Send"
              autoFocus
              onSubmit={text => void (text.trim() ? answer($, ask, text.trim()) : cancel())}
            />
            <Button key="cancel" plain onPress={cancel}>
              Cancel
            </Button>
          </Box>
        )
      }
      if (ask.kind === 'question') return hint('A question dialog is open in this session. Answer it there.')
      const other = (
        <Button key="other" plain {...key('r')} onPress={() => void patch($, { mode: 'reply', focus: ask.session })}>
          {d.kind === 'review' ? 'Reply…' : 'Other answer…'}
        </Button>
      )
      legend.push('r other answer')
      if (d.kind === 'choose') {
        legend.unshift(`${d.options.map(o => o.number).join(' ')} choose`)
        // One filled button at most: the first option the session recommends.
        const primary = d.recommended[0]
        return (
          <Box flexDirection="column" gap={1}>
            {d.options.map(o => (
              <Box flexDirection="row" gap={1} alignItems="flex-start">
                <Button
                  key={`option-${ask.session}-${o.number}`}
                  variant={o.number === primary ? 'primary' : 'secondary'}
                  {...(o.number < 10 ? key(String(o.number)) : {})}
                  onPress={() => void answer($, ask, `Option ${o.number}: ${o.label}`)}
                >
                  {o.number < 10 ? 'Pick' : `Pick ${o.number}`}
                </Button>
                <Box flexDirection="column" flexGrow={1} flexShrink={1}>
                  <Markdown text={o.label} />
                  {o.consequence && <Markdown text={o.consequence} dimColor />}
                </Box>
              </Box>
            ))}
            {other}
          </Box>
        )
      }
      if (d.kind === 'do') {
        legend.unshift(...(d.command ? ['c copy'] : []), 'd done')
        return (
          <Box flexDirection="column" gap={1}>
            {d.command && (
              <Box flexDirection="row" gap={1} alignItems="center">
                <Box flexGrow={1} flexShrink={1}>
                  <Code source={d.command} language="bash" />
                </Box>
                <Button
                  key="copy"
                  {...key('c')}
                  onPress={(press: UiPressArgument) => void $.ui.copy({ text: d.command, surface: press.surface })}
                >
                  Copy
                </Button>
              </Box>
            )}
            <Box flexDirection="row">
              <Button key={`done-${ask.session}`} variant="primary" {...key('d')} onPress={() => void answer($, ask, SENDS.done)}>
                Done
              </Button>
            </Box>
            {other}
          </Box>
        )
      }
      if (d.kind === 'review') {
        legend.unshift(...(d.url ? ['o open'] : []), 'e seen')
        return (
          <Box flexDirection="column" gap={1}>
            {d.url && (
              <Box flexDirection="row" gap={1} alignItems="center">
                <Button key="open" variant="primary" {...key('o')} onPress={() => void openLink($, d.url)}>
                  Open
                </Button>
                {hint('Opens in the browser. The ask stays until Seen.')}
              </Box>
            )}
            <Box flexDirection="row" gap={1} alignItems="center">
              <Button key={`seen-${ask.session}`} variant={d.url ? 'secondary' : 'primary'} {...key('e')} onPress={() => void seen($, ask)}>
                Seen
              </Button>
              {hint('Clears the ask. Sends nothing.')}
              {other}
            </Box>
          </Box>
        )
      }
      if (d.kind === 'reply') {
        // Not a yes-or-no question, so no button sends a fixed answer: the person answers in words, or clears it.
        legend.splice(0, legend.length, 'r answer', 'e seen')
        return (
          <Box flexDirection="row" gap={1} alignItems="center">
            <Button
              key="other"
              variant="primary"
              {...key('r')}
              onPress={() => void patch($, { mode: 'reply', focus: ask.session })}
            >
              Answer…
            </Button>
            <Button key={`seen-${ask.session}`} {...key('e')} onPress={() => void seen($, ask)}>
              Seen
            </Button>
            {hint('Seen clears the ask and sends nothing.')}
          </Box>
        )
      }
      legend.unshift('y yes', 'n no')
      return (
        <Box flexDirection="column" gap={1}>
          <Box flexDirection="row" gap={1} alignItems="center">
            <Button key={`yes-${ask.session}`} variant="primary" {...key('y')} onPress={() => void answer($, ask, SENDS.yes)}>
              Yes
            </Button>
            {hint(`Sends “${SENDS.yes}”`)}
          </Box>
          <Box flexDirection="row" gap={1}>
            <Button key={`no-${ask.session}`} {...key('n')} onPress={() => void answer($, ask, SENDS.no)}>
              No
            </Button>
            {other}
          </Box>
        </Box>
      )
    }

    const notNow = (ask: Ask) => {
      if (!keys) return null
      legend.push(ask.later ? 'l bring back' : 'l not now')
      return (
        <Box flexDirection="row">
          <Button key={`later-${ask.session}`} plain {...key('l')} onPress={() => void setAside($, ask, !ask.later)}>
            {ask.later ? 'Bring back' : 'Not now'}
          </Button>
        </Box>
      )
    }

    const memoBox = (ask: Ask) => {
      const d = describe(ask)
      const colour = COLOUR[d.kind]
      return (
        <Box flexDirection="column" borderStyle="round" borderColor={colour} paddingX={1} gap={1}>
          <Box flexDirection="column">
            <Box flexDirection="row" gap={1} justifyContent="space-between">
              <Text size="caption">
                <Text color={colour} weight="bold">
                  {KIND_WORD[d.kind]}
                </Text>
                <Text dimColor>
                  {'  '}
                  {ask.label}
                  {ask.session === own ? ' · this session' : ''}
                </Text>
              </Text>
              <Text dimColor size="caption">
                {ago(now - ask.at)}
              </Text>
            </Box>
            <Text size="heading" weight="semibold">
              {d.question}
            </Text>
            {d.blocks && (
              <Text color={CORAL} weight="semibold" size="footnote">
                Blocks {d.blocks}
              </Text>
            )}
          </Box>
          {d.body && <Markdown text={d.body} />}
          {d.recommend && (
            <Text>
              <Text dimColor>Claude recommends: </Text>
              {d.recommend}
            </Text>
          )}
          {answers(ask, d)}
          {notNow(ask)}
          {d.facts.length > 0 && (
            <Box flexDirection="column">
              {d.facts.map(f => {
                // A long fact (a table, several paragraphs) gets the pane's full width under its label; a
                // label column beside it would stay empty all the way down.
                const isLong = f.value.includes('\n') || f.value.length > FACT_ROW_LENGTH
                return (
                  <Box flexDirection={isLong ? 'column' : 'row'} gap={isLong ? 0 : 1} alignItems="flex-start">
                    <Box {...(isLong ? {} : { width: 10 })} flexShrink={0}>
                      <Text dimColor size="caption" weight="semibold">
                        {f.key}
                      </Text>
                    </Box>
                    <Box flexGrow={1} flexShrink={1}>
                      <Markdown text={f.value} />
                    </Box>
                  </Box>
                )
              })}
            </Box>
          )}
        </Box>
      )
    }

    const receiptBox = (r: Receipt) => {
      if (mode === 'followup') {
        return (
          <Box flexDirection="column" gap={1}>
            <Input
              key={`follow-${r.session}`}
              label={`Follow up to ${r.label}`}
              placeholder="Correct or add to your answer"
              submitLabel="Send"
              autoFocus
              onSubmit={text =>
                void (text.trim()
                  ? send($, r.session, text.trim()).then(() => patch($, { mode: 'view', receipt: { ...r, sent: text.trim(), undo: '' } }))
                  : cancel())
              }
            />
            <Button key="cancel" plain onPress={cancel}>
              Cancel
            </Button>
          </Box>
        )
      }
      const cleared = r.cleared
      if (keys) moves.push(cleared ? 'u put back' : 'u follow up')
      // The ask is back in the list: no session picked the answer up, so it was dropped and the ask restored.
      const isBack = !cleared && list.some(a => a.session === r.session && a.at === r.askAt)
      const isQueued = !cleared && !isBack && unread.includes(r.session)
      const head = cleared
        ? '✓ Cleared the ask'
        : isBack
          ? `Not delivered: “${r.sent}”`
          : isQueued
            ? `Queued: “${r.sent}”`
            : `✓ You sent “${r.sent}”`
      const tail = cleared
        ? ` of ${r.label}. Nothing was sent.`
        : isBack
          ? ` ${r.label} is not running, so the ask is back in the list.`
          : isQueued
            ? ` for ${r.label}, not picked up yet.`
            : ` to ${r.label}.${r.undo ? ` To undo: ${r.undo}` : ''}`
      return (
        <Box flexDirection="row" gap={1} alignItems="flex-start" backgroundColor="#272725" paddingX={1}>
          <Box flexGrow={1} flexShrink={1}>
            <Text size="footnote">
              <Text weight="semibold">{head}</Text>
              <Text dimColor>{tail}</Text>
            </Text>
          </Box>
          {cleared ? (
            <Button key="put-back" plain {...key('u')} onPress={() => void putBack($, cleared)}>
              {'Put back'}
            </Button>
          ) : (
            <Button key="follow-up" plain {...key('u')} onPress={() => void patch($, { mode: 'followup' })}>
              {'Follow up…'}
            </Button>
          )}
        </Box>
      )
    }

    const also = others.length > 0 && (
      <Box flexDirection="column">
        <Box flexDirection="row" gap={1} alignItems="center" justifyContent="space-between">
          <Text dimColor size="caption" weight="semibold">
            ALSO WAITING · {others.length}
          </Text>
          <Box flexDirection="row" gap={1}>
            <Button key="next" plain {...key('j')} onPress={() => focusOn(list[(at + 1) % list.length]!.session)}>
              Next
            </Button>
            {others.length > 1 && (
              <Button
                key="previous"
                plain
                {...key('k')}
                onPress={() => focusOn(list[(at - 1 + list.length) % list.length]!.session)}
              >
                Previous
              </Button>
            )}
          </Box>
        </Box>
        {others.map(a => {
          const d = describe(a)
          return (
            <Box flexDirection="row" gap={1} alignItems="flex-start">
              <Box width={9} flexShrink={0}>
                <Text color={COLOUR[d.kind]} weight="bold" size="caption">
                  {KIND_WORD[d.kind]}
                </Text>
              </Box>
              <Box flexGrow={1} flexShrink={1}>
                <Text size="footnote">
                  {a.topic || d.question}
                  <Text dimColor> · {a.label}</Text>
                </Text>
              </Box>
              <Box flexShrink={0}>
                <Text size="caption">
                  {d.blocks && (
                    <Text color={CORAL} weight="semibold">
                      blocks{' '}
                    </Text>
                  )}
                  <Text dimColor>{ago(now - a.at, true)}</Text>
                </Text>
              </Box>
            </Box>
          )
        })}
      </Box>
    )
    if (keys && others.length > 0) moves.push('j next', ...(others.length > 1 ? ['k previous'] : []))

    const asideView = aside.length > 0 && (
      <Box flexDirection="column">
        <Text dimColor size="caption" weight="semibold">
          SET ASIDE · {aside.length}
        </Text>
        {aside.map(a => (
          <Box flexDirection="row">
            <Button key={`aside-${a.session}`} plain onPress={() => focusOn(a.session)}>
              {`${a.topic || describe(a).question} · ${a.label}`}
            </Button>
          </Box>
        ))}
      </Box>
    )

    const quietLine = (s: Presence) => `${s.label} (${s.state === 'running' ? `running ${ago(now - s.at)}` : 'idle'})`
    const targets = here.map(s => ({ value: s.session, label: s.label }))
    const running = quiet.filter(s => s.state === 'running').length
    const needNothing =
      quiet.length === 0
        ? ''
        : quiet.length <= 3
          ? `Need nothing: ${quiet.map(quietLine).join(' · ')}`
          : `Need nothing: ${running} running · ${quiet.length - running} idle`
    const prompt =
      mode === 'prompt' && target ? (
        <Box flexDirection="column" borderStyle="round" borderColor={RULE} paddingX={1} gap={1}>
          <Select
            key="target"
            label="New prompt to"
            options={targets}
            value={target.session}
            onSelect={value => void patch($, { target: value })}
          />
          <Input
            key={`prompt-${target.session}`}
            label={`Prompt for ${target.label}`}
            placeholder="New work for this session, not an answer to an ask"
            submitLabel="Send"
            rows={3}
            autoFocus
            onSubmit={text =>
              void (text.trim()
                ? send($, target.session, text.trim()).then(() =>
                    patch($, {
                      mode: 'view',
                      receipt: { session: target.session, label: target.label, sent: text.trim(), undo: '' },
                    }),
                  )
                : cancel())
            }
          />
          <Button key="cancel" plain onPress={cancel}>
            Cancel
          </Button>
        </Box>
      ) : (
        here.length > 0 && (
          <Box flexDirection="row" gap={1} alignItems="flex-start" justifyContent="space-between">
            <Box flexGrow={1} flexShrink={1}>
              {needNothing && hint(needNothing)}
            </Box>
            <Button
              key="prompt"
              plain={list.length > 0 ? true : undefined}
              variant={list.length > 0 ? undefined : 'primary'}
              {...key('p')}
              onPress={() => void patch($, { mode: 'prompt', target: target?.session ?? null })}
            >
              {'Prompt a session…'}
            </Button>
          </Box>
        )
      )
    if (keys && here.length > 0) moves.push('p prompt a session')

    const memoView = memo && memoBox(memo)
    const receiptView = state.receipt && receiptBox(state.receipt)

    return (
      <Box flexDirection="column" gap={1}>
        <Box flexDirection="row" justifyContent="space-between" alignItems="center">
          <Text size="title" weight="semibold">
            {list.length > 0 ? `${list.length} waiting on you` : 'Nothing waiting on you'}
          </Text>
          {list.length > 1 && (
            <Text dimColor size="caption">
              blocking first, then oldest
            </Text>
          )}
        </Box>
        {memoView}
        {receiptView}
        {also}
        {asideView}
        {prompt}
        <Text dimColor size="caption">
          {!keys
            ? 'Typing: every key goes into the field. Enter sends. The keys come back after Send or Cancel.'
            : `${e.props.isFocused ? '' : 'Click in this pane to use the keys: '}${[...legend, ...moves].join(' · ')}`}
        </Text>
      </Box>
    )
  })
}
