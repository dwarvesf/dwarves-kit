// Two diff-reading rules of lib/gate/ship-rules.sh, as gdp-wired decisions (the push gate and the mega merge gate
// both source them, so their verdicts are shared).
//
// ship_rule_large_spec: a normal-lane spec that `spec.sh depth size` calls large (exit 1: 4+ tasks, a deeper Depth,
// or no countable task) needs a validate gate whose LATEST row is ran or override; any other size exit (small 0,
// unreadable 2) or a missing spec.sh fails open. Facts: the lane is normal, spec.sh exists, the size exit, the
// latest validate row's state.
//
// ship_rule_floor: a diff that hits a hard path owes the full lane's gates (kit-root lanes) whatever the spec says.
// Facts: the run's ledger script exists; a merge base is known; [gate] lane_gates is on AS OF the merge base
// (`offAtBase`: the base's committed .kit.toml says false; a false committed only on the branch head counts for
// nothing); the classifier exists; the head differs from the base; the floor verb reports a hit; the full lane's
// required gates all have a ran/override latest row.
import {bool, fun, oneOf} from 'gdp-wired'

export const SIZES = ['small', 'large', 'unreadable'] as const
export const VSTATES = ['none', 'ran', 'override', 'skipped', 'rejected'] as const
export const Size = oneOf(...SIZES)
export const VState = oneOf(...VSTATES)

export type LargeVariant = 'shipped' | 'any-validate-row'
export function largeSpec(variant: LargeVariant = 'shipped') {
  return fun(variant === 'shipped' ? 'large-spec' : `large-spec/${variant}`)
    .inputs({normal: bool, specSh: bool, size: Size, validate: VState})
    .returns(({normal, specSh, size, validate}) => {
      const ok = variant === 'any-validate-row' ? validate.is('none').not() : validate.is('ran').or(validate.is('override'))
      return {block: normal.and(specSh).and(size.is('large')).and(ok.not())}
    })
}
export function largeLaws(f: ReturnType<typeof largeSpec>) {
  return [
    f.law('a large normal-lane spec with no validate that ran or was overridden refuses the push',
      (e) => [e.normal, e.specSh, e.size.is('large'), e.validate.is('ran').not(), e.validate.is('override').not()], (o) => o.block),
    f.law('a later skipped or rejected validate does not count', (e) => [e.normal, e.specSh, e.size.is('large'), e.validate.is('rejected')], (o) => o.block),
    f.law('only the normal lane is sized', (e) => [e.normal.not()], (o) => o.block.not()),
    f.law('a small or unreadable spec fails open', (e) => [e.size.is('large').not()], (o) => o.block.not()),
  ]
}

export type FloorVariant = 'shipped' | 'head-switch'
export function floor(variant: FloorVariant = 'shipped') {
  return fun(variant === 'shipped' ? 'floor' : `floor/${variant}`)
    .inputs({ledger: bool, base: bool, offAtBase: bool, offAtHead: bool, classifier: bool, moved: bool, hit: bool, fullGates: bool})
    .returns(({ledger, base, offAtBase, offAtHead, classifier, moved, hit, fullGates}) => {
      const off = variant === 'head-switch' ? offAtHead : offAtBase
      return {block: ledger.and(base).and(off.not()).and(classifier).and(moved).and(hit).and(fullGates.not())}
    })
}
export function floorLaws(f: ReturnType<typeof floor>) {
  return [
    f.law('a hard-path diff without the full lane\'s gates refuses the push',
      (e) => [e.ledger, e.base, e.offAtBase.not(), e.classifier, e.moved, e.hit, e.fullGates.not()], (o) => o.block),
    f.law('a PR cannot switch off its own floor: a false committed only on the branch head counts for nothing',
      (e) => [e.ledger, e.base, e.offAtBase.not(), e.offAtHead, e.classifier, e.moved, e.hit, e.fullGates.not()], (o) => o.block),
    f.law('the full lane\'s gates (or an override) clear the floor', (e) => [e.fullGates], (o) => o.block.not()),
    f.law('no hard-path hit, no floor', (e) => [e.hit.not()], (o) => o.block.not()),
  ]
}
