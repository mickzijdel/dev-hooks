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

// Emphasis markers around words go; an underscore inside a name (snake_case, a_b.py) stays.
const unmark = (text: string) =>
  text
    .replace(/\*\*|__/g, '')
    .replace(/(^|\s)[*_](?=\S)/g, '$1')
    .replace(/(\S)[*_](?=\s|[.,;:!?)]|$)/g, '$1')
    .trim()

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
  let fenced = false
  for (const line of text.split('\n')) {
    // A fenced block holds a template or code, and a quote holds someone else's words.
    if (/^\s*```/.test(line)) fenced = !fenced
    if (fenced || /^\s*```/.test(line)) continue
    const label = /^\s*>/.test(line) ? undefined : matchers.flatMap(m => {
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
    else if (gap && items.length > 0) current = null
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
    ...(s.yourMove ? { yourMove: list(s.yourMove) } : {}),
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

// The person's own message: Enter at the prompt, the Remote Control bridge, or an SDK host's
// turn (how VS Code and claude -p send what was typed). The text is only the fallback, for a
// turn whose prompt.submit never arrived.
const TYPED_ORIGINS = new Set(['composer', 'bridge', 'sdk'])

export const typedFrom = (origin: string | undefined, text: string): boolean =>
  origin !== undefined ? TYPED_ORIGINS.has(origin) : isTypedPrompt(text)

const LAST_SAID_CAP = 300

export const answerFacts = (answer: string): { lastSaid?: string; asksQuestion: boolean } => {
  const first = answer.trim().split('\n')[0]?.trim() ?? ''
  return { ...(first ? { lastSaid: first.slice(0, LAST_SAID_CAP) } : {}), asksQuestion: endsOnQuestion(answer) }
}

// end-report-reminder's rule for a turn that owes a report.
export const isWorkTurn = (t: TurnRecord): boolean => t.edits > 0 || t.calls >= 10

// The last `cap` turns, and every turn from the last typed one on (so an ask survives any
// number of notification turns), up to `hardCap`.
export const keepTurns = (turns: TurnRecord[], cap = 20, hardCap = 200): TurnRecord[] => {
  const lastTyped = turns.map(t => t.typed).lastIndexOf(true)
  const from = Math.min(Math.max(turns.length - cap, 0), lastTyped < 0 ? turns.length : lastTyped)
  return turns.slice(Math.max(from, turns.length - hardCap))
}

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
const isBlocked = (r: EndReport | null) => /^blocked/i.test(r?.status ?? '')
// A report whose Your move line was there, even as "nothing".
const hasMove = (r: EndReport | null): r is EndReport & { yourMove: string[] } => r?.yourMove !== undefined

// null: a later turn's report covers this one, as when a Stop hook's continuation writes it.
const classify = (t: TurnRecord, later: TurnRecord[]): PaneStateName | null => {
  if (t.endedAt === undefined) return t.asking ? 'waiting' : 'working'
  if (t.end === 'error' || t.end === 'refusal') return 'stopped'
  if (t.end === 'aborted') return 'interrupted'
  const r = reportOf(t)
  if (isBlocked(r)) return 'waiting'
  if (hasMove(r)) return r.yourMove.length > 0 || t.asksQuestion ? 'waiting' : 'done'
  if (later.some(l => hasMove(reportOf(l)))) return null
  if (t.asksQuestion) return 'waiting'
  return isWorkTurn(t) ? 'no-report' : 'replied'
}

const movesOf = (t: TurnRecord, cls: PaneStateName | null): string[] => {
  if (cls === null) return []
  const r = reportOf(t)
  const own = hasMove(r) ? r.yourMove : []
  if (own.length > 0) return own
  if (t.asking || (t.asksQuestion && cls === 'waiting')) return [QUESTION_MOVE]
  return isBlocked(r) && r?.status ? [r.status] : []
}

// The verdict word leads the item ("met: …") or follows its criterion ("tests green: met");
// anything else ("partly met") ticks nothing.
const SAYS_NOT_MET = /^(?:(?:not met|unmet|no)\b|✗)/i
const SAYS_MET = /^(?:(?:met|done|yes)\b|✓)/i
const leadingVerdict = (text: string): boolean | null =>
  SAYS_NOT_MET.test(text) ? false : SAYS_MET.test(text) ? true : null
const verdict = (item: string): boolean | null => {
  const whole = leadingVerdict(item.trim())
  const colon = item.indexOf(':')
  return whole ?? (colon < 0 ? null : leadingVerdict(item.slice(colon + 1).trim()))
}

// The turns since the person last typed a prompt: what the pane reads.
const windowOf = (s: StatusPaneState) => s.turns.slice(Math.max(s.turns.map(t => t.typed).lastIndexOf(true), 0))

// The turn the Summarize button answers for: the latest that did work and left no report.
export const noReportTurn = (s: StatusPaneState): TurnRecord | undefined => {
  const window = windowOf(s)
  return window.findLast((t, i) => classify(t, window.slice(i + 1)) === 'no-report')
}

// When the shown state began: an ask since the turn that made it, not the latest turn.
const sinceOf = (
  state: PaneStateName,
  window: TurnRecord[],
  perTurn: (PaneStateName | null)[],
  background: BackgroundItem[],
  startedAt: number,
): number => {
  if (state === 'running' && background.length > 0) return Math.min(...background.map(b => b.since))
  const first = window.find((_t, i) => perTurn[i] === state)
  return first ? (first.endedAt ?? first.startedAt) : (window.at(-1)?.endedAt ?? startedAt)
}

// summarizing: the turn a Summarize press is answering now (module memory, so a reload
// mid-fork never leaves the button stuck).
export const paneView = (
  s: StatusPaneState,
  extraRunning: BackgroundItem[],
  now: number,
  summarizing?: string,
): PaneView => {
  const window = windowOf(s)
  const background = [...s.background, ...extraRunning]
  const perTurn = window.map((t, i) => classify(t, window.slice(i + 1)))
  const classes = perTurn.filter((c): c is PaneStateName => c !== null)
  if (background.length > 0) classes.push('running')
  const state = ORDER.find(name => classes.includes(name)) ?? 'no-turns'
  const reports = window.map(reportOf).filter((r): r is EndReport => r !== null)
  const latest = reports.at(-1)
  const lastTurn = window.at(-1)
  const open = window.find(t => t.endedAt === undefined)

  const moves = window.flatMap((t, i) => movesOf(t, perTurn[i] ?? null))
  const criteria = s.brief?.doneWhen ?? []
  const verdicts = !open && latest && latest.doneWhen.length === criteria.length ? latest.doneWhen.map(verdict) : []
  const ticked = verdicts.length > 0 && verdicts.every(v => v !== null)
  const noReport = noReportTurn(s)

  return {
    state,
    tone: TONE[state],
    label:
      state !== 'stopped'
        ? LABEL[state]
        : window.findLast((_t, i) => perTurn[i] === 'stopped')?.end === 'refusal'
          ? 'Stopped: refused'
          : 'Stopped: API error',
    since: sinceOf(state, window, perTurn, background, s.startedAt),
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
    ...(lastTurn?.lastSaid && !hasMove(reportOf(lastTurn)) ? { lastSaid: lastTurn.lastSaid } : {}),
    canSummarize: noReport !== undefined && noReport.id !== summarizing,
    summarizing: noReport !== undefined && noReport.id === summarizing,
    ...(noReport?.summaryError ? { summaryError: noReport.summaryError } : {}),
    turnCount: s.turnsTotal,
  }
}
