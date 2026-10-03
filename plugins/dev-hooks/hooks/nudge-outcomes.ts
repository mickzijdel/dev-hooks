// Stop-nudge outcomes: did Claude act on a Stop hook's reason? Pure functions only —
// register.tsx owns every `$` call and passes the facts in.
//
// A nudge fires when the Stop orchestration returns a hook's reason, and is resolved at
// the next Stop (the forced continuation the block caused, normally) or at session end,
// from what the session facts show happened after it fired.
import type { Facts, Nudge, NudgeCounts, NudgeOutcome, NudgeRecord } from '../types'

// The hook a Stop command runs, by its script name: `bash ".../review-reminder.sh"` →
// `review-reminder`. Names hooks without relying on each reason's tag.
export const hookName = (command: string): string =>
  command.match(/([\w.-]+)\.sh\b/g)?.at(-1)?.replace(/\.sh$/, '') ?? command

// The files a reason lists, one per "  path" or "  path:line: text" line.
const reasonFiles = (reason: string): string[] =>
  reason
    .split('\n')
    .filter(l => /^ {2}\S/.test(l) && !l.startsWith('  ... and'))
    .map(l => l.trim().replace(/:\d+:.*$/, ''))

const LISTS_FILES = new Set(['debug-leftover-reminder', 'missing-test-reminder'])

export const newNudge = (hook: string, reason: string, at: number): Nudge => {
  const files = LISTS_FILES.has(hook) ? reasonFiles(reason) : []
  return {
    hook,
    at,
    summary: (reason.split('\n')[0] ?? '').slice(0, 120),
    ...(files.length > 0 ? { files } : {}),
  }
}

// Mirrors review-reminder.sh's reminder_transcript_invoked needles (tests/test_nudge_parity.py).
export const REVIEW_NEEDLES = ['code-review', 'code_review', 'requesting-code-review', 'code-reviewer']
// Mirrors hook_helpers.MEMORY_DIR_RE.
export const MEMORY_DIR_RE = /\/\.claude\/(?:projects\/[^/]+\/)?memory\//

// Mirrors hook_helpers._AGENT_DOER_RE and _agent_job_re: "Review task 8" is a review,
// "Add product review form" is not.
const AGENT_DOER_RE = /^\s*(?:fix|fixes|implement|build|add|create|write|update|refactor|address|apply|predict|simulate)\b/i
const agentJobRe = (w: string) =>
  new RegExp(
    `^\\s*(?:re-?)?${w}(?:ing)?\\b` +
      `|\\bre-?${w}\\b` +
      `|^\\s*(?:code|final|whole-branch|final whole-branch)[- ]${w}\\b(?!\\s+fix)` +
      `|\\bwhole-branch ${w}\\b` +
      `|\\b${w}(?:ing)?(?=\\s*(?:$|[:,;(—–-]|\\s+(?:of|for|round|pass|loop)\\b))`,
    'i',
  )

// A skill or subagent run after `at` that names one of `names`, or a subagent described
// as doing `job`; its description for the evidence, or undefined.
const invokedSince = (f: Facts, at: number, names: string[], job?: string): string | undefined => {
  const named = (s: string) => names.some(n => s.includes(n))
  const skill = f.skills.find(s => s.at > at && named(s.skill))
  if (skill) return `skill ${skill.skill}`
  const jobRe = job ? agentJobRe(job) : undefined
  const agent = f.agents.find(
    a =>
      a.at > at &&
      (named(a.subagentType) || (jobRe !== undefined && !AGENT_DOER_RE.test(a.description) && jobRe.test(a.description))),
  )
  return agent ? `agent ${agent.subagentType}: ${agent.description}`.slice(0, 100) : undefined
}

const editedSince = (f: Facts, at: number, match: (file: string) => boolean): string | undefined =>
  Object.entries(f.lastEdit ?? {}).find(([file, t]) => t > at && match(file))?.[0]

