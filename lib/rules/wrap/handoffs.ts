// Session handoffs (lib/session/handoffs.sh), two rules.
//
// handoff-archive: the life of one handoff name in <repo>/_meta/handoffs/ (cmd_archive 327-374). A file sitting in
// the directory is open; one moved into a subdirectory is consumed ("depth alone decides"). `archive <file>`:
//   refuses a file that is not a top-level *.md of the handoff dirs (an archived one included), a symlink, a missing
//   file, an existing archive/<name> target, and a tracked file while the checkout is on the default branch;
//   else `git mv` (tracked) or `mv -n` (untracked) into archive/. Never deletes.
// Requests: create (a session writes <name> at the top level; a no-op when one is there), archive (the top-level
// file), archiveAgain (archive pointed at archive/<name>).
//
// handoff-liveness: the verdict on one open handoff (handoff_liveness 169-194). The cited row IDs are read one at a
// time; each is open (a row in a live state), closed (a terminal state of lib/board/states.tsv, or done/resolved)
// or missing (no row: "unproven, not confirmed closed", counted open). UNCITED with none, DEAD when none is open,
// else LIVE.
import {bool, oneOf, rule, when} from 'gdp-wired'

export const OPS = ['create', 'archive', 'archiveAgain'] as const

export type ArchiveVariant = 'shipped' | 'overwrite-archive' | 'default-branch-moves'
export const ARCHIVE_VARIANTS: ArchiveVariant[] = ['overwrite-archive', 'default-branch-moves']

export function handoffArchive(variant: ArchiveVariant = 'shipped') {
  return rule(variant === 'shipped' ? 'handoff-archive' : `handoff-archive/${variant}`)
    .params({tracked: bool, onDefault: bool})
    .inputs({op: oneOf(...OPS)})
    .state({top: bool.from(false), arch: bool.from(false), created: 0, moved: 0, lost: 0})
    .step(({tracked, onDefault, op, top, arch, created, moved, lost}) => {
      const creates = op.is('create').and(top.not())
      const blocked = variant === 'default-branch-moves' ? tracked.and(tracked.not()) : tracked.and(onDefault)
      const destFree = variant === 'overwrite-archive' ? arch.or(arch.not()) : arch.not()
      const moves = op.is('archive').and(top).and(destFree).and(blocked.not())
      return {
        top: creates.or(top.and(moves.not())),
        arch: arch.or(moves),
        created: when(creates, created.plus(1), created),
        moved: when(moves, moved.plus(1), moved),
        // a move onto an existing archive copy loses the older file
        lost: when(moves.and(arch), lost.plus(1), lost),
      }
    })
}

export function archiveLaws(r: ReturnType<typeof handoffArchive>) {
  return {
    laws: [
      r.law('archive never deletes: every handoff written is still on disk', ({top, arch, created, lost}) =>
        when(top, 1, 0).plus(when(arch, 1, 0)).plus(lost).eq(created).and(lost.eq(0))),
      r.law('a handoff name is consumed at most once', ({moved}) => moved.atMost(1)),
      r.law('a tracked handoff is never moved while the checkout is on the default branch',
        ({tracked, onDefault, moved}) => tracked.and(onDefault).implies(moved.eq(0))),
      // helpers
      r.law('a move leaves an archived copy', ({moved, arch}) => moved.gt(0).implies(arch)),
      r.law('at most two copies of a name exist', ({created}) => created.atMost(2)),
      r.law('a second copy exists only beside an archived one', ({created, arch, top}) => created.eq(2).implies(arch.and(top))),
      r.law('an archived copy was moved there', ({moved, arch}) => arch.implies(moved.eq(1))),
    ],
    stepLaws: [
      r.stepLaw('archive pointed at an archived handoff changes nothing', (b, a) =>
        a.moved.eq(b.moved).and(a.created.eq(b.created)), (b) => b.op.is('archiveAgain')),
    ],
  }
}

export const STATUSES = ['open', 'closed', 'missing'] as const

export type LiveVariant = 'shipped' | 'missing-is-closed'
export const LIVE_VARIANTS: LiveVariant[] = ['missing-is-closed']

export function handoffLiveness(variant: LiveVariant = 'shipped') {
  return rule(variant === 'shipped' ? 'handoff-liveness' : `handoff-liveness/${variant}`)
    .inputs({st: oneOf(...STATUSES)})
    .state({n: 0, openN: 0, closedN: 0})
    .step(({st, n, openN, closedN}) => {
      const closed = variant === 'missing-is-closed' ? st.is('closed').or(st.is('missing')) : st.is('closed')
      return {n: n.plus(1), openN: when(closed, openN, openN.plus(1)), closedN: when(closed, closedN.plus(1), closedN)}
    })
}

export function livenessLaws(r: ReturnType<typeof handoffLiveness>) {
  return {
    laws: [
      r.law('every cited ID is counted open or closed', ({n, openN, closedN}) => openN.plus(closedN).eq(n)),
    ],
    stepLaws: [
      // The doc: "A row ID this repo's board cannot resolve counts as open (unproven, not confirmed closed)."
      r.stepLaw('an ID the board cannot resolve counts as open', (b, a) => a.openN.eq(b.openN.plus(1)), (b) => b.st.is('missing')),
      r.stepLaw('only a closed row counts toward DEAD', (b, a) => a.closedN.gt(b.closedN).implies(b.st.is('closed'))),
    ],
  }
}

// The verdict the bash prints for a final liveness state.
export const verdict = (s: {n: number, openN: number}) => s.n === 0 ? 'UNCITED' : s.openN === 0 ? 'DEAD' : 'LIVE'
