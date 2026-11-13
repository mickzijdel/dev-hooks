import { expect, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'

import type { Ask, Presence } from '../types'

const PANE = {
  plugin: 'asks',
  component: 'Pane',
  requestId: 'asks',
  surface: 'desktop',
  props: {
    title: 'Asks',
    isFocused: true,
    bodyColumns: 60,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
} as const

const NOW = 10 * 3_600_000

const ask = (session: string, label: string, at: number, move: string, context = '', changed = ''): Ask => ({
  session,
  label,
  at,
  kind: 'move',
  move,
  changed,
  context,
})

const goAhead = ask(
  'mig',
  'Database import',
  NOW - 500,
  'Run the import migration on the rehearsal copy?\n**Recommend:** Yes. Not production.\n**Blocks:** 2 more tasks',
  '**Undo:** Easy. Drop the two columns.',
  'Script written.',
)
const choice = ask('ui', 'Asks UI', NOW - 900, 'Choose a route. I recommend route 2.\n1. Copy the table.\n2. Rename the table.')
const task = ask('gh', 'Email guard', NOW - 700, 'Run `gh auth login` in a terminal, then say "done".')
const review = ask('pr', 'Formula sandbox', NOW - 800, 'Review the draft PR https://github.com/acme/app/pull/42.')
const quiet: Presence = { session: 'quiet', label: 'Cleanup notes', state: 'running', at: NOW - 60_000 }

const seeded = (...asks: Ask[]) =>
  new Map<string, unknown>([
    ...asks.map(a => [`ask:${a.session}`, a] as [string, unknown]),
    ...asks.map(a => [`here:${a.session}`, { session: a.session, label: a.label, state: 'idle', at: a.at }] as [string, unknown]),
    ['here:quiet', quiet],
  ])

type On = Parameters<TestBody>[1]
type Engine = Parameters<TestBody>[0]

/** The time the engine reports. It moves on by `step` at each reading, as time does between a draw and a press. */
let clock = { now: NOW, step: 1000 }
/** The prompts the mod submitted in this session. */
let submitted: { text: string; origin: unknown }[] = []

/** Stands for the engine under the mod: one store shared by every session, and this session named `mine`. */
function engine(
  on: On,
  store = new Map<string, unknown>(),
  title = 'Login page work',
  onSet: (value: unknown) => void = () => undefined,
) {
  clock = { now: NOW, step: 1000 }
  submitted = []
  on('store.set', (_, e) => {
    store.set(e.key, e.value)
    onSet(e.value)
    return { value: undefined }
  })
  on('store.delete', (_, e) => {
    store.delete(e.key)
    return { value: undefined }
  })
  on('store.keys', () => ({ value: [...store.keys()] }))
  on('store.get', (_, e) => ({ value: store.get(e.key) }))
  on('session.id', () => ({ value: 'mine' }))
  on('session.messages', () => ({ value: [{ role: 'user', text: 'Fix the login page', toolUses: [] }] }))
  on('session.cwd', () => ({ value: '/work' }))
  on('clock.now', () => ({ value: (clock.now += clock.step) }))
  on('env.get', () => ({ value: '/home/me' }))
  // What grep prints for the transcript's title rows; `title` is '' for a session the app has not named.
  on('process.run', () => ({
    value: {
      exitCode: 0,
      stdout: title ? `"customTitle":"Old name"\n"customTitle":"${title}"\n` : '',
      stderr: '',
      isStdoutTruncated: false,
      isStderrTruncated: false,
    },
  }))
  on('model.complete', () => ({ value: { isAnswered: true, text: 'Which login fix to ship.\n', usage: {} } as never }))
  on('clock.every', () => ({ value: undefined }))
  on('command.register', () => ({ value: { command: 'asks' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.end', (_, e) => ({ sessionId: e.sessionId }))
  on('turn.complete', (_, e) => ({ text: e.answer }))
  on('prompt.submit', (_, e) => {
    submitted.push({ text: e.text, origin: e.origin })
    return { text: e.text }
  })

  return store
}

const turnEnds = ($: Engine, answer: string) =>
  $.turn.complete({ answer, durationMs: 1, isAborted: false, turnId: 't', reason: 'answer' })

/** What the pane left in the store for a session, oldest first. */
const sentTo = (store: Map<string, unknown>, session: string) =>
  [...store.entries()].filter(([k]) => k.startsWith(`send:${session}:`)).map(([, v]) => (v as { text: string }).text)

/** The pane as one session draws it, over a store that already holds `asks`. */
async function pane($: Engine, on: On, ...asks: Ask[]) {
  const store = engine(on, seeded(...asks))
  await $.session.start({ cwd: '/work', surface: 'desktop', isInteractive: true })

  return { store, ui: await $.ui.mount(PANE) }
}

test('a turn that ends with a move is saved, and the next prompt clears it', async ($, on) => {
  let store = new Map<string, unknown>()
  const topicSaved = new Promise<void>(saved => {
    store = engine(on, store, 'Login page work', value => (value as Ask).topic && saved())
  })

  await turnEnds($, '**Your move:** Choose A or B.\n\n**Changed:** One file.')
  // The subject is written after the ask is saved, by a call the turn does not wait for.
  await topicSaved
  const saved = store.get('ask:mine') as Ask
  expect(saved.move).toBe('Choose A or B.')
  expect(saved.label).toBe('Login page work')
  expect(saved.topic).toBe('Which login fix to ship')
  expect((store.get('here:mine') as Presence).state).toBe('idle')

  await $.prompt.submit({ text: 'A', origin: { kind: 'composer' }, wait: false })
  expect(store.has('ask:mine')).toBe(false)
})

test('a session the app has not named is called by its first prompt', async ($, on) => {
  const store = engine(on, new Map(), '')

  await turnEnds($, '**Your move:** Choose A or B.')
  expect((store.get('ask:mine') as Ask).label).toBe('Fix the login page')
})

test('a reply with no move block, or a slash command, keeps the ask; a move of nothing clears it', async ($, on) => {
  const store = engine(on)

  await turnEnds($, '**Your move:** Choose A or B.\n\n**Changed:** One file.')
  await $.prompt.submit({
    text: '/asks',
    origin: { kind: 'composer' },
    wait: false,
    command: { name: 'asks', args: '' },
  })
  expect(store.has('ask:mine')).toBe(true)

  await turnEnds($, 'The Asks pane opened.')
  expect((store.get('ask:mine') as Ask).move).toBe('Choose A or B.')

  await turnEnds($, '**Your move:** Nothing.\n\n**Changed:** Two files.')
  expect(store.has('ask:mine')).toBe(false)
})

test('a session that ends takes its ask, its presence and its unread messages with it', async ($, on) => {
  const store = engine(
    on,
    new Map<string, unknown>([
      ['ask:mine', ask('mine', 'Login page work', NOW, 'Ship it?')],
      ['here:mine', { session: 'mine', label: 'Login page work', state: 'idle', at: NOW }],
      ['send:mine:1', { session: 'mine', text: 'Yes', at: NOW }],
      ['ask:ui', choice],
    ]),
  )

  await $.session.end({ reason: 'other', sessionId: 'mine', resume: undefined as never })
  expect([...store.keys()]).toEqual(['ask:ui'])
})

test('the memo is the ask that blocks other work; the other asks are listed under it', async ($, on) => {
  const { ui } = await pane($, on, choice, review, task, goAhead)

  expect(await ui.find({ type: 'Text', text: /^4 waiting on you$/ })).toBeTruthy()
  expect((await ui.find({ type: 'Text', text: /^Run the import migration on the rehearsal copy\?$/ }))?.props.size).toBe('heading')
  expect(await ui.find({ type: 'Text', text: /^Blocks 2 more tasks$/ })).toBeTruthy()
  expect(await ui.find({ type: 'Text', text: /Claude recommends: Yes\. Not production\./ })).toBeTruthy()
  expect(await ui.find({ type: 'Text', text: /^UNDO$/ })).toBeTruthy()
  expect(await ui.find({ type: 'Text', text: /ALSO WAITING · 3/ })).toBeTruthy()
  // The test's clock moves on at every reading, so the minutes are not pinned.
  expect(await ui.find({ type: 'Text', text: /Need nothing: Cleanup notes \(running \d min\) · Login page work \(idle\)/ })).toBeTruthy()
  // One filled button in the whole pane. The surface draws the key beside the label, so the label has none.
  const filled = (await ui.findAll({ type: 'Button' })).filter(b => b.props.variant === 'primary')
  expect(filled.map(b => b.key)).toEqual(['yes-mig'])
  expect(filled[0]?.props.hotkey).toBe('y')
  expect(filled[0]?.text).toBe('Yes')
  // No separator bars: a Box one cell high is a thick bar on the desktop.
  expect((await ui.findAll({ type: 'Box' })).filter(b => b.props.height === 1)).toEqual([])
  // The keys that answer come first, then the keys that move about.
  expect(await ui.find({ type: 'Text', text: /^y yes · n no · r other answer · j next · k previous · p prompt a session$/ })).toBeTruthy()
  await ui.unmount()
})

test('Yes sends a fixed text with the question it answers, and moves the memo to the next ask', async ($, on) => {
  const { ui, store } = await pane($, on, choice, goAhead)

  await ui.press({ key: 'yes-mig' })
  expect(sentTo(store, 'mig')).toEqual([
    'Yes, go ahead.\n\n(This answers your ask: “Run the import migration on the rehearsal copy?”)',
  ])
  expect(store.has('ask:mig')).toBe(false)
  // The other session has not read the message yet, and the pane says so.
  expect(await ui.find({ type: 'Text', text: /Queued: “Yes, go ahead\.” for Database import, not picked up yet\./ })).toBeTruthy()
  expect((await ui.find({ type: 'Button', key: 'follow-up' }))?.props.hotkey).toBe('u')
  expect(await ui.find({ type: 'Text', text: /^Choose a route\.$/ })).toBeTruthy()
  await ui.unmount()
})

test('an answer no session picks up is dropped, and its ask comes back', async ($, on) => {
  const { ui, store } = await pane($, on, goAhead)

  await ui.press({ key: 'yes-mig' })
  expect(store.has('ask:mig')).toBe(false)
  clock.now += 3 * 60_000
  // Any turn's end reads the store again, as the 3-second poll does.
  await turnEnds($, 'Still working.')
  expect(sentTo(store, 'mig')).toEqual([])
  expect((store.get('ask:mig') as Ask).move).toBe(goAhead.move)
  expect(await ui.find({ type: 'Text', text: /Not delivered: “Yes, go ahead\.” Database import is not running, so the ask is back/ })).toBeTruthy()
  await ui.unmount()
})

test('a press that lands on an ask which only just appeared is not an answer to it', async ($, on) => {
  const second = ask('two', 'Second import', NOW - 400, 'Run the second migration too?')
  const { ui, store } = await pane($, on, goAhead, second)

  // Time stands still from here: the second "y" of a double press lands the moment the memo has changed.
  clock.now += 1000
  clock.step = 0
  await ui.press({ key: 'yes-mig' })
  expect(sentTo(store, 'mig').length).toBe(1)
  expect(await ui.find({ type: 'Text', text: /^Run the second migration too\?$/ })).toBeTruthy()
  await ui.press({ key: 'yes-two' })
  expect(sentTo(store, 'two')).toEqual([])
  expect(store.has('ask:two')).toBe(true)

  clock.now += 1000
  await ui.press({ key: 'yes-two' })
  expect(sentTo(store, 'two').length).toBe(1)
  await ui.unmount()
})

test('a more urgent ask that arrives waits in the list; the memo does not change under the reader', async ($, on) => {
  const { ui, store } = await pane($, on, choice)

  expect(await ui.find({ type: 'Text', text: /^Choose a route\.$/ })).toBeTruthy()
  store.set('ask:mig', goAhead)
  await turnEnds($, 'Still working.')
  expect((await ui.find({ type: 'Text', text: /^Choose a route\.$/ }))?.props.size).toBe('heading')
  expect(await ui.find({ type: 'Text', text: /ALSO WAITING · 1/ })).toBeTruthy()
  await ui.unmount()
})

test('an answer for this session is submitted at once, as the person', async ($, on) => {
  const { ui, store } = await pane($, on, ask('mine', 'Login page work', NOW - 400, 'Ship it?'))

  await ui.press({ key: 'yes-mine' })
  await ui.unmount()
  expect(submitted.map(s => s.text)).toEqual(['Yes, go ahead.\n\n(This answers your ask: “Ship it?”)'])
  expect((submitted[0]?.origin as { asUser?: boolean }).asUser).toBe(true)
  expect(sentTo(store, 'mine')).toEqual([])
})

test('an ask that is not a yes-or-no question has no Yes button, only an answer field and Seen', async ($, on) => {
  const { ui, store } = await pane($, on, ask('shot', 'Asks UI', NOW - 400, 'Send a screenshot and say what is unclear.'))

  expect(await ui.find({ type: 'Button', key: 'yes-shot' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /^ANSWER$/ })).toBeTruthy()
  expect((await ui.find({ type: 'Button', key: 'other' }))?.props.variant).toBe('primary')
  expect(await ui.find({ type: 'Text', text: /^r answer · e seen · p prompt a session$/ })).toBeTruthy()
  await ui.press({ key: 'other' })
  await ui.input({ key: 'reply-shot', text: 'The title is cut off' })
  await ui.unmount()
  expect(sentTo(store, 'shot')[0]).toMatch(/^The title is cut off\n/)
})

test('Next moves the memo; a choice has one digit key per option and the recommended one filled', async ($, on) => {
  const { ui, store } = await pane($, on, choice, goAhead)

  await ui.press({ key: 'next' })
  const second = await ui.find({ type: 'Button', key: 'option-ui-2' })
  expect(second?.props.variant).toBe('primary')
  expect(second?.props.hotkey).toBe('2')
  // The key chip the surface draws is the option's number, so the label does not repeat it.
  expect(second?.text).toBe('Pick')
  expect((await ui.find({ type: 'Button', key: 'option-ui-1' }))?.props.variant).toBe('secondary')
  await ui.press({ key: 'option-ui-2' })
  await ui.unmount()

  expect(sentTo(store, 'ui')[0]).toMatch(/^Option 2: Rename the table\.\n/)
})

test('a task for the person shows its command, and Done sends "done"', async ($, on) => {
  const { ui, store } = await pane($, on, task)

  expect((await ui.find({ type: 'Code' }))?.props.source).toBe('gh auth login')
  expect((await ui.find({ type: 'Button', key: 'copy' }))?.props.hotkey).toBe('c')
  await ui.press({ key: 'done-gh' })
  await ui.unmount()

  expect(sentTo(store, 'gh')[0]).toMatch(/^done\n/)
})

test('Seen clears a review with nothing sent, and Put back restores it', async ($, on) => {
  const { ui, store } = await pane($, on, review)

  expect((await ui.find({ type: 'Button', key: 'open' }))?.props.hotkey).toBe('o')
  await ui.press({ key: 'seen-pr' })
  expect(store.has('ask:pr')).toBe(false)
  expect(sentTo(store, 'pr')).toEqual([])
  expect(await ui.find({ type: 'Text', text: /Cleared the ask of Formula sandbox\. Nothing was sent\./ })).toBeTruthy()
  expect(await ui.find({ type: 'Text', text: /^Nothing waiting on you$/ })).toBeTruthy()

  await ui.press({ key: 'put-back' })
  expect((store.get('ask:pr') as Ask).move).toBe(review.move)
  await ui.unmount()
})

test('while a text field is open no button has a key, and the typed answer is what is sent', async ($, on) => {
  const { ui, store } = await pane($, on, goAhead)

  await ui.press({ key: 'other' })
  expect(await ui.find({ type: 'Input', key: 'reply-mig' })).toBeTruthy()
  expect((await ui.findAll({ type: 'Button' })).filter(b => b.props.hotkey !== undefined)).toEqual([])
  expect(await ui.find({ type: 'Text', text: /^Typing: every key goes into the field/ })).toBeTruthy()

  await ui.input({ key: 'reply-mig', text: 'Yes, but tell Robin first' })
  await ui.unmount()
  expect(sentTo(store, 'mig')[0]).toMatch(/^Yes, but tell Robin first\n/)
  expect(store.has('ask:mig')).toBe(false)
})

test('a new prompt goes to the session picked, and with nothing waiting the pane says so', async ($, on) => {
  const { ui, store } = await pane($, on)

  expect(await ui.find({ type: 'Text', text: /^Nothing waiting on you$/ })).toBeTruthy()
  expect((await ui.find({ type: 'Button', key: 'prompt' }))?.props.hotkey).toBe('p')
  await ui.press({ key: 'prompt' })
  await ui.select({ key: 'target', value: 'quiet' })
  await ui.input({ key: 'prompt-quiet', text: 'Summarise the open questions' })
  await ui.unmount()

  expect(sentTo(store, 'quiet')).toEqual(['Summarise the open questions'])
})
