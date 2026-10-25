import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

import { answerFacts } from '../hooks/status-pane'
import type { EndReport, StatusPaneState, TurnRecord } from '../types'

const ok = (stdout: string) => ({ exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false })
const PUSHED = 'To github.com:mickzijdel/dev-hooks.git\n   1111111..762caa3  main -> main\n'

type Message = { role: 'user' | 'assistant'; text: string }

// The engine beneath the module: $.state and $.store kept in memory, a session in a
// worktree of /home/m/dev-hooks, and Bash answering `bash` for every command.
function world(
  on: On,
  options: {
    pane?: unknown
    read?: () => unknown
    messages?: Message[]
    bash?: string
    env?: Record<string, string>
    ask?: Promise<void>
  } = {},
) {
  const state = new Map<string, unknown>(options.pane === undefined ? [] : [['statusPane', options.pane]])
  mock.env(on, options.env ?? {})
  const clock = mock.clock(on)
  on('state.get', (_$, e) => ({
    value: { value: e.key === 'statusPane' && options.read ? options.read() : state.get(e.key), version: 1 },
  }))
  on('state.set', (_$, e) => {
    state.set(e.key, e.value)
    return { value: { isSet: true as const, version: 2 } }
  })
  on('store.get', () => ({ value: undefined }))
  on('store.set', () => ({ value: undefined }))
  on('session.id', () => ({ value: 's1' }))
  on('session.cwd', () => ({ value: '/home/m/dev-hooks/.worktrees/x' }))
  on('session.messages', () => ({ value: (options.messages ?? []).map(m => ({ ...m, toolUses: [] })) }))
  on('turn.start', (_$, e) => ({ turnId: e.turnId }))
  on('turn.complete', (_$, e) => ({ text: e.answer }))
  on('tool.call', async (_$, e) => {
    if (e.tool === 'AskUserQuestion') await options.ask
    return e.tool === 'Bash' ? { result: {}, text: options.bash ?? '' } : { result: {} }
  })
  on('prompt.submit', (_$, e) => ({ text: e.text }))
  on('process.run', (_$, e) =>
    e.argv.includes('--git-common-dir') ? { value: ok('/home/m/dev-hooks/.git\n') } : { value: ok('') },
  )
  on('classic.Stop', () => ({}))
  const pane = () => (state.get('statusPane') as { shape: string; value: StatusPaneState } | undefined)?.value
  return { clock, pane }
}

const complete = (answer: string, turnId = 'u1') => ({ answer, turnId, durationMs: 5, isAborted: false, reason: 'answer' as const })
const edit = { tool: 'Edit' as const, file_path: '/r/a.py', old_string: 'a', new_string: 'b', replace_all: false }

test('a turn records its tool calls, edits and end report', async ($, on) => {
  const w = world(on)

  await $.turn.start({ text: 'fix it', turnId: 'u1' })
  await $.tool.call({ tool: 'Bash', command: 'ls' })
  await $.tool.call(edit)
  await $.turn.complete(complete('Done.\n**Changed:** a.py\n**Your move:** merge'))

  const t = w.pane()?.turns[0]
  expect([t?.typed, t?.calls, t?.edits, t?.end, t?.report?.yourMove]).toEqual([true, 2, 1, 'answer', ['merge']])
  expect(w.pane()?.turnsTotal).toBe(1)
})

test("a subagent's turn and tool calls stay out", async ($, on) => {
  const w = world(on)

  await $.turn.start({ text: 'fix it', turnId: 'u1' })
  await $.turn.start({ text: 'look', turnId: 'a1', agentId: 'ag' })
  await $.tool.call({ tool: 'Bash', command: 'ls', agentId: 'ag' })

  expect(w.pane()?.turns.map(t => [t.id, t.calls])).toEqual([['u1', 0]])
})

test('parallel tool calls lose no count', async ($, on) => {
  const w = world(on)

  await $.turn.start({ text: 'go', turnId: 'u1' })
  await Promise.all([1, 2, 3, 4, 5].map(() => $.tool.call({ tool: 'Bash', command: 'ls' })))

  expect(w.pane()?.turns[0]?.calls).toBe(5)
})

test('a commit in Bash output counts for its repo', async ($, on) => {
  const w = world(on, { bash: '[status-pane abc1234] feat: x\n 1 file changed' })

  await $.turn.start({ text: 'commit', turnId: 'u1' })
  await $.tool.call({ tool: 'Bash', command: 'git add a && git commit -m x' })
  expect(w.pane()?.repos.map(r => [r.repo, r.commits, r.lastPushAt])).toEqual([['dev-hooks', 1, undefined]])
})

