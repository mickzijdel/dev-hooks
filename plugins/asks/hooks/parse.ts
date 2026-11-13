export type ParsedAsk = { move: string; changed: string; context: string }

const DETAILS = /^\s*Details \(skippable\)\s*$/im
/** The label opens a line: a reply that only mentions it inside a sentence states no move. */
const MOVE = /^[ \t]*\*\*Your move:\*\*/im
/** The line that links the session's brief file: a pointer, not context for the decision. */
const BRIEF_LINE = /^Brief:.*$/im
const CHANGED = /\*\*Changed:\*\*/i
/** A bold label that opens a line, as `**Risk:**`: where the "Changed" text ends. */
const NEXT_LABEL = /^\*\*[^*\n]+:\*\*/m
/** A move whose first line says nothing is needed. "None of the tests pass. Decide…" is an ask, so "none" must stand alone. */
const NOTHING = /^(nothing\b|no action\b|none\s*[.!]?\s*$)/i

/**
 * Reads the "Your move" block that opens a reply. Null when the reply has none, or when the move is "nothing".
 * Only the text above the "Details (skippable)" line is read.
 */
export function parseAsk(answer: string): ParsedAsk | null {
  const head = answer.split(DETAILS)[0] ?? ''
  const moveAt = head.search(MOVE)
  if (moveAt < 0) return null
  const afterMove = head.slice(moveAt).replace(MOVE, '')
  const changedAt = afterMove.search(CHANGED)
  const move = (changedAt < 0 ? afterMove : afterMove.slice(0, changedAt)).trim()
  if (!move || NOTHING.test(move.split('\n')[0]!.trim())) return null
  if (changedAt < 0) return { move, changed: '', context: '' }
  const afterChanged = afterMove.slice(changedAt).replace(CHANGED, '')
  const labelAt = afterChanged.search(NEXT_LABEL)
  const changed = (labelAt < 0 ? afterChanged : afterChanged.slice(0, labelAt)).trim()
  const context = labelAt < 0 ? '' : afterChanged.slice(labelAt).replace(BRIEF_LINE, '').trim()

  return { move, changed, context }
}

const OPTION = /^\s*(\d{1,2})[.)]\s+(.*)$/
/** The numbers that stand right after "I recommend": "I recommend 1 and 2", "Recommended: option 3". */
const RECOMMENDS =
  /(?:^|\s)(?:I recommend|Recommended:|Recommendation:)\s*(?:(?:options?|routes?|choices?|steps?)\s*)?(\d{1,2}(?:\s*(?:,|and|&|\+)\s*\d{1,2})*)\b/i

export type MoveChoice = {
  /** What stands around the numbered list: the decision in a sentence or two. */
  intro: string
  /**
   * The numbered items, each with its continuation lines joined on. `number` is the item's place in the list, so
   * every option has its own key even when the list repeats or restarts its numbers.
   */
  options: { number: number; text: string }[]
  /** The options the intro recommends, as "I recommend 1 and 2 together". */
  recommended: number[]
}

/** Splits a move into its intro and its numbered options. A move with no numbered list is all intro. */
export function moveChoice(move: string): MoveChoice {
  const intro: string[] = []
  const options: MoveChoice['options'] = []
  const written: number[] = []
  // A blank line after the list closes it: what follows is prose about the choice, not more of the last option.
  let isClosed = false
  for (const line of move.split('\n')) {
    const item = OPTION.exec(line)
    if (item) {
      written.push(Number(item[1]))
      options.push({ number: options.length + 1, text: item[2]!.trim() })
      isClosed = false
    } else if (options.length === 0 || isClosed) intro.push(line)
    else if (line.trim()) options.at(-1)!.text += ` ${line.trim()}`
    else isClosed = true
  }
  const introText = intro
    .join('\n')
    .replace(/\n\s*\n+/g, '\n')
    .trim()
  const named = (RECOMMENDS.exec(introText)?.[1]?.match(/\d{1,2}/g) ?? []).map(Number)
  // A recommendation names an option by the number the session wrote; the first item with that number is meant.
  const recommended = named.map(n => written.indexOf(n) + 1).filter(place => place > 0)

  return { intro: introText, options, recommended }
}

/**
 * The session's title as the app last set it, from the `"customTitle":"…"` matches a grep of the transcript printed,
 * oldest first. Empty when the transcript holds none.
 */
export function titleFrom(matches: string): string {
  const last = matches.trim().split('\n').pop() ?? ''
  try {
    const title = (JSON.parse(`{${last}}`) as { customTitle?: unknown }).customTitle
    return typeof title === 'string' ? title.trim() : ''
  } catch {
    return ''
  }
}

/** What the small model is asked, to head an ask with its subject. */
export function topicPrompt(session: string, parts: ParsedAsk): string {
  return [
    'An AI coding assistant ended its turn with a request to its user. Write the subject of that request as one',
    'plain phrase of at most 9 words, so the user sees at a glance what the decision is about. Name the concrete',
    'thing, not the act of deciding. No quotes, no full stop, no preamble.',
    '',
    `Session: ${session}`,
    `Request: ${parts.move}`,
    parts.changed && `What changed: ${parts.changed}`,
    parts.context && `Context: ${parts.context}`,
  ]
    .filter(line => line !== '')
    .join('\n')
}

const TAGGED_BLOCK = /<([a-z][a-z-]*)\b[^>]*>[\s\S]*?<\/\1>/gi

/** A session's name from its first prompt: reminders and command tags left out, one line, at most `length` characters. */
export function sessionName(prompt: string, length: number): string {
  const text = prompt.replace(TAGGED_BLOCK, ' ').replace(/\s+/g, ' ').trim()

  return text.length > length ? `${text.slice(0, length)}…` : text
}

/** Whether the reply states a move at all above the details line. A reply that states none leaves an earlier ask open. */
export function statesMove(answer: string): boolean {
  return MOVE.test(answer.split(DETAILS)[0] ?? '')
}

/** The questions of an AskUserQuestion call as markdown, each with its options. */
export function questionText(input: unknown): string {
  const questions = (input as { questions?: unknown } | null)?.questions
  if (!Array.isArray(questions)) return ''

  return questions
    .map(q => {
      const one = q as { question?: unknown; options?: unknown }
      const options = Array.isArray(one.options)
        ? one.options.map(o => `- ${String((o as { label?: unknown }).label ?? '')}`).join('\n')
        : ''

      return `${String(one.question ?? '')}\n${options}`.trim()
    })
    .join('\n\n')
}