const base = (path: string) => path.slice(path.lastIndexOf('/') + 1)
const stem = (path: string) => base(path).replace(/\.[^.]*$/, '')
const isTestPath = (path: string) =>
  /(^|\/)(tests?|spec|__tests__)\//.test(path) || /(^test_|_test\.|\.test\.|_spec\.|\.spec\.)/.test(base(path))

export type NudgeEvidence = {
  facts: Facts
  // Hooks whose reason the resolving Stop returned again.
  refired: string[]
  // The resolving Stop's last assistant message; undefined when resolved at session end.
  lastMessage?: string
  // false when resolved at session end or a later sweep: no Stop ran after the nudge.
  atStop: boolean
}

type Resolution = { outcome: NudgeOutcome; evidence: string }

// What counts as acting on each hook's reason. A hook without a remedy the facts can show
// is "unknown", never guessed. The facts see Edit/Write only, so a remedy done through
// Bash (a test file made by a generator, a memory file written with cat) reads as ignored.
export const resolveNudge = (n: Nudge, ev: NudgeEvidence): Resolution => {
  const acted = (evidence: string): Resolution => ({ outcome: 'acted', evidence })
  const missed = (what: string): Resolution =>
    ev.atStop
      ? { outcome: 'ignored', evidence: `no ${what} before the next Stop` }
      : { outcome: 'unknown', evidence: `session ended before the next Stop; no ${what}` }

  switch (n.hook) {
    case 'review-reminder': {
      const hit = invokedSince(ev.facts, n.at, REVIEW_NEEDLES, 'review')
      return hit ? acted(hit) : missed('review skill or review agent')
    }
    case 'compress-comments-reminder': {
      const hit = invokedSince(ev.facts, n.at, ['compress-comments'])
      return hit ? acted(hit) : missed('compress-comments run')
    }
    case 'memory-reminder': {
      const file = editedSince(ev.facts, n.at, f => MEMORY_DIR_RE.test(f))
      if (file) return acted(`wrote memory ${base(file)}`)
      // The reason's own escape hatch: "Say 'nothing worth saving' in one line and stop."
      if (/nothing worth saving/i.test(ev.lastMessage ?? '')) {
        return { outcome: 'declined', evidence: "said 'nothing worth saving'" }
      }
      return missed('memory write')
    }
    case 'missing-test-reminder': {
      const stems = (n.files ?? []).map(stem)
      const file = editedSince(ev.facts, n.at, f => isTestPath(f) && stems.some(s => base(f).includes(s)))
      return file ? acted(`wrote test ${base(file)}`) : missed('test written for a listed file')
    }
    case 'debug-leftover-reminder': {
      const files = n.files ?? []
      const file = editedSince(ev.facts, n.at, f => files.some(l => f === l || f.endsWith(`/${l}`)))
      return file ? acted(`edited ${base(file)}`) : missed('edit to a listed file')
    }
    case 'verify-work': {
      // Only a failure can be re-checked: verify-work runs again at the continuation's
      // Stop and blocks again while the failure stands.
      if (!n.summary.startsWith('Verification failed')) return { outcome: 'unknown', evidence: 'advisory, nothing to re-check' }
      if (!ev.atStop) return { outcome: 'unknown', evidence: 'session ended before verify-work ran again' }
      return ev.refired.includes('verify-work')
        ? { outcome: 'ignored', evidence: 'still failing at the next Stop' }
        : acted('passed at the next Stop')
    }
    default:
      return { outcome: 'unknown', evidence: 'no remedy the session facts can show' }
  }
}

// Resolves every nudge fired before `now` that is still pending.
export const resolvePending = (f: Facts, ev: NudgeEvidence, now: number): { facts: Facts; resolved: Nudge[] } => {
  const resolved: Nudge[] = []
  const nudges = (f.nudges ?? []).map(n => {
    if (n.outcome !== undefined || n.at >= now) return n
    const r = { ...n, ...resolveNudge(n, ev), resolvedAt: now }
    resolved.push(r)
    return r
  })
  return { facts: resolved.length > 0 ? { ...f, nudges } : f, resolved }
}

