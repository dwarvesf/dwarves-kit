export type BoardMode = 'repo' | 'all'
export type BoardTone = 'cyan' | 'yellow'
export type BoardRow =
  | { kind: 'text'; text: string; isDim: boolean; isBold: boolean }
  | { kind: 'item'; id: string; text: string; repo?: string; tone?: BoardTone; isDim: boolean }
export type BoardState = { rows: BoardRow[]; mode: BoardMode; refreshedAt: string }

declare module 'claude-code' {
  interface PluginState {
    'board-pane': { state: BoardState }
  }
}
