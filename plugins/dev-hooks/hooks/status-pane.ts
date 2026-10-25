// The session-status pane's pure half: it reads end reports, briefs and git output, and
// derives what the pane shows. register.tsx records the session and draws the result.
import type { BackgroundItem, Brief, EndReport, StatusPaneState, TurnRecord } from '../types'

export type { BackgroundItem, Brief, EndReport, RepoCommits, StatusPaneState, TurnEnd, TurnRecord } from '../types'


// hook_helpers._END_REPORT_LINES' patterns, pinned by test_status_pane_parity.py.
export const END_REPORT_LABELS = {
  changed: String.raw`(?:what\s+(?:i\s+)?)?changed`,
  yourMove: String.raw`your\s+move`,
}

const REPORT_LABELS = {
  status: 'status',
  doneWhen: String.raw`done\s+when`,
  changed: END_REPORT_LABELS.changed,
  assumed: 'assumed',
  notChecked: String.raw`not\s+checked`,
  yourMove: END_REPORT_LABELS.yourMove,
}

const BRIEF_LABELS = {
  doing: 'doing',
  notDoing: String.raw`not\s+doing`,
  depth: 'depth',
  doneWhen: String.raw`done\s+when`,
  needFromYou: String.raw`need\s+from\s+you`,
  assuming: 'assuming',
}

const TAIL = String.raw`(?:\s+this\s+(?:turn|session))?`
const BULLET = /^\s*(?:[-*+]|\d+[.)])\s+(.*)$/
const NOTHING = /^(?:nothing(?: yet)?|none)\.?$/i

const unmark = (text: string) => text.replace(/^[*_\s]+/, '').trim()

type Labels = Record<string, string>
type Sections<L extends Labels> = { [K in keyof L]?: string[] }

// A label line as hook_helpers.end_report_missing reads one: "**Changed:**", "Your move:",
// "What I changed this session:", or a heading holding only the label.
const parseSections = <L extends Labels>(text: string, labels: L): Sections<L> => {
  const matchers = Object.entries(labels).map(([key, word]) => ({
    key: key as keyof L,
    inline: new RegExp(String.raw`^[\s>*_|-]*(?:${word})${TAIL}[*_\s]*:(.*)$`, 'i'),
    heading: new RegExp(String.raw`^\s*#+\s*(?:${word})${TAIL}\s*$`, 'i'),
  }))
  const found: Sections<L> = {}
  let current: keyof L | null = null
  let gap = false
  for (const line of text.split('\n')) {
    const label = matchers.flatMap(m => {
      const inline = m.inline.exec(line)
      if (inline) return [{ key: m.key, rest: unmark(inline[1] ?? '') }]
      return m.heading.test(line) ? [{ key: m.key, rest: '' }] : []
    })[0]
    if (label) {
      current = label.key
      found[current] = label.rest ? [label.rest] : []
      gap = false
      continue
    }
    if (current === null) continue
    const items = found[current] ?? []
    if (!line.trim()) {
      gap = true
      continue
    }
    const bullet = BULLET.exec(line)
    if (bullet) items.push(unmark(bullet[1] ?? ''))
    else if (gap) current = null
    else if (items.length > 0) items[items.length - 1] = `${items[items.length - 1]} ${line.trim()}`
    else items.push(unmark(line))
    gap = false
  }
  return found
}

const list = (items: string[] | undefined) => (items ?? []).filter(item => item && !NOTHING.test(item))

export const parseEndReport = (text: string): EndReport | null => {
  const s = parseSections(text, REPORT_LABELS)
  if (!s.status && !s.changed && !s.yourMove) return null
  const status = s.status?.join(' ')
  return {
    ...(status ? { status } : {}),
    doneWhen: list(s.doneWhen),
    changed: list(s.changed),
    notChecked: list(s.notChecked),
    yourMove: list(s.yourMove),
  }
}

