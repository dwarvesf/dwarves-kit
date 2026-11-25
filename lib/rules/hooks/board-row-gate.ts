// board-row-gate (hooks/board-row-gate.sh, PreToolUse Bash) as a gdp-wired decision.
//
//   :29      DWARVES_KIT_SKIP_BOARD_ROW_GATE=1                            -> exit 0
//   :31-60   no `git ... commit` segment (heredoc bodies stripped)         -> exit 0
//   :94-102  no repo, no board (_meta/BACKLOG.md, else BACKLOG.md), a merge/rebase/cherry-pick/revert state, no HEAD -> 0
//   :206-224 the IDs the commit takes (index, plus the work tree for -a, a covering pathspec, or a git add earlier in the
//            command) minus the base's (HEAD, HEAD^ for --amend); none new -> exit 0
//   :232-236 gate-policy says board_row_gate is off (exit 1 only)          -> exit 0 (default ON)
//   :251     a `board-row-ok: <reason>` line in this commit's -m, heredoc or -F message -> exit 0
//   :252-269 otherwise exit 2
import {bool, fun} from 'gdp-wired'

export type Variant = 'shipped' | 'kill-switch-ignored' | 'marker-ignored' | 'blocks-status-flips'
export const VARIANTS: Variant[] = ['kill-switch-ignored', 'marker-ignored', 'blocks-status-flips']

export function boardRowGate(v: Variant = 'shipped') {
  return fun(v === 'shipped' ? 'board-row-gate' : `board-row-gate/${v}`)
    .inputs({skip: bool, commit: bool, board: bool, special: bool, head: bool, newRow: bool, rowChanged: bool, off: bool, marker: bool})
    .returns(({skip, commit, board, special, head, newRow, rowChanged, off, marker}) => {
      const s = v === 'kill-switch-ignored' ? skip.and(skip.not()) : skip
      const adds = v === 'blocks-status-flips' ? newRow.or(rowChanged) : newRow
      const m = v === 'marker-ignored' ? marker.and(marker.not()) : marker
      return {block: s.not().and(commit).and(board).and(special.not()).and(head).and(adds).and(off.not()).and(m.not())}
    })
}
export const make = boardRowGate

export function laws(f: ReturnType<typeof boardRowGate>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('a commit that adds no new board row is never blocked', (e) => [e.newRow.not()], (o) => o.block.not()),
      f.law('the session kill switch never blocks', (e) => [e.skip], (o) => o.block.not()),
      f.law('a repo opt-out never blocks', (e) => [e.off], (o) => o.block.not()),
      f.law('a board-row-ok line lets the commit through', (e) => [e.marker], (o) => o.block.not()),
      f.law('a merge, rebase, cherry-pick or revert in progress is never blocked', (e) => [e.special], (o) => o.block.not()),
      f.law('a new row with no board-row-ok line is blocked', (e) => [e.skip.not(), e.commit, e.board, e.special.not(), e.head, e.newRow, e.off.not(), e.marker.not()], (o) => o.block),
    ],
  }
}