test('a push marks the repo pushed', async ($, on) => {
  const w = world(on, { bash: PUSHED })

  await $.tool.call({ tool: 'Bash', command: 'git push origin main' })
  expect(w.pane()?.repos.map(r => [r.repo, r.lastPushAt !== undefined])).toEqual([['dev-hooks', true]])
})

test('the brief comes from the session at turn end', async ($, on) => {
  const brief = '**Doing:** a pane.\n**Done when:**\n- it opens\n'
  const w = world(on, { messages: [{ role: 'user', text: 'go' }, { role: 'assistant', text: brief }] })

  await $.turn.start({ text: 'go', turnId: 'u1' })
  await $.turn.complete(complete('Done.'))

  expect(w.pane()?.brief).toEqual({ doing: 'a pane.', doneWhen: ['it opens'] })
})

test('a stored value of another shape is declined, not read', async ($, on) => {
  const w = world(on, { pane: { shape: 'status-pane-0', value: { turns: 'garbage' } } })

  await $.turn.start({ text: 'go', turnId: 'u1' })

  expect(w.pane()?.turns.map(t => t.id)).toEqual(['u1'])
})

test('Stop records background work, keeping a task first-seen time', async ($, on) => {
  const w = world(on)
  const stop = {
    stop_hook_active: false,
    background_tasks: [{ id: 'b1', type: 'shell', status: 'running', description: 'npm test' }],
    session_crons: [{ id: 'c1', schedule: '*/5 * * * *', recurring: true, prompt: 'check the deploy' }],
  }

  await $.classic.Stop(stop)
  const first = w.pane()?.background
  await w.clock.advance(60_000)
  await $.classic.Stop(stop)

  expect(first?.map(b => b.label)).toEqual(['npm test', 'wakes up: check the deploy'])
  expect(w.pane()?.background).toEqual(first)
})

// ── Drawing and opening ──────────────────────────────────────────────────────────────
const PANE = {
  plugin: 'dev-hooks',
  component: 'Pane',
  requestId: 'session-status',
  props: {
    title: 'Session status',
    isFocused: false,
    bodyColumns: 60,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
} as const
const T0 = Date.UTC(2026, 9, 25, 8, 53)
const shaped = (value: StatusPaneState) => ({ shape: 'status-pane-2', value })
const base = (over: Partial<StatusPaneState> = {}): StatusPaneState => ({
  turns: [],
  turnsTotal: 0,
  brief: null,
  repos: [],
  background: [],
  startedAt: T0,
  ...over,
})
const rep = (over: Partial<EndReport> = {}): EndReport => ({ doneWhen: [], changed: [], notChecked: [], yourMove: [], ...over })
const ended = (over: Partial<TurnRecord> = {}): TurnRecord => ({
  id: 'u1',
  startedAt: T0,
  typed: true,
  endedAt: T0 + 60_000,
  end: 'answer',
  calls: 3,
  edits: 1,
  ...answerFacts('Done.'),
  report: null,
  ...over,
})
const SURFACES = ['terminal', 'vscode'] as const

test('the pane draws each state on the terminal and in VS Code', async ($, on) => {
  const cases: [StatusPaneState, RegExp][] = [
    [base({ turns: [ended({ report: rep({ yourMove: ['push', 'merge'] }) })], turnsTotal: 1 }), /● Waiting on you/],
    [base({ turns: [ended({ endedAt: undefined, end: undefined })], turnsTotal: 1 }), /● Working/],
    [base({ turns: [ended(answerFacts('I fixed it.'))], turnsTotal: 1 }), /● Turn ended, no end report/],
    [base({ turns: [ended({ report: rep() })], turnsTotal: 1 }), /● Done/],
    [base(), /● No turns yet/],
  ]
  let current = base()
  world(on, { read: () => shaped(current) })
  for (const [pane, line] of cases) {
    current = pane
    for (const surface of SURFACES) {
      const ui = await $.ui.mount({ ...PANE, surface })
      expect([surface, (await ui.find({ type: 'Text', text: line }))?.text?.match(line)?.[0]]).toEqual([
        surface,
        line.source,
      ])
      await ui.unmount()
    }
  }
})

test('Your move numbers its items, and the Summarize button shows only without a report', async ($, on) => {
  let current = base({ turns: [ended({ report: rep({ yourMove: ['push', 'merge'] }) })], turnsTotal: 1 })
  world(on, { read: () => shaped(current) })
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Text', text: /^1\. push$/ }))?.text).toBe('1. push')
    expect(await ui.find({ key: 'summarize' })).toBeUndefined()
    await ui.unmount()
  }
  current = base({ turns: [ended(answerFacts('I fixed it.'))], turnsTotal: 1 })
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect(await ui.find({ key: 'summarize' })).toBeDefined()
    await ui.unmount()
  }
})

