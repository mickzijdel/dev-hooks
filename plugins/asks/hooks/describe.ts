import type { Ask } from '../types'
import { moveChoice } from './parse'

/** What the person must do for an ask, which picks the memo's shape and its colour. */
export type Kind = 'go-ahead' | 'choose' | 'do' | 'review' | 'reply'

export type Option = { number: number; label: string; consequence: string }

/** One labelled line of the reply, as `**Risk:** shared with the data team`: key `RISK`, value `shared with the data team`. */
export type Fact = { key: string; value: string }

/**
 * An ask as the memo draws it, derived by plain code from what the session wrote. The one exception is
 * `question`, which is the model-written subject line when the session's first sentence is too long for a heading.
 */
export type Described = {
  kind: Kind
  /** The memo's heading: the first sentence of the move, or the subject line when that sentence is long. */
  question: string
  /** What the move says after its first sentence, as markdown; empty when there is no more. */
  body: string
  /** What follows "Claude recommends:"; empty when the session recommended nothing. */
  recommend: string
  options: Option[]
  /** The option numbers the session recommends. */
  recommended: number[]
  /** The command of a task only the person can do. */
  command: string
  /** The link of finished work to review. */
  url: string
  /** What waits on the answer; empty when nothing does. */
  blocks: string
  /** The labelled lines the memo shows under the answers, in display order. */
  facts: Fact[]
}

