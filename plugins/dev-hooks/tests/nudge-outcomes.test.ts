import { expect, test } from 'claude-code/testing'

import {
  actedRate,
  formatNudgeStats,
  hookName,
  mergeNudgeLog,
  newNudge,
  resolveNudge,
  resolvePending,
  summarizeNudges,
} from '../hooks/nudge-outcomes'
import type { Facts, Nudge, NudgeRecord } from '../types'

const T = 1_791_015_800_000
const DAY = 86_400_000

const facts = (over: Partial<Facts> = {}): Facts => ({ updatedAt: T, skills: [], agents: [], repos: [], stops: [], ...over })
const atStop = (f: Facts, over: { refired?: string[]; lastMessage?: string } = {}) => ({
  facts: f,
  refired: over.refired ?? [],
  lastMessage: over.lastMessage,
  atStop: true,
})
const nudge = (hook: string, summary = `[${hook}] x`, files?: string[]): Nudge => ({ hook, at: T, summary, ...(files ? { files } : {}) })

test('hookName names a Stop command by its script', async () => {
  expect(hookName('bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/review-reminder.sh"')).toBe('review-reminder')
  expect(hookName('bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/verify-work.sh"')).toBe('verify-work')
})

test('newNudge keeps the first line and, for hooks that list files, the files', async () => {
  const reason = '[missing-test] new source files without tests this session. Add tests:\n  src/a.ts\n  lib/b.py'
  expect(newNudge('missing-test-reminder', reason, T)).toEqual({
    hook: 'missing-test-reminder',
    at: T,
    summary: '[missing-test] new source files without tests this session. Add tests:',
    files: ['src/a.ts', 'lib/b.py'],
  })
  const debug = '[debug-leftover] hits:\n  app/x.js:12: console.log(a)\n  ... and 3 more'
  expect(newNudge('debug-leftover-reminder', debug, T).files).toEqual(['app/x.js'])
  expect(newNudge('review-reminder', '[review-reminder] run a review', T).files).toBeUndefined()
})

test('review-reminder is acted on by a review skill or a review agent after the fire, not before', async () => {
  const before = facts({ skills: [{ skill: 'code-review', at: T - 1 }] })
  expect(resolveNudge(nudge('review-reminder'), atStop(before)).outcome).toBe('ignored')

  const skill = facts({ skills: [{ skill: 'superpowers:requesting-code-review', at: T + 5 }] })
  expect(resolveNudge(nudge('review-reminder'), atStop(skill))).toEqual({
    outcome: 'acted',
    evidence: 'skill superpowers:requesting-code-review',
  })

  const agent = facts({ agents: [{ description: 'Review the nudge tracking diff', subagentType: 'general-purpose', at: T + 5 }] })
  expect(resolveNudge(nudge('review-reminder'), atStop(agent)).outcome).toBe('acted')

  const doer = facts({ agents: [{ description: 'Add product review form', subagentType: 'general-purpose', at: T + 5 }] })
  expect(resolveNudge(nudge('review-reminder'), atStop(doer)).outcome).toBe('ignored')
})

test('compress-comments-reminder is acted on by the compress-comments skill', async () => {
  const f = facts({ skills: [{ skill: 'dev-hooks:compress-comments', at: T + 1 }] })
  expect(resolveNudge(nudge('compress-comments-reminder'), atStop(f)).outcome).toBe('acted')
  expect(resolveNudge(nudge('compress-comments-reminder'), atStop(facts())).outcome).toBe('ignored')
})

test('memory-reminder: a memory write acts, the escape-hatch phrase declines, silence ignores', async () => {
  const wrote = facts({ lastEdit: { '/home/u/.claude/projects/-x/memory/fact.md': T + 1, '/repo/a.ts': T + 2 } })
  expect(resolveNudge(nudge('memory-reminder'), atStop(wrote))).toEqual({ outcome: 'acted', evidence: 'wrote memory fact.md' })

  const other = facts({ lastEdit: { '/repo/memory/notes.md': T + 1 } })
  expect(resolveNudge(nudge('memory-reminder'), atStop(other)).outcome).toBe('ignored')

  const said = atStop(facts(), { lastMessage: 'Nothing worth saving — all of it is in the commit.' })
  expect(resolveNudge(nudge('memory-reminder'), said).outcome).toBe('declined')
})

test('missing-test-reminder is acted on by a test for a listed file', async () => {
  const n = nudge('missing-test-reminder', '[missing-test] …', ['src/parser.ts'])
  const test_ = facts({ lastEdit: { '/repo/tests/parser.test.ts': T + 1 } })
  expect(resolveNudge(n, atStop(test_)).outcome).toBe('acted')
  const unrelated = facts({ lastEdit: { '/repo/tests/other.test.ts': T + 1, '/repo/src/parser.ts': T + 1 } })
  expect(resolveNudge(n, atStop(unrelated)).outcome).toBe('ignored')
})

