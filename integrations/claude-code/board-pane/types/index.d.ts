export type BoardLines = string[]
export type BoardMode = 'repo' | 'all'
export type BoardState = { lines: BoardLines; mode: BoardMode; isError: boolean }

declare module 'claude-code' {
  interface PluginState {
    'board-pane': { state: BoardState }
  }
}
