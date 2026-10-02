export type BoardMode = 'repo' | 'all'
export type BoardTone = 'cyan' | 'yellow'
export type BoardRow =
  | { kind: 'text'; text: string; isDim: boolean; isBold: boolean }
  | { kind: 'item'; id: string; text: string; repo?: string; tone?: BoardTone; isDim: boolean }
export type BoardState = { rows: BoardRow[]; mode: BoardMode; refreshedAt: string }
export type BoardTasks = { queued: number; executing: number }
// A field is absent when its source failed or does not exist; the band skips that segment.
export type BoardSummary = { tasks?: BoardTasks; handoffs?: number; worktrees?: number; prs?: number; prsAt?: number }

declare module 'claude-code' {
  interface PluginState {
    'board-pane': { state: BoardState; summary: BoardSummary }
  }
}