test('long lists end in "+N more" and a long Doing is clamped to two lines', async ($, on) => {
  const moves = ['a', 'b', 'c', 'd', 'e', 'f', 'g']
  const brief = { doing: 'x'.repeat(755), doneWhen: [] }
  world(on, { read: () => shaped(base({ turns: [ended({ report: rep({ yourMove: moves }) })], turnsTotal: 1, brief })) })
  const ui = await $.ui.mount({ ...PANE, surface: 'vscode' })
  expect((await ui.find({ type: 'Text', text: /\+3 more/ }))?.text).toBe('+3 more')
  expect((await ui.find({ type: 'Text', text: /^x+…$/ }))?.text?.length).toBeLessThanOrEqual(120)
  await ui.unmount()
})

// What session.start reads, as stop-takeover.test.ts answers it, and every pane opened.
function startWorld(on: On, env: Record<string, string> = {}) {
  const opened: string[] = []
  world(on, { env })
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('store.keys', () => ({ value: [] }))
  on('fs.read', () => ({ value: JSON.stringify({ hooks: {} }) }))
  on('env.set', () => ({ value: {} }))
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('session.attach', (_$, e) => ({ clientId: e.clientId }))
  on('ui.open', (_$, e) => {
    opened.push(e.id)
    return { value: { isPlaced: true as const } }
  })
  return opened
}

test('the pane opens by itself in VS Code, not in a terminal, and not when switched off', async ($, on) => {
  const opened = startWorld(on)
  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
  expect(opened).toEqual([])
  await $.session.start({ cwd: '/repo', surface: 'vscode', isInteractive: true })
  expect(opened).toEqual(['session-status'])
})

test('switched off, the pane never opens by itself', async ($, on) => {
  const opened = startWorld(on, { DEV_HOOKS_STATUS_PANE: 'false' })
  await $.session.start({ cwd: '/repo', surface: 'vscode', isInteractive: true })
  await $.session.attach({ surface: 'vscode', clientId: 'c1' })
  expect(opened).toEqual([])
})

test('a VS Code window attaching later opens it, and /session-status opens it anywhere', async ($, on) => {
  const opened = startWorld(on)
  await $.session.attach({ surface: 'vscode', clientId: 'c1' })
  expect(opened).toEqual(['session-status'])
  const ran = await $.command.run({ command: 'session-status', args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 80 } })
  expect([ran.text, opened]).toEqual(['Session status pane opened.', ['session-status', 'session-status']])
})

// ── Summarize and the clock ──────────────────────────────────────────────────────────
const USAGE = { input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 }
const unreported = () => shaped(base({ turns: [ended(answerFacts('I fixed it.'))], turnsTotal: 1 }))

test('Summarize asks once, and its answer stands in for the missing report', async ($, on) => {
  const w = world(on, { pane: unreported() })
  const asked: string[] = []
  on('model.fork', (_$, e) => {
    asked.push(e.prompt)
    return { value: { isAnswered: true as const, text: 'Status: Done\nYour move:\n- push', usage: USAGE } }
  })

  const ui = await $.ui.mount({ ...PANE, surface: 'vscode' })
  await ui.press({ key: 'summarize' })
  await ui.unmount()

  expect(asked.length).toBe(1)
  expect(w.pane()?.turns[0]?.summary?.yourMove).toEqual(['push'])
  const again = await $.ui.mount({ ...PANE, surface: 'vscode' })
  expect((await again.find({ type: 'Text', text: /● Waiting on you/ }))?.text).toBe('● Waiting on you')
  expect(await again.find({ key: 'summarize' })).toBeUndefined()
  await again.unmount()
})

test('a failed Summarize keeps the warning and says why', async ($, on) => {
  const w = world(on, { pane: unreported() })
  on('model.fork', () => ({ value: { isAnswered: false as const, reason: 'api-error' as const, status: 529, error: 'overloaded' as const, usage: USAGE } }))

  const ui = await $.ui.mount({ ...PANE, surface: 'vscode' })
  await ui.press({ key: 'summarize' })
  await ui.unmount()

  expect(w.pane()?.turns[0]?.summaryError).toBe('api-error')
  const again = await $.ui.mount({ ...PANE, surface: 'vscode' })
  expect((await again.find({ type: 'Text', text: /summary failed/ }))?.text).toBe('summary failed: api-error')
  await again.unmount()
})

