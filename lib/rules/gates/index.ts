// Every rule of the gates area (lib/gate/ and the decision chain of hooks/ship-gate.sh), for a top-level prover.
//
// Each entry: `make(variant?)` builds the rule (a rule() or a fun()); `laws(r)` gives its invariants, step laws and,
// for a decision, its decisions; `variants` are the kept broken variants (each must be refused); `refuted` are laws
// the docs promise or a reviewer asks that the shipped code refutes (FINDINGS.md: each must stay refuted until the
// code changes, and is never weakened); `bridge` runs the real bash against the rule (a bridge may cover several
// entries of one file: `bridgeOf` names the entry that carries it).
import type {BridgeResult} from './harness.ts'
import * as fixture from './fixture-identities.ts'
import * as gatePolicy from './gate-policy.ts'
import * as inherit from './inherit.ts'
import * as knownFailures from './known-failures.ts'
import * as laneEffective from './lane-effective.ts'
import * as laneGate from './lane-gate-check.ts'
import * as negctl from './negctl.ts'
import * as premerge from './premerge.ts'
import * as proofCheck from './proof-check.ts'
import * as proofClassify from './proof-classify.ts'
import * as quiz from './quiz-gate.ts'
import * as recheck from './recheck-sample.ts'
import * as recordBatch from './record-batch.ts'
import * as redteam from './redteam-round.ts'
import * as review from './review-verdict.ts'
import * as shipGate from './ship-gate.ts'
import * as shipRules from './ship-rules.ts'
import * as validateRound from './validate-round.ts'

export type Laws = {laws: any[], stepLaws: any[], decisions?: any[]}
export type Entry = {
  name: string, source: string, kind: 'rule' | 'fun',
  make: (variant?: any) => any, laws: (r: any) => Laws, variants: string[],
  refuted?: (r: any) => Laws, bridge?: () => Promise<BridgeResult>, bridgeOf?: string,
}

const dec = (decisions: any[]): Laws => ({laws: [], stepLaws: [], decisions})
const lazy = (file: string) => async () => (await import(file)).bridge() as Promise<BridgeResult>

