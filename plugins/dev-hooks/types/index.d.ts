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
}

declare module 'claude-code' {
  interface PluginState {
    'dev-hooks': { contextBarShown: boolean; contextBarSnapshot: Snapshot | null }
  }
}