const LABEL = /^\*\*([^*:\n]{2,24}):\*\*\s*(.*)$/
/** A value that says nothing: "None.", "Nothing this turn.", "N/A". "No way back once sent." says something. */
const NOTHING = /^(nothing|none|n\/a|no)(\s+(to|this|needed|required|yet)\b[^.,;:]{0,20})?[.!]?$/i
/** A question "yes" does not answer: it opens with a question word, or offers alternatives. */
const OPEN_QUESTION = /^(which|what|how|who|whom|whose|where|when|why)\b|\sor\s/i
/** Words that make a numbered list a choice between its items, not a list of steps. */
const CHOOSES = /\b(choose|pick|which|options?|either|routes?)\b/i
const SENTENCE = /^([\s\S]+?[?.!])(?=\s|$)/
const RECOMMENDS = /(?:^|\s)(?:I recommend|Recommended:|Recommendation:)\s*([^.\n]*\.?)/i
const CODE_SPAN = /`([^`\n]+)`/
const URL = /https?:\/\/[^\s)>\]]+/
const PULL = /\/pull\/\d+/
const RUNS = /\b(run|type|paste|execute|sign in|log in)\b/i
const SPLIT = /\s[—–-]\s|:\s|\s->\s|\s→\s/
const LONG_QUESTION = 100
/** Labels that steer the memo and are not shown as fact rows. */
const STEERING = new Set(['YOUR MOVE', 'KIND', 'RECOMMEND', 'BLOCKS', 'PR', 'REVIEW'])
const FACT_ORDER = ['RISK', 'UNDO', 'DOES', 'CHANGED', 'NOT CHECKED']
const KINDS: Record<string, Kind> = {
  'go-ahead': 'go-ahead',
  approve: 'go-ahead',
  decide: 'go-ahead',
  choose: 'choose',
  choice: 'choose',
  do: 'do',
  task: 'do',
  review: 'review',
  reply: 'reply',
}

/**
 * Splits text into its labelled lines and what is left. A label's value runs on over the lines after it, up to a
 * blank line, a numbered item or the next label.
 */
export function labelled(text: string): { facts: Fact[]; rest: string } {
  const facts: Fact[] = []
  const rest: string[] = []
  let open: Fact | null = null
  for (const line of text.split('\n')) {
    const label = LABEL.exec(line.trim())
    if (label) {
      open = { key: label[1]!.trim().toUpperCase(), value: label[2]!.trim() }
      facts.push(open)
    } else if (open && line.trim() && !/^\s*\d{1,2}[.)]\s/.test(line)) {
      open.value = `${open.value} ${line.trim()}`.trim()
    } else {
      open = null
      rest.push(line)
    }
  }

  return { facts, rest: rest.join('\n').trim() }
}

function option(number: number, text: string): Option {
  const cut = SPLIT.exec(text)
  const label = cut ? text.slice(0, cut.index).trim() : text
  // A "label" that is most of the sentence is no label: keep the option whole.
  if (!cut || label.length > 60 || label.length < 3) return { number, label: text, consequence: '' }

  return { number, label, consequence: text.slice(cut.index + cut[0].length).trim() }
}

/** The memo's view of an ask. `topic` is the subject line a small model wrote, when it has one. */
export function describe(ask: Pick<Ask, 'move' | 'changed' | 'context' | 'topic'>): Described {
  const inMove = labelled(ask.move)
  const inContext = labelled(ask.context)
  const all = [...inMove.facts, ...inContext.facts]
  const stated = (key: string) => all.find(f => f.key === key)?.value ?? ''
  const choice = moveChoice(inMove.rest)
  const options = choice.options.map(o => option(o.number, o.text))

  let intro = choice.intro
  let recommend = stated('RECOMMEND')
  const said = RECOMMENDS.exec(intro)
  if (said) {
    intro = intro.replace(said[0], ' ').replace(/\s+/g, ' ').trim()
    if (!recommend) recommend = said[1]!.trim()
  }
  recommend = recommend.replace(/^[a-z]/, c => c.toUpperCase())

  const first = SENTENCE.exec(intro)?.[1]?.trim() ?? intro
  const isLong = first.length > LONG_QUESTION && !!ask.topic
  const question = isLong ? ask.topic! : first || ask.topic || 'This session needs you'

  const url = URL.exec(`${stated('PR')} ${stated('REVIEW')} ${inMove.rest}`)?.[0] ?? ''
  const command = CODE_SPAN.exec(intro)?.[1] ?? ''
  const named = KINDS[stated('KIND').toLowerCase()]
  // A numbered list is a choice only when the session recommends an item or its words ask for a pick.
  const isChoice =
    options.length >= 2 && (choice.recommended.length > 0 || /\?\s*$/.test(choice.intro) || CHOOSES.test(choice.intro))
  const kind: Kind =
    named ??
    (isChoice
      ? 'choose'
      : stated('REVIEW')
        ? 'review'
        : /\?$/.test(first) && !OPEN_QUESTION.test(first)
          ? 'go-ahead'
          : PULL.test(url)
            ? 'review'
            : command && RUNS.test(intro)
              ? 'do'
              : // "Yes" must answer a question the session asked, or a yes-or-no it recommended. Anything else,
                // as "Send a screenshot and say what is unclear", is answered in words.
                /^(yes|no)\b/i.test(recommend)
                ? 'go-ahead'
                : 'reply')
  // A list that is not drawn as options stays in the text, so nothing the session wrote goes unseen.
  const steps = kind === 'choose' ? [] : choice.options.map(o => `${o.number}. ${o.text}`)
  const body = [isLong ? intro : intro.slice(first.length).trim(), ...steps].filter(Boolean).join('\n')

  const blocks = stated('BLOCKS')
  const shown = [...(ask.changed ? [{ key: 'CHANGED', value: ask.changed }] : []), ...all]
    .filter(f => !STEERING.has(f.key) && f.value && !NOTHING.test(f.value))
    .sort((a, b) => rank(a.key) - rank(b.key))

  return {
    kind,
    question,
    body,
    recommend,
    options: kind === 'choose' ? options : [],
    recommended: choice.recommended,
    command: kind === 'do' ? command : '',
    url,
    blocks: NOTHING.test(blocks) ? '' : blocks,
    facts: shown,
  }
}

function rank(key: string): number {
  const at = FACT_ORDER.indexOf(key)
  return at < 0 ? FACT_ORDER.length : at
}

/** Asks in the order the pane works through them: those that block other work first, then the oldest. */
export function inOrder<A extends Pick<Ask, 'move' | 'changed' | 'context' | 'at'>>(asks: readonly A[]): A[] {
  const blocks = (a: A) => (describe(a).blocks ? 0 : 1)
  return [...asks].sort((a, b) => blocks(a) - blocks(b) || a.at - b.at)
}

/** A length of time in the fewest words: "now", "12 min", "2 h 10 min", "3 d"; `short` gives "12m", "2h", "3d". */
export function ago(ms: number, short = false): string {
  const minutes = Math.max(0, Math.floor(ms / 60_000))
  if (minutes < 1) return 'now'
  if (short) return minutes < 60 ? `${minutes}m` : minutes < 1440 ? `${Math.floor(minutes / 60)}h` : `${Math.floor(minutes / 1440)}d`
  if (minutes < 60) return `${minutes} min`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return minutes % 60 ? `${hours} h ${minutes % 60} min` : `${hours} h`

  return `${Math.floor(hours / 24)} d`
}
