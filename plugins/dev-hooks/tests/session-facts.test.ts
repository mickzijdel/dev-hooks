import type { On } from 'claude-code'
import { expect, test } from 'claude-code/testing'

import { netAdded } from '../hooks/register'
import type { Facts, NudgeRecord } from '../types'

const DAY = 86_400_000

// The test's $ has no store noun to read back through, so answer the
// plugin's $.session.id, $.store and $.process.run from memory the test sees.
function world(on: On, options: { root?: string | null; store?: Record<string, unknown> } = {}) {
  const store = new Map<string, unknown>(Object.entries(options.store ?? {}))
  const root = options.root === undefined ? '/repo' : options.root
  on('session.id', () => ({ value: 's1' }))
  on('store.get', (_$, e) => ({ value: store.get(e.key) }))
  on('store.set', (_$, e) => {
    store.set(e.key, JSON.parse(JSON.stringify(e.value)))
    return { value: undefined }
  })
  on('store.delete', (_$, e) => {
    store.delete(e.key)
    return { value: undefined }
  })
  on('store.keys', () => ({ value: [...store.keys()] }))
  const written = new Map<string, string>()
  on('env.get', (_$, e) => ({ value: e.name === 'HOME' ? '/home/u' : undefined }))
  on('fs.exists', (_$, e) => ({ value: e.path === '/home/u/.claude/automation-review' }))
  on('fs.write', (_$, e) => {
    written.set(e.path, e.text)
    return { value: undefined }
  })
  on('process.run', () => ({
    value: root === null
      ? { exitCode: 128, stdout: '', stderr: 'fatal: not a git repository', isStdoutTruncated: false, isStderrTruncated: false }
      : { exitCode: 0, stdout: `${root}\n`, stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
  }))
  return { store, written, facts: () => store.get('facts:s1') as Facts }
}

const patch = (...lines: string[]) => ({ result: { structuredPatch: [{ oldStart: 1, oldLines: 0, newStart: 1, newLines: 0, lines }] }, text: 'ok' })

test('netAdded counts net lines, not every + line', async () => {
  expect(netAdded([{ lines: ['-three', '+three', '+four', '+five'] }], undefined)).toBe(2)
  expect(netAdded([{ lines: ['-a', '-b', '+c'] }], undefined)).toBe(-1)
})

test('netAdded counts a created file by its lines, ignoring the trailing newline', async () => {
  expect(netAdded([], 'a\nb\nc\n')).toBe(3)
  expect(netAdded(undefined, 'a\nb')).toBe(2)
  expect(netAdded([], '')).toBe(0)
})

test('an Edit is recorded under its repo root with its net growth', async ($, on) => {
  const w = world(on)
  on('tool.call', () => patch('-three', '+three', '+four'))

  await $.tool.call({ tool: 'Edit', file_path: '/repo/src/a.ts', old_string: 'three', new_string: 'three\nfour' })

  expect(w.facts().repos).toEqual([{ root: '/repo', files: ['/repo/src/a.ts'], added: 1, bySubagent: 0 }])
})

test('an edit outside any git repo is kept, under a null root', async ($, on) => {
  const w = world(on, { root: null })
  on('tool.call', () => ({ result: { type: 'create', structuredPatch: [] }, text: 'ok' }))

  await $.tool.call({ tool: 'Write', file_path: '/home/u/.claude/memory/x.md', content: 'a\nb\n' })

  expect(w.facts().repos).toEqual([{ root: null, files: ['/home/u/.claude/memory/x.md'], added: 2, bySubagent: 0 }])
})

test('a denied or failed edit records nothing', async ($, on) => {
  const w = world(on)
  on('tool.call', () => ({ deny: 'no' }))

  await $.tool.call({ tool: 'Edit', file_path: '/repo/a.ts', old_string: 'a', new_string: 'b' })

  expect(w.facts()).toBeUndefined()
})

test('parallel edits are not lost to an interleaved read-modify-write', async ($, on) => {
  const w = world(on)
  on('tool.call', () => patch('+x'))

  await Promise.all(
    ['a', 'b', 'c', 'd'].map(n =>
      $.tool.call({ tool: 'Edit', file_path: `/repo/${n}.ts`, old_string: 'q', new_string: 'x' }),
    ),
  )

  expect(w.facts().repos[0]?.added).toBe(4)
  expect(w.facts().repos[0]?.files).toHaveLength(4)
})

test('a skill expansion is recorded by name', async ($, on) => {
  const w = world(on)
  on('skill.prompt', (_$, e) => ({ text: e.text }))

  await $.skill.prompt({ skill: 'dev-hooks:compress-comments', text: 'body' })

  expect(w.facts().skills.map(s => s.skill)).toEqual(['dev-hooks:compress-comments'])
})

test('session start prunes facts of sessions idle for over 30 days', async ($, on) => {
  const now = Date.now()
  const w = world(on, {
    store: {
      'facts:old': { updatedAt: now - 31 * DAY, skills: [], agents: [], repos: [], stops: [] },
      'facts:recent': { updatedAt: now - 2 * DAY, skills: [], agents: [], repos: [], stops: [] },
      unrelated: 1,
    },
  })
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('session.start', (_$, e) => ({ cwd: e.cwd }))

  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })

  expect([...w.store.keys()].sort()).toEqual(['facts:recent', 'unrelated'])
})

test('an Edit records when the file was last touched, the evidence window for Stop nudges', async ($, on) => {
  const w = world(on)
  on('tool.call', () => patch('+x'))
  const before = Date.now()

  await $.tool.call({ tool: 'Edit', file_path: '/repo/a.ts', old_string: 'q', new_string: 'x' })

  expect(w.facts().lastEdit?.['/repo/a.ts']).toBeGreaterThanOrEqual(before)
})

const pendingReview = (at: number): Facts => ({
  updatedAt: at,
  skills: [],
  agents: [],
  repos: [],
  stops: [],
  nudges: [{ hook: 'review-reminder', at, summary: '[review-reminder] run a review' }],
})

test('session end resolves a pending nudge as unknown and logs it across sessions', async ($, on) => {
  const at = Date.now() - 60_000
  const w = world(on, { store: { 'facts:s1': pendingReview(at) } })
  on('session.end', (_$, e) => ({ sessionId: e.sessionId }))

  await $.session.end({ reason: 'other', sessionId: 's1', resume: { id: 's1' } })

  expect(w.facts().nudges?.[0]?.outcome).toBe('unknown')
  const log = w.store.get('nudgeOutcomes') as NudgeRecord[]
  expect(log.map(r => [r.hook, r.session, r.outcome])).toEqual([['review-reminder', 's1', 'unknown']])
  const exported = JSON.parse(w.written.get('/home/u/.claude/automation-review/stop-nudges.json') ?? '{}')
  expect(exported.last7Days).toEqual([{ hook: 'review-reminder', fired: 1, acted: 0, ignored: 0, declined: 0, unknown: 1 }])
})

test('session start sweeps abandoned sessions\' pending nudges into the log, leaving live ones', async ($, on) => {
  const now = Date.now()
  const w = world(on, {
    store: { 'facts:dead': pendingReview(now - 7 * 3_600_000), 'facts:live': pendingReview(now - 60_000) },
  })
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('session.start', (_$, e) => ({ cwd: e.cwd }))

  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })

  expect((w.store.get('facts:dead') as Facts).nudges?.[0]?.outcome).toBe('unknown')
  expect((w.store.get('facts:live') as Facts).nudges?.[0]?.outcome).toBeUndefined()
  expect((w.store.get('nudgeOutcomes') as NudgeRecord[]).map(r => r.session)).toEqual(['dead'])
})
