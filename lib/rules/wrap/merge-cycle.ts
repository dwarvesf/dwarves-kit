// The recovery merge cycle `wrap land` and `wrap merge` run on a CONFLICTING PR
// (lib/wrap/wrap-common.sh:_merge_verify_push 675-712 with _merge_default 406-541, _verify_or_undo 564-589,
// _push_ff 591-632, _undo_local 543-562, _merge_restore 373-404, the signal handler _mvp_trap 634-673).
//
// One request is one thing the cycle observed, in the order the bash meets them:
//   fetchFail / contains / fetchOk         git fetch origin <def>; is origin/<def> already in <tip>? (rc 1 / rc 4)
//   mergeOk / mergeRefused / restoreFail   _merge_default: merged, refused and restored (1 or 5), restore failed (2)
//   verifyPass / verifyFail                the caller's --verify (exit 0 with HEAD and tracked files unchanged, or not)
//   gatePass / gateBlock                   hooks/ship-gate.sh on the merge commit (_ship_gate_check)
//   pushOk / pushLanded                    the push exited 0, or failed but origin holds (or descends from) the commit
//   pushRefused / pushUnreadable           the push failed and origin still holds <tip> or moved / cannot be read (2)
//   undoClean / undoLeft                   _undo_local: back at <tip> and clean (1), or leftovers / reset refused (2)
//   signal                                 INT/TERM/HUP: the trap restores by state; 130, or 2 if it could not
// Phases: start, fetched, merged, verified, gated, undoing, and the ends ok, refused, stuck (rc 2), contains (rc 4),
// interrupted (rc 130). `onOrigin` is whether origin's branch holds the merge commit.
import {bool, oneOf, rule, when} from 'gdp-wired'

export const EVENTS = ['fetchFail', 'contains', 'fetchOk', 'mergeOk', 'mergeRefused', 'restoreFail', 'verifyPass', 'verifyFail',
  'gatePass', 'gateBlock', 'pushOk', 'pushLanded', 'pushRefused', 'pushUnreadable', 'undoClean', 'undoLeft', 'signal'] as const
export const PHASES = ['start', 'fetched', 'merged', 'verified', 'gated', 'undoing', 'ok', 'refused', 'stuck', 'contains', 'interrupted'] as const
export const TERMINAL = ['ok', 'refused', 'stuck', 'contains', 'interrupted'] as const

export type Variant = 'shipped' | 'push-on-red-verify' | 'skip-gate' | 'stuck-downgraded'
export const VARIANTS: Variant[] = ['push-on-red-verify', 'skip-gate', 'stuck-downgraded']

export function mergeCycle(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'merge-cycle' : `merge-cycle/${variant}`)
    .params({hasCmd: bool})
    .inputs({ev: oneOf(...EVENTS)})
    .state({phase: oneOf(...PHASES).from('start'), onOrigin: bool.from(false), verifyOk: bool.from(false),
      gateOk: bool.from(false), pushes: 0})
    .step(({hasCmd, ev, phase, onOrigin, verifyOk, gateOk, pushes}) => {
      const at = (p: typeof PHASES[number]) => phase.is(p)
      const live = at('start').or(at('fetched')).or(at('merged')).or(at('verified')).or(at('gated')).or(at('undoing'))
      // After the merge, the verify runs only with a command; without one the cycle goes straight to the gate.
      const verifyStep = at('merged').and(hasCmd)
      const gateStep = at('verified').or(at('merged').and(hasCmd.not()))
      const verifyRed = variant === 'push-on-red-verify' ? verifyStep.and(verifyStep.not()) : verifyStep.and(ev.is('verifyFail'))
      const verifyGreen = variant === 'push-on-red-verify' ? verifyStep.and(ev.is('verifyPass').or(ev.is('verifyFail'))) : verifyStep.and(ev.is('verifyPass'))
      const gatePassed = variant === 'skip-gate' ? gateStep.and(ev.is('gatePass').or(ev.is('gateBlock'))) : gateStep.and(ev.is('gatePass'))
      const gateBlocked = variant === 'skip-gate' ? gateStep.and(gateStep.not()) : gateStep.and(ev.is('gateBlock'))
      const pushing = at('gated')
      const pushed = pushing.and(ev.is('pushOk').or(ev.is('pushLanded')))
      const next = when(live.and(ev.is('signal')), 'interrupted',
        when(at('start').and(ev.is('fetchFail')), 'refused',
        when(at('start').and(ev.is('contains')), 'contains',
        when(at('start').and(ev.is('fetchOk')), 'fetched',
        when(at('fetched').and(ev.is('mergeOk')), 'merged',
        when(at('fetched').and(ev.is('mergeRefused')), 'refused',
        when(at('fetched').and(ev.is('restoreFail')), 'stuck',
        when(verifyGreen, 'verified',
        when(verifyRed, 'undoing',
        when(gatePassed, 'gated',
        when(gateBlocked, 'undoing',
        when(pushed, 'ok',
        when(pushing.and(ev.is('pushRefused')), 'undoing',
        when(pushing.and(ev.is('pushUnreadable')), 'stuck',
        when(at('undoing').and(ev.is('undoClean')), 'refused',
        when(at('undoing').and(ev.is('undoLeft')), variant === 'stuck-downgraded' ? 'refused' : 'stuck',
          phase))))))))))))))))
      return {
        phase: next,
        onOrigin: onOrigin.or(pushed),
        verifyOk: verifyOk.or(verifyGreen),
        gateOk: gateOk.or(gatePassed),
        pushes: when(pushing.and(ev.is('signal').not()).and(ev.is('pushOk').or(ev.is('pushLanded')).or(ev.is('pushRefused')).or(ev.is('pushUnreadable'))), pushes.plus(1), pushes),
      }
    })
}

