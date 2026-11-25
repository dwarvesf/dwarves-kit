// `board run <ID>` (lib/board/board-run.sh) scaffolding one row's megadir, over repeated runs into one dir:
//   - the row is read through `backlog.sh row` (board-run.sh:main step 1): no row or a duplicated id exits 1, and a
//     row with no item text exits 1; nothing is written then;
//   - a shipped, dropped or parked row warns and scaffolds anyway ("the run, not the board, is your call");
//   - _write_once (board-run.sh:_write_once) writes each of ROADMAP.md, POINTER_PROMPT.md, goals/01-<slug>.md,
//     HANDOFF.md, DECISIONS.md only when it does not exist: an existing file is `kept`, never overwritten;
//   - it never writes the board (read only through `backlog.sh row`) and never launches anything without --exec.
// State per file: present, and which run wrote it (`v`, 0 for a file that was there before any run). `req` names
// the run. The goal file's name depends on the item, so the bridge keeps the item fixed and varies the Notes.
import {bool, nat, oneOf, rule, when} from 'gdp-wired'

export const FILES = ['roadmap', 'pointer', 'goal', 'handoff', 'decisions'] as const
export type Variant = 'shipped' | 'overwrites' | 'refuses-terminal' | 'writes-on-bad-row'
export const VARIANTS: Variant[] = ['overwrites', 'refuses-terminal', 'writes-on-bad-row']

export function boardRun(variant: Variant = 'shipped') {
  const st: Record<string, unknown> = {warned: bool.from(false), refused: bool.from(false), boardWrites: 0}
  for (const f of FILES) { st[`${f}`] = bool.from(false); st[`${f}V`] = 0 }
  return rule(variant === 'shipped' ? 'board-run' : `board-run/${variant}`)
    .inputs({row: oneOf('ok', 'missing', 'dup', 'noItem'), terminal: bool, req: nat})
    .state(st as never)
    .step((e: any) => {
      const ok = variant === 'writes-on-bad-row' ? e.row.is('missing').not() : e.row.is('ok')
      const goes = variant === 'refuses-terminal' ? ok.and(e.terminal.not()) : ok
      const out: Record<string, unknown> = {
        warned: goes.and(e.terminal),
        refused: goes.not(),
        boardWrites: e.boardWrites,
      }
      for (const f of FILES) {
        const writes = variant === 'overwrites' ? goes : goes.and(e[f].not())
        out[f] = e[f].or(goes)
        out[`${f}V`] = when(writes, e.req, e[`${f}V`])
      }
      return out as never
    })
}

export function laws(r: ReturnType<typeof boardRun>) {
  const R: any = r
  return {
    laws: [
      R.law('board run never writes the board', (e: any) => e.boardWrites.eq(0)),
    ],
    stepLaws: [
      ...FILES.map(f => R.stepLaw(`an existing ${f} file is never overwritten`,
        (b: any, a: any) => a[`${f}V`].eq(b[`${f}V`]).and(a[f]), (b: any) => b[f])),
      R.stepLaw('a run on a readable row leaves all five scaffold files in place',
        (b: any, a: any) => FILES.map(f => a[f]).reduce((x: any, y: any) => x.and(y)), (b: any) => b.row.is('ok')),
      R.stepLaw('a missing, duplicated or item-less row writes nothing',
        (b: any, a: any) => FILES.map(f => a[`${f}V`].eq(b[`${f}V`]).and(a[f].implies(b[f])).and(b[f].implies(a[f]))).reduce((x: any, y: any) => x.and(y)).and(a.refused),
        (b: any) => b.row.is('ok').not()),
      R.stepLaw('a shipped, dropped or parked row is scaffolded anyway, with a warning',
        (b: any, a: any) => a.warned.and(a.refused.not()), (b: any) => b.row.is('ok').and(b.terminal)),
    ],
  }
}
