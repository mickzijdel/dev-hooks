import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

import type { Run } from '../hooks/ci-watch'

const SHA = '762caa326fb1da9dda327189ee7b075a5677cc09'
const PUSHED = 'To github.com:mickzijdel/dev-hooks.git\n   1111111..762caa3  main -> main\n'
const ok = (stdout: string) => ({ exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false })
const failed = { exitCode: 128, stdout: '', stderr: 'fatal', isStdoutTruncated: false, isStderrTruncated: false }
const run = (over: Partial<Run> = {}): Run => ({
  databaseId: 37111047147,
  workflowName: 'ci',
  status: 'completed',
  conclusion: 'success',
  headSha: SHA,
  url: 'https://github.com/mickzijdel/dev-hooks/actions/runs/37111047147',
  event: 'push',
  ...over,
})

// The engine beneath the module: a repo at /repo with a workflow, gh answering
// `runs`, and every status, toast, note and prompt the module produces recorded.
function world(on: On, options: { env?: Record<string, string>; workflows?: string[] } = {}) {
  const w = {
    runs: [] as Run[],
    ghCalls: [] as string[][],
    statuses: [] as (string | undefined)[],
    toasts: [] as string[],
    prompts: [] as string[],
    logs: [] as string[],
  }
  mock.env(on, options.env ?? {})
  on('session.cwd', () => ({ value: '/repo' }))
  on('fs.list', () => ({
    value: (options.workflows ?? ['ci.yml']).map(name => ({ name, kind: 'file' as const, size: 1, mtimeMs: 0, isLink: false })),
  }))
  on('process.run', (_$, e) => {
    const argv = [...e.argv]
    if (argv[0] === 'gh') {
      w.ghCalls.push(argv)
      return { value: ok(JSON.stringify(w.runs)) }
    }
    if (argv.includes('--show-toplevel')) return { value: ok('/repo\n') }
    if (argv.includes('rev-parse')) return { value: String(argv.at(-1)).startsWith('762caa3') ? ok(`${SHA}\n`) : failed }
    return { value: failed }
  })
  on('ui.status', (_$, e) => {
    w.statuses.push(e.text)
    return { value: undefined }
  })
  on('ui.toast', (_$, e) => {
    w.toasts.push(e.text)
    return { value: undefined }
  })
  on('ui.log', (_$, e) => {
    w.logs.push(e.text)
    return { value: undefined }
  })
  on('prompt.submit', (_$, e) => {
    w.prompts.push(e.text)
    return { text: e.text }
  })
  // The kit has nothing beneath a plugin's own $.session.append (a test hook never sees
  // it), so the call rejects and the module logs that: proof the note went that way.
  const appended = () => w.logs.some(l => l.includes('no implementation for session.append'))
  return Object.assign(w, { appended })
}

const push = (on: On, text = PUSHED) => on('tool.call', () => ({ result: { stdout: '', stderr: text }, text }))

test('a push is watched until its run passes, then noted for the model without waking it', async ($, on) => {
  const clock = mock.clock(on)
  const w = world(on)
  push(on)

  const ran = await $.tool.call({ tool: 'Bash', command: 'git push origin main' })

  expect(ran.context?.[0]).toContain('Watching the GitHub Actions run(s) for mickzijdel/dev-hooks@762caa3')
  expect(w.statuses.at(-1)).toBe('CI: dev-hooks@762caa3 waiting for its run')

  w.runs = [run({ status: 'in_progress', conclusion: '' })]
  await clock.advance(3_000)
  expect(w.ghCalls[0]).toEqual(['gh', 'run', 'list', '--repo', 'mickzijdel/dev-hooks', '--commit', SHA, '--json', 'databaseId,workflowName,status,conclusion,headSha,url,event', '--limit', '50'])
  expect(w.statuses.at(-1)).toBe('CI: dev-hooks@762caa3 0/1 runs done')

  w.runs = [run()]
  await clock.advance(15_000)
  expect(w.statuses.at(-1)).toBeUndefined()
  expect(w.toasts).toEqual(['✓ CI passed · dev-hooks@762caa3'])
  expect(w.appended()).toBe(true)
  expect(w.prompts).toEqual([])
})

test('a failed run wakes the session with a prompt naming the failure', async ($, on) => {
  const clock = mock.clock(on)
  const w = world(on)
  push(on)
  w.runs = [run({ databaseId: 35830926133, conclusion: 'failure' })]

  await $.tool.call({ tool: 'Bash', command: 'git push' })
  await clock.advance(3_000)

  expect(w.toasts).toEqual(['✗ CI failed · dev-hooks@762caa3: ci'])
  expect(w.prompts[0]).toContain('CI FAILED')
  expect(w.prompts[0]).toContain('gh run view 35830926133')
  expect(w.appended()).toBe(false)
})

test('a run that never appears is given up on and noted', async ($, on) => {
  const clock = mock.clock(on)
  const w = world(on)
  push(on)

  await $.tool.call({ tool: 'Bash', command: 'git push' })
  for (let i = 0; i < 30; i++) await clock.advance(5_000)

  expect(w.toasts).toEqual(['? No CI run appeared · dev-hooks@762caa3'])
  expect(w.appended()).toBe(true)
})

test('DEV_HOOKS_CI_WATCH=false turns the watch off', async ($, on) => {
  const w = world(on, { env: { DEV_HOOKS_CI_WATCH: 'false' } })
  push(on)

  const optedOut = await $.tool.call({ tool: 'Bash', command: 'git push' })
  expect(optedOut.context).toBeUndefined()
  expect(w.statuses).toEqual([])
})

test('no watch without a push that reached GitHub with workflows to run', async ($, on) => {
  const w = world(on, { workflows: [] })
  let text = PUSHED
  on('tool.call', () => ({ result: {}, text }))

  for (const command of ['git status', 'git push --dry-run']) {
    expect((await $.tool.call({ tool: 'Bash', command })).context).toBeUndefined()
  }
  expect((await $.tool.call({ tool: 'Bash', command: 'git push' })).context).toBeUndefined() // no workflows
  text = 'Everything up-to-date\n'
  expect((await $.tool.call({ tool: 'Bash', command: 'git push' })).context).toBeUndefined()
  expect(w.statuses).toEqual([])
})

test('a push to a non-GitHub remote is not watched', async ($, on) => {
  const w = world(on)
  push(on, 'To git@gitlab.com:o/r.git\n   1111111..762caa3  main -> main\n')

  expect((await $.tool.call({ tool: 'Bash', command: 'git push' })).context).toBeUndefined()
  expect(w.statuses).toEqual([])
})

function startWorld(on: On, env: Record<string, string>) {
  const marked: (string | undefined)[] = []
  mock.env(on, env)
  mock.store(on)
  on('session.id', () => ({ value: 's1' }))
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('fs.read', () => ({ value: '{}' }))
  on('env.set', (_$, e) => {
    if (e.name === 'DEV_HOOKS_CI_WATCH_SESSION') marked.push(e.value)
    return { value: undefined }
  })
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  return marked
}

const START = { cwd: '/repo', surface: 'terminal', isInteractive: true } as const

test('session start marks the session, so ci-watch-reminder.sh stands down', async ($, on) => {
  const marked = startWorld(on, {})

  await $.session.start(START)

  expect(marked).toEqual(['s1'])
})

test('with the opt-out set, session start leaves the session unmarked', async ($, on) => {
  const marked = startWorld(on, { DEV_HOOKS_CI_WATCH: 'false' })

  await $.session.start(START)

  expect(marked).toEqual([])
})
