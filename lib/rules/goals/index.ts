// The goals / mega-goals / queue area's rules: every implicit state machine and decision in lib/goal, lib/mega/mega.sh,
// lib/queue (queue, watch-board, orchestrate's wavefront) and lib/decide/flick.sh that gdp-wired can hold, each with
// the laws it must keep, the broken variants it must refuse, and a bridge to the real bash.
//
//   laws(r) -> {laws, stepLaws, decisions}   proven from ANY state (the ledgers are reloaded from disk)
//   findings(r)                               promised laws the code-faithful rule REFUTES, kept and expected refuted
//                                             until the bash is fixed (FINDINGS.md); prove.ts fails if one turns proven
//   variants                                  bugs each rule rules out; prove.ts fails if any is proven
import {attemptState, laws as attemptLaws, VARIANTS as attemptVariants} from './attempt-state.ts'
import {goalRegistry, laws as registryLaws, VARIANTS as registryVariants} from './goal-registry.ts'
import {registryRace, laws as raceLaws, VARIANTS as raceVariants} from './registry-race.ts'
import {queueGuard, laws as guardLaws, VARIANTS as guardVariants} from './queue-guard.ts'
import {queueConductors, laws as conductorLaws, VARIANTS as conductorVariants} from './queue-conductors.ts'
import {queueNight, laws as nightLaws, VARIANTS as nightVariants} from './queue-night.ts'
import {waveGate, laws as waveLaws, VARIANTS as waveVariants} from './wave-gate.ts'
import {orchestratePick, laws as pickLaws, VARIANTS as pickVariants} from './orchestrate-pick.ts'
import {megaStatus, laws as statusLaws, pendingLaws, VARIANTS as statusVariants} from './mega-status.ts'
import {megaMerge, laws as mergeLaws, VARIANTS as mergeVariants} from './mega-merge.ts'
import {flickEgress, laws as flickLaws, VARIANTS as flickVariants} from './flick-egress.ts'
import {megagoals, laws as megagoalsLaws, VARIANTS as megagoalsVariants} from './megagoals.ts'
import {goalDrafts, laws as draftsLaws, VARIANTS as draftsVariants} from './goal-drafts.ts'
import {touchesDisjoint, laws as touchesPromised, plainLaws as touchesLaws, VARIANTS as touchesVariants} from './touches-disjoint.ts'
import type {BridgeResult} from './_bridge.ts'

export type LawSet = {laws: any[], stepLaws: any[], decisions?: any[]}
export type RuleEntry = {
  name: string
  source: string
  kind: 'rule' | 'decision'
  make: (variant?: any) => any
  laws: (r: any, variant?: any) => LawSet
  findings?: (r: any) => LawSet
  variants: string[]
  fixed?: string[]                 // the variants that are the bash as it was found, before a fix in this change
  bridge?: () => Promise<BridgeResult>
}

const rules = (f: (r: any) => {laws: any[], stepLaws: any[]}) => (r: any) => ({...f(r), decisions: []})
const decisions = (f: (r: any) => any[]) => (r: any) => ({laws: [], stepLaws: [], decisions: f(r)})