export const NUDGE_LOG_KEY = 'nudgeOutcomes'
const LOG_DAYS = 90
const LOG_MAX = 3000
const DAY_MS = 86_400_000

export const toRecord = (session: string, n: Nudge): NudgeRecord => ({
  hook: n.hook,
  session,
  at: n.at,
  resolvedAt: n.resolvedAt ?? n.at,
  outcome: n.outcome ?? 'unknown',
  evidence: n.evidence ?? '',
})

// Union by (session, hook, at), so re-adding a record is harmless; keeps the last
// LOG_DAYS days and at most LOG_MAX records, which bounds the store key.
export const mergeNudgeLog = (log: NudgeRecord[] | undefined, add: NudgeRecord[], now: number): NudgeRecord[] => {
  const byId = new Map<string, NudgeRecord>()
  for (const r of [...(log ?? []), ...add]) byId.set(`${r.session}|${r.hook}|${r.at}`, r)
  return [...byId.values()]
    .filter(r => r.at >= now - LOG_DAYS * DAY_MS)
    .sort((a, b) => a.at - b.at)
    .slice(-LOG_MAX)
}

export type NudgeSummary = { hook: string } & NudgeCounts

// Per hook, the outcomes of nudges fired since `since`, most-fired first.
export const summarizeNudges = (log: NudgeRecord[], since: number): NudgeSummary[] => {
  const byHook = new Map<string, NudgeSummary>()
  for (const r of log) {
    if (r.at < since) continue
    const s = byHook.get(r.hook) ?? { hook: r.hook, fired: 0, acted: 0, ignored: 0, declined: 0, unknown: 0 }
    s.fired++
    s[r.outcome]++
    byHook.set(r.hook, s)
  }
  return [...byHook.values()].sort((a, b) => b.fired - a.fired || a.hook.localeCompare(b.hook))
}

// Acted-on rate over the nudges whose outcome is known; null when none is.
export const actedRate = (s: NudgeCounts): number | null => {
  const known = s.acted + s.ignored + s.declined
  return known === 0 ? null : s.acted / known
}

export const formatNudgeStats = (log: NudgeRecord[], now: number, days = 7): string => {
  const rows = summarizeNudges(log, now - days * DAY_MS)
  if (rows.length === 0) return `Stop nudges · none resolved in the last ${days} days`
  const width = Math.max(4, ...rows.map(r => r.hook.length))
  const pct = (s: NudgeCounts) => {
    const r = actedRate(s)
    return r === null ? '   -' : `${Math.round(r * 100)}%`.padStart(4)
  }
  const cell = (n: number | string) => String(n).padStart(8)
  return [
    `Stop nudges · last ${days} days · acted = acted / (acted + ignored + declined)`,
    '',
    `${'hook'.padEnd(width)} ${cell('fired')} ${cell('acted')} ${cell('ignored')} ${cell('declined')} ${cell('unknown')}  rate`,
    ...rows.map(
      r => `${r.hook.padEnd(width)} ${cell(r.fired)} ${cell(r.acted)} ${cell(r.ignored)} ${cell(r.declined)} ${cell(r.unknown)}  ${pct(r)}`,
    ),
    '',
    '/session-facts nudges 30 widens the window; the weekly review reads ~/.claude/automation-review/stop-nudges.json.',
  ].join('\n')
}

// The export the weekly automation review reads.
export const nudgeExport = (log: NudgeRecord[], now: number) => ({
  generatedAt: new Date(now).toISOString(),
  retentionDays: LOG_DAYS,
  last7Days: summarizeNudges(log, now - 7 * DAY_MS),
  last30Days: summarizeNudges(log, now - 30 * DAY_MS),
  records: log,
})
