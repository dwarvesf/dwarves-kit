// The spec task box and its verification log, as lib/spec/spec-task-done.sh edits them for ONE task id.
// Modelled from the code (line numbers are the fixed script):
//   - argument validation (spec-task-done.sh:53-64): a non-hex or short --commit, or --verify-log without
//     --command/--exit/--excerpt/--verdict (or those flags without --verify-log), exits 1 before any file moves.
//     `valid` stands for all of it.
//   - the one-pass awk (spec-task-done.sh:75-109): count the id's unchecked lines (`open`) and checked lines
//     (`done`); open == 0 exits 3 (never seen) or 4 (already checked), open > 1 exits 5; only open == 1 flips.
//   - the log destination check (FIX, spec-task-done.sh:111-118): with --verify-log, a directory that cannot be
//     made or a log that cannot be written exits 1 BEFORE the spec is renamed. The shipped code before the fix
//     renamed the spec first and then died in `mkdir -p` / `>>`, leaving the spec checked and no log entry
//     (variant 'log-after-flip').
//   - the append (spec-task-done.sh:123-137): exactly one `## <ID> title` entry per successful call with a log.
// `logOk` says whether the --verify-log destination is writable; `pass` whether --verdict says PASS.
import {bool, nat, rule, when} from 'gdp-wired'

export type Variant = 'shipped' | 'log-after-flip' | 'flips-duplicates' | 'reflips-checked'
export const VARIANTS: Variant[] = ['log-after-flip', 'flips-duplicates', 'reflips-checked']

export function specTaskDone(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'spec-task-done' : `spec-task-done/${variant}`)
    .inputs({valid: bool, withLog: bool, logOk: bool, pass: bool})
    .state({open: 0, done: 0, logged: 0, failed: bool.from(false)})
    .step(({valid, withLog, logOk, open, done, logged}) => {
      const one = variant === 'flips-duplicates' ? open.atLeast(1)
        : variant === 'reflips-checked' ? open.eq(1).or(open.eq(0).and(done.atLeast(1)))
          : open.eq(1)
      const destOk = withLog.not().or(logOk)
      // Shipped: the destination is checked before the rename. Before the fix it was not.
      const flips = variant === 'log-after-flip' ? valid.and(one) : valid.and(one).and(destOk)
      const logs = flips.and(withLog).and(logOk)
      return {
        open: when(flips, open.minus(1), open),
        done: when(flips, done.plus(1), done),
        logged: when(logs, logged.plus(1), logged),
        failed: flips.not().or(withLog.and(logOk.not())),
      }
    })
}

export function laws(r: ReturnType<typeof specTaskDone>) {
  return {
    laws: [],
    stepLaws: [
      r.stepLaw('a refused call changes neither the spec nor the verification log',
        (b, a) => a.open.eq(b.open).and(a.done.eq(b.done)).and(a.logged.eq(b.logged)),
        (b) => b.valid.not().or(b.open.eq(1).not()).or(b.withLog.and(b.logOk.not()))),
      r.stepLaw('a call that exits 0 checks exactly one line off',
        (b, a) => a.failed.not().implies(a.done.eq(b.done.plus(1)).and(a.open.plus(1).eq(b.open)))),
      r.stepLaw('a task is checked off only when it has exactly one unchecked line',
        (b, a) => a.done.gt(b.done).implies(b.open.eq(1))),
      r.stepLaw('an id that is already checked is never checked again',
        (b, a) => a.done.eq(b.done).and(a.failed), (b) => b.open.eq(0)),
      r.stepLaw('a checked-off task with --verify-log always gets exactly one log entry',
        (b, a) => a.done.gt(b.done).and(b.withLog).implies(a.logged.eq(b.logged.plus(1)))),
      r.stepLaw('a log entry is written only together with the check-off',
        (b, a) => a.logged.gt(b.logged).implies(a.done.eq(b.done.plus(1)).and(b.withLog))),
      r.stepLaw('a checked line is never unchecked and no unchecked line appears',
        (b, a) => a.done.atLeast(b.done).and(a.open.atMost(b.open))),
    ],
  }
}

// A reviewer's law, refuted by the faithful rule and left unfixed: the script takes the `(DONE, commit, verified)`
// flip with no --verify-log at all, and with any --verdict text (FAIL included). commands/execute.md promises the
// call is made "after an end PASS" with `--verdict PASS`; the script does not hold the caller to it.
export function refuted(r: ReturnType<typeof specTaskDone>) {
  return {
    laws: [],
    stepLaws: [
      r.stepLaw('a task is marked verified only with a recorded PASS verification log entry',
        (b, a) => a.done.gt(b.done).implies(b.withLog.and(b.pass).and(a.logged.gt(b.logged)))),
    ],
  }
}
