export type Segment = { name: string; tokens: number; color: string; kind: 'used' | 'free' | 'buffer' }
export type Snapshot = { segments: Segment[]; totalTokens: number; maxTokens: number; percentage: number }

// Session facts, kept in $.store under `facts:<session id>`.
export type RepoEdits = { root: string | null; files: string[]; added: number; bySubagent: number }
export type Facts = {
  updatedAt: number
  skills: { skill: string; at: number }[]
  agents: { description: string; subagentType: string; at: number }[]
  // root null: edited outside any git repo (scratchpad, memory dir, ~/.claude).
  repos: RepoEdits[]
  stops: { at: number; block: string | null }[]
  // Per file, when an Edit/Write last touched it: the evidence window for Stop nudges.
  lastEdit?: Record<string, number>
  // Stop nudges this session: one per hook reason the Stop orchestration returned.
  nudges?: Nudge[]
}

// Stop-nudge outcomes. A nudge is pending until a later Stop (or the session's end)
// resolves it from what the session did after it fired.
export type NudgeOutcome = 'acted' | 'ignored' | 'declined' | 'unknown'
export type Nudge = {
  hook: string
  at: number
  // The reason's first line, cut short.
  summary: string
  // Files the reason named (debug-leftover, missing-test).
  files?: string[]
  outcome?: NudgeOutcome
  resolvedAt?: number
  evidence?: string
}
// One resolved nudge, as kept across sessions in $.store under `nudgeOutcomes`.
export type NudgeRecord = {
  hook: string
  session: string
  at: number
  resolvedAt: number
  outcome: NudgeOutcome
  evidence: string
}
export type NudgeCounts = { fired: number } & Record<NudgeOutcome, number>

declare module 'claude-code' {
  interface PluginState {
    'dev-hooks': { contextBarShown: boolean; contextBarSnapshot: Snapshot | null; guardTimedOut: Record<string, string> }
  }
}