test('debug-leftover-reminder is acted on by an edit to a listed file', async () => {
  const n = nudge('debug-leftover-reminder', '[debug-leftover] …', ['app/x.js'])
  expect(resolveNudge(n, atStop(facts({ lastEdit: { '/repo/app/x.js': T + 1 } }))).outcome).toBe('acted')
  expect(resolveNudge(n, atStop(facts({ lastEdit: { '/repo/app/x.js': T - 1 } }))).outcome).toBe('ignored')
})

test('verify-work: a failure that clears is acted on, one that refires is ignored, an advisory is unknown', async () => {
  const failed = nudge('verify-work', 'Verification failed. Fix these before finishing:')
  expect(resolveNudge(failed, atStop(facts())).outcome).toBe('acted')
  expect(resolveNudge(failed, atStop(facts(), { refired: ['verify-work'] })).outcome).toBe('ignored')
  expect(resolveNudge(nudge('verify-work', 'No test suite or linter was auto-detected'), atStop(facts())).outcome).toBe(
    'unknown',
  )
})

test('a hook with no detectable remedy is unknown, never guessed', async () => {
  for (const hook of ['change-summary-reminder', 'big-change-reminder', 'save-script-reminder']) {
    expect(resolveNudge(nudge(hook), atStop(facts())).outcome).toBe('unknown')
  }
})

test('without a later Stop, missing evidence is unknown rather than ignored', async () => {
  const ended = { facts: facts(), refired: [], atStop: false }
  expect(resolveNudge(nudge('review-reminder'), ended).outcome).toBe('unknown')
  const acted = { ...ended, facts: facts({ skills: [{ skill: 'code-review', at: T + 1 }] }) }
  expect(resolveNudge(nudge('review-reminder'), acted).outcome).toBe('acted')
})

test('resolvePending resolves only earlier, still-pending nudges', async () => {
  const done: Nudge = { ...nudge('memory-reminder'), outcome: 'declined', evidence: 'x', resolvedAt: T + 1 }
  const f = facts({ nudges: [nudge('review-reminder'), done, { ...nudge('review-reminder'), at: T + 10 }] })
  const { facts: next, resolved } = resolvePending(f, atStop(f), T + 10)

  expect(resolved.map(n => [n.hook, n.outcome, n.resolvedAt])).toEqual([['review-reminder', 'ignored', T + 10]])
  expect(next.nudges?.[1]).toEqual(done)
  expect(next.nudges?.[2]?.outcome).toBeUndefined()
  expect(resolvePending(facts(), atStop(facts()), T).resolved).toEqual([])
})

const rec = (hook: string, outcome: NudgeRecord['outcome'], at = T, session = 's1'): NudgeRecord => ({
  hook,
  session,
  at,
  resolvedAt: at + 1,
  outcome,
  evidence: '',
})

test('mergeNudgeLog dedupes by session, hook and time, and drops records past 90 days', async () => {
  const old = rec('review-reminder', 'ignored', T - 91 * DAY)
  const a = rec('review-reminder', 'acted')
  const merged = mergeNudgeLog([old, a], [a, rec('verify-work', 'acted', T + 1)], T)
  expect(merged.map(r => r.hook)).toEqual(['review-reminder', 'verify-work'])
})

test('summarizeNudges counts outcomes per hook in the window; actedRate skips unknowns', async () => {
  const log = [
    rec('review-reminder', 'acted'),
    rec('review-reminder', 'ignored', T + 1),
    rec('review-reminder', 'unknown', T + 2),
    rec('memory-reminder', 'declined', T + 3),
    rec('review-reminder', 'acted', T - 8 * DAY),
  ]
  const rows = summarizeNudges(log, T - 7 * DAY)
  expect(rows).toEqual([
    { hook: 'review-reminder', fired: 3, acted: 1, ignored: 1, declined: 0, unknown: 1 },
    { hook: 'memory-reminder', fired: 1, acted: 0, ignored: 0, declined: 1, unknown: 0 },
  ])
  expect(actedRate(rows[0]!)).toBe(0.5)
  expect(actedRate({ fired: 1, acted: 0, ignored: 0, declined: 0, unknown: 1 })).toBeNull()
})

test('formatNudgeStats prints one row per hook with its rate', async () => {
  const text = formatNudgeStats([rec('review-reminder', 'acted'), rec('review-reminder', 'ignored', T + 1)], T + 2)
  expect(text.split('\n')).toContain('review-reminder        2        1        1        0        0   50%')
  expect(formatNudgeStats([], T)).toBe('Stop nudges · none resolved in the last 7 days')
})
