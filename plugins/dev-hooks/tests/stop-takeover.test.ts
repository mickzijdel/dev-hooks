import type { On } from 'claude-code'
import { expect, test } from 'claude-code/testing'

const HOOKS = JSON.stringify({ hooks: { Stop: [{ hooks: [{ type: 'command', command: 'bash a.sh' }] }] } })

// Answers what session start and Stop read, and records in order what the module
// marks, when the hooks beneath it run, and which Stop commands it runs itself.
function world(on: On, store: Record<string, unknown>, options: { version?: string; canMark?: boolean; breaksOrchestration?: boolean; markedFor?: string } = {}) {
  const log: string[] = []
  const env = new Map<string, string | undefined>([['DEV_HOOKS_MOD_SESSION', options.markedFor]])
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('session.id', () => ({ value: 's1' }))
  on('store.keys', () => ({ value: Object.keys(store) }))
  on('store.get', (_$, e) => ({ value: store[e.key] }))
  on('store.set', (_$, e) => {
    store[e.key] = e.value
    return { value: undefined }
  })
  on('fs.read', (_$, e) => ({
    value: String(e.path).endsWith('plugin.json')
      ? JSON.stringify({ name: 'dev-hooks', version: options.version ?? '9.9.9' })
      : HOOKS,
  }))
  on('fs.write', () => ({ value: undefined }))
  on('env.get', (_$, e) => {
    // The orchestration reads this after the hooks beneath ran; the takeover never does.
    if (options.breaksOrchestration && e.name === 'CLAUDE_CODE_ENTRYPOINT') throw new Error('env unavailable')
    return { value: env.get(e.name) }
  })
  on('env.set', (_$, e) => {
    if (e.name === 'DEV_HOOKS_MOD_SESSION') {
      if (options.canMark === false) throw new Error('env unavailable')
      log.push(`mark:${e.value}`)
    }
    env.set(e.name, e.value)
    return { value: {} }
  })
  on('process.run', (_$, e) => {
    if (e.argv[0] === 'bash') log.push(`run:${e.argv[2]}`)
    return { value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('turn.start', (_$, e) => ({ turnId: e.turnId }))
  on('classic.Stop', () => {
    log.push('beneath')
    return {}
  })
  return log
}

const START = { cwd: '/repo', surface: 'terminal', isInteractive: true } as const
const STOP = { session_id: 's1', cwd: '/repo', stop_hook_active: false }

// A plugin seated above can send classic.Stop past this module (Claude Code's built-in
// security plugin does, in a team organization). A mark made at session start would then
// silence the command hooks with nothing running them.
test('session start leaves the session unmarked', async ($, on) => {
  const log = world(on, {})

  await $.session.start(START)

  expect(log).toEqual([])
})

test('a Stop that reaches the module marks the session before the hooks beneath run, then runs the Stop commands', async ($, on) => {
  const log = world(on, {})

  await $.session.start(START)
  expect(log).toEqual([])
  await $.classic.Stop(STOP)

  expect(log).toEqual(['mark:s1', 'beneath', 'run:bash a.sh'])
})

test('a version whose Stop orchestration failed leaves Stop to the command hooks', async ($, on) => {
  const log = world(on, { stopOrchestrationFailed: '9.9.9' })

  await $.session.start(START)
  expect(log).toEqual([])
  await $.classic.Stop(STOP)

  expect(log).toEqual(['beneath'])
})

test('a new version tries the takeover again after an older one failed', async ($, on) => {
  const log = world(on, { stopOrchestrationFailed: '9.9.8' })

  await $.session.start(START)
  expect(log).toEqual([])
  await $.classic.Stop(STOP)

  expect(log).toEqual(['mark:s1', 'beneath', 'run:bash a.sh'])
})

test('a marked session is unmarked once the takeover is refused, as after a failure in another session', async ($, on) => {
  const store: Record<string, unknown> = {}
  const log = world(on, store)

  await $.session.start(START)
  await $.classic.Stop(STOP)
  store.stopOrchestrationFailed = '9.9.9'
  log.length = 0
  await $.classic.Stop(STOP)

  expect(log).toEqual(['mark:undefined', 'beneath'])
})

test('a failed orchestration hands Stop back for the rest of the session, even if the failure was not stored', async ($, on) => {
  const store: Record<string, unknown> = {}
  const log = world(on, store, { breaksOrchestration: true })
  const stop = { ...STOP, session_id: 's-broken' }

  await $.classic.Stop(stop)
  expect(log).toEqual(['mark:s-broken', 'beneath', 'run:bash a.sh', 'mark:undefined'])
  expect(store.stopOrchestrationFailed).toBe('9.9.9')
  delete store.stopOrchestrationFailed
  log.length = 0
  await $.classic.Stop(stop)

  expect(log).toEqual(['beneath'])
})

const TURN = { text: 'go', turnId: 'u1' }

// The mark is proof for one Stop only: a later Stop can be sent past the module, and a
// session opened before this version still carries the mark its session start made.
test('a turn start clears the mark a Stop or an older version left on this session', async ($, on) => {
  const log = world(on, {}, { markedFor: 's1' })

  await $.turn.start(TURN)
  expect(log).toEqual(['mark:undefined'])
  await $.classic.Stop(STOP)
  await $.turn.start({ ...TURN, turnId: 'u2' })

  expect(log).toEqual(['mark:undefined', 'mark:s1', 'beneath', 'run:bash a.sh', 'mark:undefined'])
})

test("a turn start leaves another session's mark alone", async ($, on) => {
  const log = world(on, {}, { markedFor: 'some-parent-session' })

  await $.turn.start(TURN)

  expect(log).toEqual([])
})

test("a subagent's turn start leaves the mark in place", async ($, on) => {
  const log = world(on, {}, { markedFor: 's1' })

  await $.turn.start({ ...TURN, agentId: 'a1' })

  expect(log).toEqual([])
})

test("a session the module can't mark keeps its command hooks and gets no second run", async ($, on) => {
  const log = world(on, {}, { canMark: false })

  await $.session.start(START)
  expect(log).toEqual([])
  await $.classic.Stop(STOP)

  expect(log).toEqual(['beneath'])
})