test('the open pane redraws each minute, and stops once it is closed', async ($, on) => {
  const w = world(on, { pane: shaped(base()) })
  let isOpen = true
  const redraws: string[] = []
  on('ui.panes', () => ({
    value: isOpen ? [{ id: 'session-status', title: 'Session status', isShown: true, isFocused: false, isPlaced: true }] : [],
  }))
  on('ui.invalidate', (_$, e) => {
    redraws.push(e.event)
    return { value: undefined }
  })

  const ui = await $.ui.mount({ ...PANE, surface: 'vscode' })
  await w.clock.advance(60_000)
  expect(redraws).toEqual(['ui.render'])
  isOpen = false
  await w.clock.advance(60_000)
  await w.clock.advance(60_000)
  expect(redraws).toEqual(['ui.render'])
  await ui.unmount()
})

// ── Found by the final review ────────────────────────────────────────────────────────
const SCHEDULED = { kind: 'scheduled-trigger' as const }
const COMPOSER = { kind: 'composer' as const }

test("a scheduled wake-up's turn is not typed, so it can't clear an earlier ask", async ($, on) => {
  const w = world(on)

  await $.prompt.submit({ text: 'merge it', wait: false, origin: COMPOSER })
  await $.turn.start({ text: 'merge it', turnId: 'u1' })
  await $.turn.complete(complete('**Your move:** approve the migration', 'u1'))
  await $.prompt.submit({ text: 'check the deploy', wait: false, origin: SCHEDULED })
  await $.turn.start({ text: 'check the deploy', turnId: 'u2' })

  expect(w.pane()?.turns.map(t => t.typed)).toEqual([true, false])
})

test('a turn waiting on AskUserQuestion is marked asking until it is answered', async ($, on) => {
  let answer = () => {}
  const w = world(on, { ask: new Promise<void>(resolve => (answer = resolve)) })

  await $.turn.start({ text: 'go', turnId: 'u1' })
  const asked = $.tool.call({ tool: 'AskUserQuestion', questions: [] })
  await w.clock.advance(0)
  expect(w.pane()?.turns[0]?.asking).toBe(true)
  answer()
  await asked

  expect(w.pane()?.turns[0]?.asking).toBe(false)
})

test('the stored record keeps a line of each answer, not the answer', async ($, on) => {
  const w = world(on)

  await $.turn.start({ text: 'go', turnId: 'u1' })
  await $.turn.complete(complete(`Start.\n${'x'.repeat(20_000)}\nShall I push?`))

  expect(JSON.stringify(w.pane()).length).toBeLessThan(2_000)
  expect(w.pane()?.turns[0]?.asksQuestion).toBe(true)
})

test('every row is clamped, not only Doing', async ($, on) => {
  const long = `do ${'y'.repeat(749)}`
  world(on, { read: () => shaped(base({ turns: [ended({ report: rep({ yourMove: [long] }) })], turnsTotal: 1 })) })
  const ui = await $.ui.mount({ ...PANE, surface: 'vscode' })
  expect((await ui.find({ type: 'Text', text: /^do y+…$/ }))?.text?.length).toBeLessThanOrEqual(120)
  await ui.unmount()
})

test("the pane's opening can't cut session start short", async ($, on) => {
  const marked: (string | undefined)[] = []
  on('env.get', (_$, e) => {
    if (e.name === 'DEV_HOOKS_STATUS_PANE') throw new Error('env unavailable')
    return { value: undefined }
  })
  on('env.set', (_$, e) => {
    if (e.name === 'DEV_HOOKS_MOD_SESSION') marked.push(e.value)
    return { value: {} }
  })
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('session.id', () => ({ value: 's1' }))
  on('store.keys', () => ({ value: [] }))
  on('store.get', () => ({ value: undefined }))
  on('state.get', () => ({ value: { value: undefined, version: 1 } }))
  on('fs.read', (_$, e) =>
    ({ value: String(e.path).endsWith('plugin.json') ? JSON.stringify({ version: '9.9.9' }) : JSON.stringify({ hooks: { Stop: [{ hooks: [{ type: 'command', command: 'bash a.sh' }] }] } }) }),
  )
  on('session.start', (_$, e) => ({ cwd: e.cwd }))

  await $.session.start({ cwd: '/repo', surface: 'vscode', isInteractive: true })

  expect(marked).toEqual(['s1'])
})
