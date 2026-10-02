export type BoardTone = 'cyan' | 'yellow' | 'magenta'
export type BoardRow =
  | { kind: 'text'; text: string; isDim: boolean; isBold: boolean }
  | { kind: 'item'; id: string; text: string; repo?: string; tone?: BoardTone; isDim: boolean }
export type BoardItem = { id: string; title: string; state: string }
export type BoardRepo = {
  name: string
  rail?: string
  isCurrent: boolean
  behind: number
  items: BoardItem[]
}
// The pane's whole state: the data of the last refresh plus what the person did since.
export type BoardState = {
  repos: BoardRepo[]
  // The repo whose view is open; absent for the overview.
  repo?: string
  filter: string
  isExpanded: boolean
  // True when no registry was readable and the pane shows the session repo alone.
  isFallback: boolean
  errorLines: string[]
  refreshedAt: string
}
export type BoardTasks = { queued: number; executing: number }
// A field is absent when its source failed or does not exist; the band skips that segment.
export type BoardSummary = { tasks?: BoardTasks; handoffs?: number; worktrees?: number; prs?: number; prsAt?: number }

declare module 'claude-code' {
  interface PluginState {
    'board-pane': { state: BoardState; summary: BoardSummary }
  }
}
