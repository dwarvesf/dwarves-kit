// slop-cleaner (hooks/slop-cleaner.sh, Stop) as a gdp-wired rule, for one source file of one session. Advisory.
//
//   :23-24   stop_hook_active                      -> silent
//   :47-50   no session marker yet                 -> create it, silent (the first Stop has no baseline)
//   :55      outside a git work tree               -> silent
//   :61-70   only files modified since the marker are read
//   :85-86   an unreadable file is skipped (fixed: it used to end the hook with awk's exit 2, a blocked Stop;
//            'pre-fix' keeps that)
//   :123-137 a bloated file is reported unless the seen-file already holds it at the same content hash; reporting
//            records the hash
// State is the marker and the seen-file (both on disk), so every law is proven from any state. Content hashes are
// naturals here (0 = never seen).
import {bool, nat, rule, when} from 'gdp-wired'

export type Variant = 'shipped' | 'pre-fix' | 'no-memory'
export const VARIANTS: Variant[] = ['pre-fix', 'no-memory']

export function slopCleaner(v: Variant = 'shipped') {
  return rule(v === 'shipped' ? 'slop-cleaner' : `slop-cleaner/${v}`)
    .inputs({active: bool, git: bool, recent: bool, readable: bool, bloated: bool, hash: nat})
    .assume(({hash}) => hash.gt(0))
    .state({marker: bool.from(false), seen: 0, reported: bool.from(false), blocked: bool.from(false)})
    .flags(({active, git, recent, readable, bloated, hash, marker, seen}) => {
      const scans = active.not().and(marker).and(git).and(recent)
      return {
        report: scans.and(readable).and(bloated).and(v === 'no-memory' ? bloated : seen.eq(hash).not()),
        crash: v === 'pre-fix' ? scans.and(readable.not()) : scans.and(scans.not()),
      }
    })
    .step(({active, marker, seen, hash, report, crash}) => ({
      marker: marker.or(active.not()),
      seen: when(report, hash, seen),
      reported: report.and(crash.not()),
      blocked: crash,
    }))
}
export const make = slopCleaner

export function laws(r: ReturnType<typeof slopCleaner>) {
  return {
    laws: [],
    stepLaws: [
      r.stepLaw('an advisory hook never blocks the Stop', (b, a) => a.blocked.not()),
      r.stepLaw('the first Stop of a session is silent', (b, a) => a.reported.not(), (b) => b.marker.not()),
      r.stepLaw('a Stop already continuing is silent', (b, a) => a.reported.not(), (b) => b.active),
      r.stepLaw('a file is reported at most once per content', (b, a) => a.reported.not(), (b) => b.seen.eq(b.hash)),
      r.stepLaw('a report records the content it reported', (b, a) => a.reported.implies(a.seen.eq(b.hash))),
    ],
  }
}
