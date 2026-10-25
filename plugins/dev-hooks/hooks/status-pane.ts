// The session-status pane's pure half: it reads end reports, briefs and git output, and
// derives what the pane shows. register.tsx records the session and draws the result.

export type EndReport = { status?: string; doneWhen: string[]; changed: string[]; notChecked: string[]; yourMove: string[] }
export type Brief = { doing: string; doneWhen: string[] }

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