export const RULES: Entry[] = [
  {name: 'lane-gate-check', source: 'lib/gate/gate-ledger.sh:record,override,check,progress', kind: 'rule',
    make: laneGate.laneGateCheck, laws: laneGate.laws, variants: laneGate.VARIANTS, bridge: lazy('./lane-gate-check.bridge.ts')},
  {name: 'lane-effective', source: 'lib/gate/lane-data.sh:lane_effective + lib/gate/gate-ledger.sh:start', kind: 'rule',
    make: laneEffective.laneEffective, laws: laneEffective.laws, variants: laneEffective.VARIANTS, bridge: lazy('./lane-effective.bridge.ts')},
  {name: 'record-batch', source: 'lib/gate/gate-ledger.sh:record_batch', kind: 'fun',
    make: recordBatch.recordBatch, laws: (f) => dec(recordBatch.laws(f)), variants: recordBatch.VARIANTS, bridge: lazy('./record-batch.bridge.ts')},
  {name: 'inherit', source: 'lib/gate/gate-ledger.sh:inherit', kind: 'fun',
    make: inherit.inherit, laws: (f) => dec(inherit.laws(f)), variants: inherit.VARIANTS, bridge: lazy('./inherit.bridge.ts')},
  {name: 'validate-round', source: 'lib/gate/gate-ledger.sh:_vr_open,_vr_close,_vr_incomplete', kind: 'rule',
    make: validateRound.validateRound, laws: validateRound.laws, variants: validateRound.VARIANTS, bridge: lazy('./validate-round.bridge.ts')},
  {name: 'spec-verdict', source: 'lib/gate/ship-rules.sh:_sr_review_last_verdict', kind: 'rule',
    make: review.specVerdict, laws: review.specLaws, variants: review.SPEC_VARIANTS, bridge: lazy('./review-verdict.bridge.ts')},
  {name: 'ledger-verdict', source: 'lib/gate/gate-ledger.sh:review_verdict', kind: 'rule',
    make: review.ledgerVerdict, laws: review.ledgerLaws, variants: review.LEDGER_VARIANTS, bridgeOf: 'spec-verdict'},
  {name: 'review-gate', source: 'lib/gate/ship-rules.sh:ship_rule_review_verdict', kind: 'fun',
    make: review.reviewGate, laws: (f) => dec(review.gateLaws(f)), variants: review.GATE_VARIANTS, bridgeOf: 'spec-verdict'},
  {name: 'gate-policy', source: 'lib/gate/gate-policy.sh:enabled', kind: 'fun',
    make: gatePolicy.gatePolicy, laws: (f) => dec(gatePolicy.laws(f)), variants: gatePolicy.VARIANTS, bridge: lazy('./gate-policy.bridge.ts')},
  {name: 'fixture-email', source: 'lib/gate/ship-rules.sh:_sr_fixture_email', kind: 'fun',
    make: fixture.fixtureEmail, laws: (f) => dec(fixture.emailLaws(f)), variants: ['local-allowed'], bridge: lazy('./fixture-identities.bridge.ts')},
  {name: 'fixture-identities', source: 'lib/gate/ship-rules.sh:ship_rule_identities', kind: 'rule',
    make: fixture.identities, laws: fixture.foldLaws, variants: ['author-only'], bridgeOf: 'fixture-email'},
  {name: 'fixture-identities-block', source: 'lib/gate/ship-rules.sh:ship_rule_identities', kind: 'fun',
    make: () => fixture.blockDecision, laws: () => dec(fixture.blockLaws), variants: [], bridgeOf: 'fixture-email'},
  {name: 'large-spec', source: 'lib/gate/ship-rules.sh:ship_rule_large_spec', kind: 'fun',
    make: shipRules.largeSpec, laws: (f) => dec(shipRules.largeLaws(f)), variants: ['any-validate-row'], bridge: lazy('./ship-rules.bridge.ts')},
  {name: 'floor', source: 'lib/gate/ship-rules.sh:ship_rule_floor', kind: 'fun',
    make: shipRules.floor, laws: (f) => dec(shipRules.floorLaws(f)), variants: ['head-switch'], bridgeOf: 'large-spec'},
  {name: 'ship-gate', source: 'hooks/ship-gate.sh (the decision chain)', kind: 'fun',
    make: shipGate.shipGate, laws: (f) => dec(shipGate.laws(f)), variants: shipGate.VARIANTS,
    refuted: (f) => dec(shipGate.refutedLaws(f)), bridge: lazy('./ship-gate.bridge.ts')},
  {name: 'impl-notes', source: 'hooks/ship-gate.sh (full-lane implementation-notes rule)', kind: 'rule',
    make: shipGate.implNotes, laws: shipGate.notesLaws, variants: shipGate.NOTES_VARIANTS, refuted: shipGate.notesRefuted, bridgeOf: 'ship-gate'},
  {name: 'proof-check', source: 'lib/gate/proof-ledger.sh:check', kind: 'fun',
    make: proofCheck.proofCheck, laws: (f) => dec(proofCheck.laws(f)), variants: proofCheck.VARIANTS,
    refuted: (f) => dec(proofCheck.refutedLaws(f)), bridge: lazy('./proof-check.bridge.ts')},
  {name: 'proof-classify', source: 'lib/gate/proof-ledger.sh:classify', kind: 'fun',
    make: proofClassify.proofClassify, laws: (f) => dec(proofClassify.laws(f)), variants: proofClassify.VARIANTS,
    refuted: (f) => dec(proofClassify.refutedLaws(f)), bridge: lazy('./proof-classify.bridge.ts')},
  {name: 'proof-override-scope', source: 'lib/gate/proof-ledger.sh:is_overridden', kind: 'fun',
    make: proofClassify.overrideScope, laws: (f) => dec(proofClassify.scopeLaws(f)), variants: [], bridgeOf: 'proof-classify'},
  {name: 'negctl', source: 'lib/gate/negctl.sh (mutate mode)', kind: 'rule',
    make: negctl.negctl, laws: negctl.laws, variants: negctl.VARIANTS, bridge: lazy('./negctl.bridge.ts')},
  {name: 'known-failures', source: 'lib/gate/known-failures.sh:cmd_classify', kind: 'fun',
    make: knownFailures.knownFailures, laws: (f) => dec(knownFailures.laws(f)), variants: knownFailures.VARIANTS, bridge: lazy('./known-failures.bridge.ts')},
  {name: 'recheck-sample', source: 'lib/gate/recheck-sample.sh:decide', kind: 'fun',
    make: recheck.recheckSample, laws: (f) => dec(recheck.laws(f)), variants: recheck.VARIANTS, bridge: lazy('./recheck-sample.bridge.ts')},
  {name: 'redteam-round', source: 'lib/gate/redteam-gate.sh:cmd_round', kind: 'fun',
    make: redteam.redteamRound, laws: (f) => dec(redteam.laws(f)), variants: redteam.VARIANTS,
    refuted: (f) => dec(redteam.refutedLaws(f)), bridge: lazy('./redteam-round.bridge.ts')},
  {name: 'quiz-tap', source: 'lib/gate/quiz-gate.sh:cmd_tap', kind: 'fun',
    make: quiz.quizTap, laws: (f) => dec(quiz.tapLaws(f)), variants: quiz.VARIANTS, bridge: lazy('./quiz-gate.bridge.ts')},
  {name: 'quiz-respond', source: 'lib/gate/quiz-gate.sh:cmd_respond', kind: 'fun',
    make: () => quiz.quizRespond(), laws: (f) => dec(quiz.respondLaws(f)), variants: [], bridgeOf: 'quiz-tap'},
  {name: 'premerge', source: 'lib/gate/premerge.sh:cmd_check', kind: 'fun',
    make: premerge.premerge, laws: (f) => dec(premerge.laws(f)), variants: premerge.VARIANTS, bridge: lazy('./premerge.bridge.ts')},
]
