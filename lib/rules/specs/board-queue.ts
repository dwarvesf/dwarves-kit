// The overnight-queue allow-list, lib/board/parse-board.sh `pb_queue_rows` (behind `board queue`): which board
// rows reach an unattended runner. A row is emitted only when every gate passes, in this order: its leading status
// is `queued`; it carries a `#queue{...}` tag; the tag has non-empty repo= and pointer=; repo matches
// ^[A-Za-z0-9_-]+$ and pointer ^[A-Za-z0-9_./-]+$; pointer is relative; it has no `..` component; repo= names the
// board's own repo; the canonical <root>/<pointer> lies under <root>/_meta/megagoals/ or <root>/.claude/goals/;
// and that file exists. Any failure is a skip, never an error.
// Each input is one gate's verdict on the row (`inside` and `exists` judged on the canonical path).
import {bool, fun} from 'gdp-wired'

export const GATES = ['queued', 'tag', 'keys', 'repoChars', 'ptrChars', 'relative', 'noDotDot', 'ownRepo', 'inside', 'exists'] as const
export type Variant = 'shipped' | 'trusts-repo' | 'no-containment' | 'emits-dangling'
export const VARIANTS: Variant[] = ['trusts-repo', 'no-containment', 'emits-dangling']

export function boardQueue(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'board-queue' : `board-queue/${variant}`)
    .inputs(Object.fromEntries(GATES.map(g => [g, bool])) as Record<(typeof GATES)[number], typeof bool>)
    .returns((e: any) => {
      const skip = new Set(variant === 'trusts-repo' ? ['ownRepo'] : variant === 'no-containment' ? ['inside'] : variant === 'emits-dangling' ? ['exists'] : [])
      return {emit: GATES.filter(g => !skip.has(g)).map(g => e[g]).reduce((a: any, b: any) => a.and(b))}
    })
}

export function laws(f: ReturnType<typeof boardQueue>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('an emitted pointer lies under _meta/megagoals/ or .claude/goals/ of the repo', () => [], (o: any, e: any) => o.emit.implies(e.inside)),
      f.law('a row claiming another repo is never emitted (cross-repo spoofing)', (e: any) => e.ownRepo.not(), (o: any) => o.emit.not()),
      f.law('a pointer to a missing file is never emitted', (e: any) => e.exists.not(), (o: any) => o.emit.not()),
      f.law('a pointer with a .. component or an absolute path is never emitted', (e: any) => e.noDotDot.and(e.relative).not(), (o: any) => o.emit.not()),
      f.law('a token with a shell metacharacter is never emitted', (e: any) => e.repoChars.and(e.ptrChars).not(), (o: any) => o.emit.not()),
      f.law('only a queued row is ever emitted', () => [], (o: any, e: any) => o.emit.implies(e.queued.and(e.tag))),
      f.law('a queued row whose tag passes every gate is emitted', (e: any) => GATES.map(g => e[g]), (o: any) => o.emit),
    ],
  }
}
