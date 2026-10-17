import type { On } from 'claude-code'
import { expect, test } from 'claude-code/testing'

const HOOKS = JSON.stringify({ hooks: { Stop: [{ hooks: [{ type: 'command', command: 'bash a.sh' }] }] } })

// Answers what session.start reads, and records what it marks.
function world(on: On, store: Record<string, unknown>, version = '9.9.9') {
  const marked: (string | undefined)[] = []
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('session.id', () => ({ value: 's1' }))
  on('store.keys', () => ({ value: Object.keys(store) }))
  on('store.get', (_$, e) => ({ value: store[e.key] }))
  on('fs.read', (_$, e) => ({
    value: String(e.path).endsWith('plugin.json') ? JSON.stringify({ name: 'dev-hooks', version }) : HOOKS,
  }))
  on('env.set', (_$, e) => {
    if (e.name === 'DEV_HOOKS_MOD_SESSION') marked.push(e.value)
    return { value: undefined }
  })
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  return marked
}

const START = { cwd: '/repo', surface: 'terminal', isInteractive: true } as const

test('session start takes the Stop hooks over by marking the session', async ($, on) => {
  const marked = world(on, {})

  await $.session.start(START)

  expect(marked).toEqual(['s1'])
})

test('a version whose Stop orchestration failed leaves Stop to the command hooks', async ($, on) => {
  const marked = world(on, { stopOrchestrationFailed: '9.9.9' })

  await $.session.start(START)

  expect(marked).toEqual([])
})

test('a new version tries the takeover again after an older one failed', async ($, on) => {
  const marked = world(on, { stopOrchestrationFailed: '9.9.8' })

  await $.session.start(START)

  expect(marked).toEqual(['s1'])
})
