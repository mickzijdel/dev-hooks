/** What one session is waiting on the person for. */
export type Ask = {
  /** The id of the session that asks. */
  session: string
  /** A short name for that session: the title the app gave it, else its first prompt, else its folder. */
  label: string
  /** What the ask is about, in one phrase a small model wrote. Absent until that call answers, and when it fails. */
  topic?: string
  /** When the ask was recorded, in `$.clock.now()` milliseconds. */
  at: number
  /** `move` is a "Your move" block at the end of a turn; `question` is an open AskUserQuestion dialog. */
  kind: 'move' | 'question'
  /** What the person must do or decide, as markdown. */
  move: string
  /** The "Changed" line, or empty. */
  changed: string
  /** What else stands above the "Details (skippable)" line, as markdown. */
  context: string
}

/** A session the mod runs in, whether or not it is waiting on the person. */
export type Presence = {
  session: string
  label: string
  /** `running` from the start of a turn to its end. */
  state: 'running' | 'idle'
  /** When the state began, in `$.clock.now()` milliseconds. */
  at: number
}

/** What the pane last did for the person, kept in view so the action can be followed up or put back. */
export type Receipt = {
  session: string
  label: string
  /** The text that was sent; empty when an ask was cleared and nothing was sent. */
  sent: string
  /** How to undo what the answer started, as the session stated it; empty when it stated nothing. */
  undo: string
  /** The ask that was cleared with nothing sent, so "Put back" can restore it. */
  cleared?: Ask
  /** When the answered ask was recorded: an ask with this time back in the list means the answer was not delivered. */
  askAt?: number
}

/** The pane's own state in one session. */
export type PaneView = {
  /** The session whose ask is the memo; null shows the first in order. */
  focus: string | null
  /** `view` shows buttons with keys; the others show one text field and no keys. */
  mode: 'view' | 'reply' | 'followup' | 'prompt'
  /** The session a new prompt goes to, in `prompt` mode. */
  target: string | null
  receipt: Receipt | null
}

declare module 'claude-code' {
  interface PluginState {
    asks: { list: Shaped<Ask[]>; sessions: Shaped<Presence[]>; view: Shaped<PaneView>; pending: Shaped<string[]> }
  }
}
