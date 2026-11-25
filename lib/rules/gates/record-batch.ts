// `gate-ledger.sh record-batch <rid> <lane> [--evidence-default T] <phase>=<state>:<evidence> ...`
// (lib/gate/gate-ledger.sh:record_batch, :949), a decision over what the call carries and what the ledger holds.
//
// Facts: an item names a phase outside the lane's plan; an item's state is not ran|skipped|override; a phase is
// given twice; an item has no evidence and there is no --evidence-default (all four: exit 64 at parse); the dry run
// on a scratch copy refuses: an override reason already used on a different phase, by this call or the ledger
// (exit 65), or a grill skip without its reason= enum (64); the ledger's lane is stricter than the batch lane (start
// --amend refuses the lowering, 65). Otherwise it writes the START or START-AMEND and every item, then exits with
// check()'s status: `complete` = every required phase of the lane ends ran or override.
import {bool, fun} from 'gdp-wired'

export type Variant = 'shipped' | 'lowers' | 'partial-write'
export const VARIANTS: Variant[] = ['lowers', 'partial-write']

export function recordBatch(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'record-batch' : `record-batch/${variant}`)
    .inputs({unknownPhase: bool, badState: bool, dup: bool, noEvidence: bool, sharedReason: bool, grillBad: bool, lowers: bool, complete: bool})
    .returns(({unknownPhase, badState, dup, noEvidence, sharedReason, grillBad, lowers, complete}) => {
      const parse = unknownPhase.or(badState).or(dup).or(noEvidence)
      const dry = sharedReason.or(grillBad)
      const lowerRefused = variant === 'lowers' ? lowers.and(lowers.not()) : lowers
      const refused = parse.or(dry).or(lowerRefused)
      // partial-write: the bug a dry run exists to prevent (items written before a later item is refused)
      const wrote = variant === 'partial-write' ? parse.not().and(lowerRefused.not()) : refused.not()
      return {refused, wrote, exit0: refused.not().and(complete)}
    })
}

export function laws(f: ReturnType<typeof recordBatch>) {
  return [
    f.law('a refused record-batch writes nothing, START line included', () => [], (o) => o.refused.implies(o.wrote.not())),
    f.law('record-batch cannot lower a run\'s lane', (e) => [e.lowers], (o) => o.refused.and(o.wrote.not())),
    f.law('one override reason on two phases is refused', (e) => [e.sharedReason], (o) => o.refused),
    f.law('record-batch exits 0 only when the lane is complete', () => [], (o, e) => o.exit0.implies(e.complete)),
    f.law('a clean call writes every item', (e) => [e.unknownPhase.not(), e.badState.not(), e.dup.not(), e.noEvidence.not(),
      e.sharedReason.not(), e.grillBad.not(), e.lowers.not()], (o) => o.wrote),
  ]
}
