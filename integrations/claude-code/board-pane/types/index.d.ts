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
// One row of the overview's NEXT section: a queued item the priority view ranks worth picking.
export type BoardNext = { kind: 'now' | 'urgent' | 'quick'; id: string; title: string; repo: string }
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
  next: BoardNext[]
  refreshedAt: string
}
export type BoardTasks = { queued: number; executing: number }
// A field is absent when its source failed or does not exist; the band skips that segment.
// staleWorktrees is absent when the staleness lookup failed; the count itself is never dropped for it.
export type BoardSummary = {
  tasks?: BoardTasks
  handoffs?: number
  worktrees?: number
  staleWorktrees?: number
  prs?: number
  prsAt?: number
}

declare module 'claude-code' {
  interface PluginState {
    'board-pane': { state: BoardState; summary: BoardSummary }
  }
}