export const RULES: RuleEntry[] = [
  {name: 'attempt-state', source: 'lib/goal/attempt-state.sh:as_dispatch..as_abandon', kind: 'rule',
    make: v => attemptState(v), laws: rules(attemptLaws), variants: attemptVariants,
    bridge: async () => (await import('./attempt-state.bridge.ts')).bridge()},
  {name: 'goal-registry', source: 'lib/goal/goal-registry.sh:reg_claim,reg_release', kind: 'rule',
    make: v => goalRegistry(v), laws: rules(registryLaws), variants: registryVariants, fixed: ['takeover'],
    bridge: async () => (await import('./goal-registry.bridge.ts')).bridge()},
  {name: 'registry-race', source: 'lib/goal/goal-registry.sh:reg_claim (gate, write, re-read)', kind: 'rule',
    make: v => registryRace(v), laws: rules(raceLaws), variants: raceVariants,
    bridge: async () => (await import('./registry-race.bridge.ts')).bridge()},
  {name: 'queue-guard', source: 'lib/queue/queue.sh:_breaker_apply,_stall_bump,_schedule_retry + watch-board.sh:_guard_skip_reason,_reap_stale_runs', kind: 'rule',
    make: v => queueGuard(v), laws: rules(guardLaws), variants: guardVariants, fixed: ['error-unbounded'],
    bridge: async () => (await import('./queue-guard.bridge.ts')).bridge()},
  {name: 'queue-conductors', source: 'lib/queue/queue.sh:cmd_run,_beat_claim + watch-board.sh:_guard_skip_reason', kind: 'rule',
    make: v => queueConductors(v), laws: rules(conductorLaws), variants: conductorVariants, fixed: ['unclaimed'],
    bridge: async () => (await import('./queue-conductors.bridge.ts')).bridge()},
  {name: 'queue-night', source: 'lib/queue/queue.sh:cmd_run (row loop)', kind: 'rule',
    make: v => queueNight(v), laws: rules(nightLaws), variants: nightVariants,
    bridge: async () => (await import('./queue-night.bridge.ts')).bridge()},
  {name: 'wave-gate', source: 'lib/queue/orchestrate.sh:_wave_gate,_ready_set', kind: 'rule',
    make: v => waveGate(v), laws: rules(waveLaws), variants: waveVariants,
    bridge: async () => (await import('./wave-gate.bridge.ts')).bridge()},
  {name: 'orchestrate-pick', source: 'lib/queue/orchestrate.sh:cmd_run (cycle body)', kind: 'decision',
    make: v => orchestratePick(v), laws: decisions(pickLaws), variants: pickVariants, fixed: ['redispatch'],
    bridge: async () => (await import('./orchestrate-pick.bridge.ts')).bridge()},
  {name: 'mega-status', source: 'lib/mega/mega.sh:_classify,cmd_status', kind: 'decision',
    make: v => megaStatus(v), laws: decisions(statusLaws), findings: decisions(pendingLaws), variants: statusVariants,
    bridge: async () => (await import('./mega-status.bridge.ts')).bridge()},
  {name: 'mega-merge', source: 'lib/goal/mega-merge.sh:merge', kind: 'decision',
    make: v => megaMerge(v), laws: decisions(mergeLaws), variants: mergeVariants,
    bridge: async () => (await import('./mega-merge.bridge.ts')).bridge()},
  {name: 'flick-egress', source: 'lib/decide/flick.sh:main,guard_ok,word_gate_apply', kind: 'decision',
    make: v => flickEgress(v), laws: decisions(flickLaws), variants: flickVariants,
    bridge: async () => (await import('./flick-egress.bridge.ts')).bridge()},
  {name: 'megagoals', source: 'lib/goal/megagoals.sh:count_subgoals,cmd_list', kind: 'rule',
    make: v => megagoals(v), laws: (r, v) => ({...megagoalsLaws(r, v), decisions: []}), variants: megagoalsVariants, fixed: ['h1-leaks'],
    bridge: async () => (await import('./megagoals.bridge.ts')).bridge()},
  {name: 'goal-drafts', source: 'lib/goal/goal-drafts.sh:drafts_archive', kind: 'rule',
    make: v => goalDrafts(v), laws: rules(draftsLaws), variants: draftsVariants,
    bridge: async () => (await import('./goal-drafts.bridge.ts')).bridge()},
  {name: 'touches-disjoint', source: 'lib/gate/dispatch-gate.sh:gate_normalize_glob,prefix_overlap', kind: 'decision',
    make: v => touchesDisjoint(v), laws: decisions(f => [...touchesLaws(f), ...touchesPromised(f)]), variants: touchesVariants, fixed: ['dot-segments'],
    bridge: async () => (await import('./touches-disjoint.bridge.ts')).bridge()},
]