export function laws(r: ReturnType<typeof mergeCycle>) {
  const ended = (p: {is: (x: string) => any}) => p.is('ok').or(p.is('refused')).or(p.is('stuck')).or(p.is('contains')).or(p.is('interrupted'))
  return {
    laws: [
      r.law('origin holds the merge commit only after the ship-gate passed it', ({onOrigin, gateOk}) => onOrigin.implies(gateOk)),
      r.law('with --verify, origin holds the merge commit only after the verify passed',
        ({onOrigin, verifyOk, hasCmd}) => onOrigin.and(hasCmd).implies(verifyOk)),
      r.law('one cycle makes at most one push', ({pushes}) => pushes.atMost(1)),
      r.law('a cycle that ends ok pushed its merge commit', ({phase, onOrigin}) => phase.is('ok').implies(onOrigin)),
      // helpers
      r.law('nothing is pushed before the push phase', ({phase, pushes, onOrigin}) =>
        phase.is('start').or(phase.is('fetched')).or(phase.is('merged')).or(phase.is('verified')).or(phase.is('gated'))
          .implies(pushes.eq(0).and(onOrigin.not()))),
      r.law('the push phase is reached only through a passed gate', ({phase, gateOk}) => phase.is('gated').implies(gateOk)),
      r.law('with --verify the gate is reached only through a passed verify',
        ({phase, gateOk, verifyOk, hasCmd}) => hasCmd.and(gateOk).implies(verifyOk).and(hasCmd.and(phase.is('verified')).implies(verifyOk))),
      r.law('a push leaves the push phase', ({phase, pushes}) => pushes.eq(1).implies(phase.is('gated').not())),
      r.law('a cycle that pushed is in a phase after the push', ({phase, pushes}) => pushes.eq(1).implies(
        phase.is('ok').or(phase.is('undoing')).or(phase.is('refused')).or(phase.is('stuck')).or(phase.is('interrupted')))),
      r.law('origin is written only by a push', ({pushes, onOrigin}) => onOrigin.implies(pushes.eq(1))),
    ],
    stepLaws: [
      r.stepLaw('a red verify never pushes: it undoes the merge commit',
        (_b, a) => a.phase.is('undoing').and(a.onOrigin.not()),
        (b) => b.phase.is('merged').and(b.hasCmd).and(b.ev.is('verifyFail')).and(b.onOrigin.not())),
      r.stepLaw('a blocked ship-gate never pushes: it undoes the merge commit',
        (_b, a) => a.phase.is('undoing').and(a.pushes.eq(0)),
        (b) => b.phase.is('verified').or(b.phase.is('merged').and(b.hasCmd.not())).and(b.ev.is('gateBlock')).and(b.pushes.eq(0))),
      r.stepLaw('a cycle that could not restore its state ends at 2, never downgraded to 1',
        (_b, a) => a.phase.is('stuck'), (b) => b.phase.is('undoing').and(b.ev.is('undoLeft'))),
      r.stepLaw('an ended cycle never moves again',
        (b, a) => a.phase.eq(b.phase).and(a.onOrigin.implies(b.onOrigin)).and(b.onOrigin.implies(a.onOrigin)).and(a.pushes.eq(b.pushes)), (b) => ended(b.phase)),
    ],
  }
}

// The exit code each end maps to (the cycle's own return convention).
export const RC: Record<string, number> = {ok: 0, refused: 1, stuck: 2, contains: 4, interrupted: 130}
