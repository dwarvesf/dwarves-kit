// The `## Touches` disjointness rule both the wavefront (_wave_gate) and the goal registry (_reg_overlap) rest on:
// lib/gate/dispatch-gate.sh gate_normalize_glob (L44-54) + prefix_overlap (L80-86), as a gdp-wired decision over two
// `<prefix>/**` globs. (The gate is outside this area: modelled here because the goals area's disjointness laws are
// only as strong as it, ADR-0030 "Consequences".)
//
// A glob's prefix is one or two raw path segments, each a name (a, b), `.`, `..` or empty (`a//**`, a leading `/`).
// gate_normalize_glob accepts a `/**` prefix as PROVABLE only when every segment is a name (no `.`, `..` or empty
// segment; FINDINGS.md F8 fix), taken verbatim; anything else is `?`-marked and overlaps everything. prefix_overlap
// compares the verbatim strings on `/` boundaries. What the glob really covers is the prefix with `.` and empty segments dropped
// and `..` resolved (`esc` = it climbs out of the repo root).
import {type Cond, fun, nat, oneOf, type Term, when} from 'gdp-wired'

export const SEGS = ['a', 'b', 'dot', 'dotdot', 'empty'] as const
export const Seg = oneOf(...SEGS)

// The verbatim segment-wise comparison prefix_overlap makes: equal, or one an ancestor of the other.
function rawOverlap(n1: Term, x1: any, x2: any, n2: Term, y1: any, y2: any): Cond {
  const same1 = x1.eq(y1)
  const same2 = x2.eq(y2)
  return same1.and(n1.eq(1).or(n2.eq(1)).or(same2))
}

// Resolve up to two segments: [len, r1, r2, esc] with r in {0 = a, 1 = b}.
function resolve(n: Term, s1: any, s2: any) {
  const name = (s: any) => s.is('a').or(s.is('b'))
  const code = (s: any) => when(s.is('b'), 1, 0)
  // after s1
  const len1 = when(name(s1), 1, 0)
  const esc1 = s1.is('dotdot')
  // after s2 (when n = 2)
  const two = n.eq(2)
  const len = when(two.and(name(s2)), len1.plus(1), when(two.and(s2.is('dotdot')), len1.minus(1), len1))
  const esc = esc1.or(two.and(s2.is('dotdot')).and(len1.eq(0)))
  const r1 = when(name(s1), code(s1), code(s2))
  const r2 = code(s2)
  return {len, r1, r2, esc}
}

// 'equal-only' is the bug prefix_overlap's ancestor arms rule out: only identical prefixes would overlap.
// 'dot-segments' is the gate as found: any `[A-Za-z0-9._/-]+/**` was provable, so `./**` vs `a/**` passed as disjoint.
export type Variant = 'shipped' | 'equal-only' | 'dot-segments'
export const VARIANTS: Variant[] = ['equal-only', 'dot-segments']

export function touchesDisjoint(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'touches-disjoint' : `touches-disjoint/${variant}`)
    .inputs({n1: nat, x1: Seg, x2: Seg, n2: nat, y1: Seg, y2: Seg})
    .returns(({n1, x1, x2, n2, y1, y2}) => {
      // Provable only when every segment is a name; anything else is `?`-marked and overlaps everything.
      const name = (s: any) => s.is('a').or(s.is('b'))
      const provable = (n: Term, s1: any, s2: any) => variant === 'dot-segments'
        ? n.eq(1).and(s1.is('empty')).not()
        : name(s1).and(n.eq(1).or(name(s2)))
      const raw = (variant === 'equal-only' ? x1.eq(y1).and(n1.eq(n2)).and(n1.eq(1).or(x2.eq(y2))) : rawOverlap(n1, x1, x2, n2, y1, y2)).or(provable(n1, x1, x2).not()).or(provable(n2, y1, y2).not())
      const A = resolve(n1, x1, x2), B = resolve(n2, y1, y2)
      // really overlapping: one resolved prefix is an ancestor of (or equal to) the other; the root covers everything
      const prefix = A.len.eq(0).or(B.len.eq(0))
        .or(A.r1.eq(B.r1).and(A.len.eq(1).or(B.len.eq(1)).or(A.r2.eq(B.r2))))
      return {gateOverlaps: when(raw, 1, 0), reallyOverlaps: when(prefix.and(A.esc.not()).and(B.esc.not()), 1, 0)}
    })
}

export type TouchesFun = ReturnType<typeof touchesDisjoint>

// Promised (ADR-0019/0030, PHILOSOPHY "prove-or-serialize": any pair the gate cannot PROVE disjoint is serialized):
// two globs the gate calls disjoint never cover a common file. Was refuted (FINDINGS.md F8); proven since the fix.
export function laws(f: TouchesFun) {
  return [
    f.law('two Touches globs the gate proves disjoint never cover a common file',
      ({n1, n2}) => [n1.atLeast(1), n1.atMost(2), n2.atLeast(1), n2.atMost(2)],
      ({gateOverlaps, reallyOverlaps}) => gateOverlaps.eq(0).implies(reallyOverlaps.eq(0))),
  ]
}

// Holds: on plain name-only prefixes (no `.`, `..` or empty segment) the gate is exact.
export function plainLaws(f: TouchesFun) {
  const plain = (s: any) => s.is('a').or(s.is('b'))
  return [
    f.law('on plain directory prefixes the gate overlaps exactly when the globs share a file',
      ({n1, n2, x1, x2, y1, y2}) => [n1.atLeast(1), n1.atMost(2), n2.atLeast(1), n2.atMost(2), plain(x1), plain(y1), n1.eq(2).implies(plain(x2)), n2.eq(2).implies(plain(y2))],
      ({gateOverlaps, reallyOverlaps}) => gateOverlaps.eq(reallyOverlaps)),
  ]
}