export const findBrief = (texts: string[]): Brief | null => {
  for (const text of [...texts].reverse()) {
    const s = parseSections(text, BRIEF_LABELS)
    if (s.doing && s.doneWhen) return { doing: s.doing.join(' '), doneWhen: list(s.doneWhen) }
  }
  return null
}

const COMMIT = /^\[([^\s\]]+)(?: \([^)]*\))? ([0-9a-f]{7,40})\]/gm

export const parseCommits = (text: string): { branch: string; sha: string }[] =>
  [...text.matchAll(COMMIT)].map(m => ({ branch: m[1] ?? '', sha: m[2] ?? '' }))

export const endsOnQuestion = (text: string): boolean => {
  const last = text.trim().split('\n').at(-1) ?? ''
  return last.replace(/[*_`>\s]+$/, '').endsWith('?')
}

// ── The view ─────────────────────────────────────────────────────────────────────────

export const EMPTY_PANE_STATE = (now: number): StatusPaneState => ({
  turns: [],
  turnsTotal: 0,
  brief: null,
  repos: [],
  background: [],
  startedAt: now,
})

export type PaneStateName =
  | 'stopped'
  | 'waiting'
  | 'no-report'
  | 'working'
  | 'running'
  | 'done'
  | 'replied'
  | 'interrupted'
  | 'no-turns'
export type PaneTone = 'red' | 'yellow' | 'blue' | 'green' | 'dim'
export type PaneView = {
  state: PaneStateName
  tone: PaneTone
  label: string
  since: number
  yourMove: string[]
  doing?: string
  doneWhen: { text: string; met: boolean | null }[]
  doneWhenNote?: string
  running: string[]
  changed: string[]
  repoLines: string[]
  notChecked: string[]
  lastSaid?: string
  canSummarize: boolean
  summarizing: boolean
  summaryError?: string
  turnCount: number
}

// Highest first: the pane shows the worst state any turn since the last typed prompt is in.
const ORDER: PaneStateName[] = [
  'stopped',
  'waiting',
  'no-report',
  'working',
  'running',
  'done',
  'replied',
  'interrupted',
  'no-turns',
]
const TONE: Record<PaneStateName, PaneTone> = {
  stopped: 'red',
  waiting: 'yellow',
  'no-report': 'yellow',
  working: 'blue',
  running: 'blue',
  done: 'green',
  replied: 'dim',
  interrupted: 'dim',
  'no-turns': 'dim',
}
const LABEL: Record<PaneStateName, string> = {
  stopped: 'Stopped',
  waiting: 'Waiting on you',
  'no-report': 'Turn ended, no end report',
  working: 'Working',
  running: 'Running',
  done: 'Done',
  replied: 'Replied',
  interrupted: 'Interrupted',
  'no-turns': 'No turns yet',
}
const CAPS = { yourMove: 5, changed: 4, running: 4, notChecked: 2 }
const QUESTION_MOVE = 'answer the question in the chat'
const NOT_TYPED = /^\s*(?:<task-notification>|<agent-message|<system-reminder>|\[dev-hooks CI watch\])/

export const isTypedPrompt = (text: string): boolean => text.trim() !== '' && !NOT_TYPED.test(text)

// end-report-reminder's rule for a turn that owes a report.
export const isWorkTurn = (t: TurnRecord): boolean => t.edits > 0 || t.calls >= 10

export const capped = (items: string[], cap: number): string[] =>
  items.length <= cap ? items : [...items.slice(0, cap - 1), `+${items.length - cap + 1} more`]

const age = (ms: number): string => {
  const minutes = Math.floor(ms / 60_000)
  if (minutes < 1) return 'just now'
  if (minutes < 60) return `${minutes} min`
  return `${Math.floor(minutes / 60)} h ${minutes % 60} min`
}

export const clockTime = (at: number, tz?: string): string =>
  new Intl.DateTimeFormat('en-GB', { hour: '2-digit', minute: '2-digit', hour12: false, timeZone: tz }).format(at)

export const sinceLabel = (at: number, now: number, tz?: string): string => `since ${clockTime(at, tz)} (${age(now - at)})`

const reportOf = (t: TurnRecord) => t.summary ?? t.report ?? null

const classify = (t: TurnRecord): PaneStateName => {
  if (t.endedAt === undefined) return 'working'
  if (t.end === 'error' || t.end === 'refusal') return 'stopped'
  if (t.end === 'aborted') return 'interrupted'
  const r = reportOf(t)
  if (r) return r.yourMove.length > 0 || /^blocked/i.test(r.status ?? '') ? 'waiting' : 'done'
  if (isWorkTurn(t)) return 'no-report'
  return endsOnQuestion(t.answer ?? '') ? 'waiting' : 'replied'
}

const NOT_MET = /not met|\bno\b|✗/i
const MET = /\bmet\b|\bdone\b|\byes\b|✓/i
const verdict = (item: string): boolean | null => (NOT_MET.test(item) ? false : MET.test(item) ? true : null)

export const paneView = (s: StatusPaneState, extraRunning: BackgroundItem[], now: number): PaneView => {
  const lastTyped = s.turns.map(t => t.typed).lastIndexOf(true)
  const window = s.turns.slice(Math.max(lastTyped, 0))
  const background = [...s.background, ...extraRunning]
  const classes = window.map(classify)
  if (background.length > 0) classes.push('running')
  const state = ORDER.find(name => classes.includes(name)) ?? 'no-turns'
  const reports = window.map(reportOf).filter((r): r is EndReport => r !== null)
  const latest = reports.at(-1)
  const lastTurn = window.at(-1)
  const open = window.find(t => t.endedAt === undefined)

  const moves = window.flatMap(t => {
    const r = reportOf(t)
    if (r) return r.yourMove
    return classify(t) === 'waiting' ? [QUESTION_MOVE] : []
  })
  const criteria = s.brief?.doneWhen ?? []
  const verdicts = !open && latest && latest.doneWhen.length === criteria.length ? latest.doneWhen.map(verdict) : []
  const ticked = verdicts.length > 0 && verdicts.every(v => v !== null)
  const noReport = window.findLast(t => classify(t) === 'no-report')

  return {
    state,
    tone: TONE[state],
    label:
      state !== 'stopped'
        ? LABEL[state]
        : window.findLast(t => classify(t) === 'stopped')?.end === 'refusal'
          ? 'Stopped: refused'
          : 'Stopped: API error',
    since: open?.startedAt ?? lastTurn?.endedAt ?? s.startedAt,
    yourMove: capped([...new Set(moves)], CAPS.yourMove),
    ...(s.brief ? { doing: s.brief.doing } : {}),
    doneWhen: criteria.map((text, i) => ({ text, met: ticked ? (verdicts[i] ?? null) : null })),
    ...(!open && !ticked && latest && latest.doneWhen.length > 0 && criteria.length > 0
      ? { doneWhenNote: latest.doneWhen.join('; ') }
      : {}),
    running: capped(
      background.map(b => `${b.label} (${age(now - b.since)})`),
      CAPS.running,
    ),
    changed: capped(latest?.changed ?? [], CAPS.changed),
    repoLines: s.repos.map(
      r =>
        `${r.repo}: ${r.commits} commit${r.commits === 1 ? '' : 's'}, ${
          (r.lastPushAt ?? 0) >= r.lastCommitAt ? 'pushed' : 'not pushed'
        }`,
    ),
    notChecked: capped(latest?.notChecked ?? [], CAPS.notChecked),
    ...(lastTurn?.answer && !reportOf(lastTurn) ? { lastSaid: lastTurn.answer.trim().split('\n')[0] } : {}),
    canSummarize: noReport !== undefined && !noReport.summarizing,
    summarizing: noReport?.summarizing === true,
    ...(noReport?.summaryError ? { summaryError: noReport.summaryError } : {}),
    turnCount: s.turnsTotal,
  }
}
