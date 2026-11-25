// The one install-time move of the legacy run corpus into the durable ledger root
// (lib/telemetry/kit-migrate.sh:_kit_migrate_corpus, lines 35-62), across repeated installs.
//   durable/.migrated present          -> nothing (the sentinel)
//   legacy is a real dir               -> cp -Rn legacy/. durable/; on success write .migrated, drop .migrate-refused
//   legacy is a symlink                -> refuse: no copy, no sentinel, write .migrate-refused (the next run retries)
//   no legacy dir (a fresh install)    -> write .migrated
// Requests: legacy (the operator's legacy dir becomes absent, a real dir with a new log in it, a real dir holding
// one unreadable file so cp fails part way, or a symlink to a dir with a planted log), and run (an install).
import {bool, oneOf, rule, when} from 'gdp-wired'

export const LEGACY = ['absent', 'dir', 'dirBad', 'symlink'] as const

export type Variant = 'shipped' | 'sentinel-on-failure' | 'follow-symlink'
export const VARIANTS: Variant[] = ['sentinel-on-failure', 'follow-symlink']

export function kitMigrate(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'kit-migrate' : `kit-migrate/${variant}`)
    .inputs({op: oneOf('legacy', 'run'), kind: oneOf(...LEGACY)})
    .state({legacy: oneOf(...LEGACY).from('absent'), fresh: bool.from(false), sentinel: bool.from(false),
      refused: bool.from(false), copied: 0, planted: bool.from(false), complete: bool.from(false)})
    .step(({op, kind, legacy, fresh, sentinel, refused, copied, planted, complete}) => {
      const run = op.is('run').and(sentinel.not())
      const isDir = legacy.is('dir').or(legacy.is('dirBad')).or(variant === 'follow-symlink' ? legacy.is('symlink') : legacy.is('absent').and(legacy.is('dir')))
      const cpOk = run.and(isDir).and(legacy.is('dirBad').not())
      const cpRan = run.and(isDir)
      const refuses = run.and(legacy.is('symlink')).and(isDir.not())
      const markFresh = run.and(legacy.is('absent'))
      const marks = cpOk.or(markFresh).or(variant === 'sentinel-on-failure' ? cpRan : cpOk)
      const newLegacy = op.is('legacy')
      return {
        legacy: when(newLegacy, kind, legacy),
        // a new legacy dir means a new log the durable root does not hold yet
        fresh: when(newLegacy, kind.is('dir').or(kind.is('dirBad')).or(kind.is('symlink')), fresh.and(cpRan.not())),
        sentinel: sentinel.or(marks),
        refused: refuses.or(refused.and(cpOk.not())),
        copied: when(cpRan.and(fresh), copied.plus(1), copied),
        planted: planted.or(cpRan.and(legacy.is('symlink'))),
        // the sentinel was written by a copy that finished, or by a run that found no legacy dir
        complete: complete.or(cpOk).or(markFresh),
      }
    })
}

export function laws(r: ReturnType<typeof kitMigrate>) {
  return {
    laws: [
      r.law('nothing is ever copied through a symlinked legacy dir', ({planted}) => planted.not()),
      r.law('the sentinel means a copy finished or there was nothing to copy', ({sentinel, complete}) => sentinel.implies(complete)),
      // Not stated as a law: "a refusal marker never sits beside the sentinel". A refused symlink later removed takes
      // the fresh-install path, which writes .migrated and leaves .migrate-refused in place (inert: nothing reads
      // it). Recorded in FINDINGS.md as an observation.
      r.law('a finished copy writes the sentinel', ({complete, sentinel}) => complete.implies(sentinel)),
    ],
    stepLaws: [
      r.stepLaw('once the sentinel is down an install copies nothing', (b, a) => a.copied.eq(b.copied), (b) => b.sentinel),
      r.stepLaw('a copy that fails part way writes no sentinel, so the next install retries',
        (_b, a) => a.sentinel.not(), (b) => b.op.is('run').and(b.sentinel.not()).and(b.legacy.is('dirBad'))),
      r.stepLaw('a symlinked legacy dir is refused and recorded', (_b, a) => a.refused.and(a.sentinel.not()),
        (b) => b.op.is('run').and(b.sentinel.not()).and(b.legacy.is('symlink'))),
    ],
  }
}
