// The wrap, land and session area's rules: every implicit state machine and decision found in lib/wrap/,
// lib/session/handoffs.sh, lib/reflect/, lib/telemetry/kit-migrate.sh, lib/config/ (and the [gate] defaults it
// feeds), each as a gdp-wired rule written from what the bash does, with the laws the docs promise and the laws a
// reviewer would ask, the broken variants it rules out, and a bridge that runs the real bash beside it.
// lib/rules/wrap/prove.ts proves them all; FINDINGS.md is the table.
import type {Decision, KeyedLiveness, Law, StepLaw} from 'gdp-wired'
import type {BridgeResult} from './bridge-util.ts'

import * as mergeRetry from './merge-retry.ts'
import * as mergeDispatch from './merge-dispatch.ts'
import * as mergeCommand from './merge-command.ts'
import * as mergeCycle from './merge-cycle.ts'
import * as prGate from './pr-gate.ts'
import * as land from './land.ts'
import * as landMany from './land-many.ts'
import * as worktreeSweep from './worktree-sweep.ts'
import * as deployWait from './deploy-wait.ts'
import * as configPrecedence from './config-precedence.ts'
import * as moduleSwitch from './module-switch.ts'
import * as gatePolicy from './gate-policy.ts'
import * as handoffs from './handoffs.ts'
import * as throttle from './throttle.ts'
import * as kitMigrate from './kit-migrate.ts'
import * as debt from './debt-disposition.ts'

export type RuleEntry = {
  name: string
  source: string
  make: (variant?: any) => any
  laws: (r: any) => {laws: Law[], stepLaws: StepLaw[], decisions?: Decision[]}
  liveness?: (r: any) => KeyedLiveness[]
  variants: string[]
  // A promised law the code-faithful rule refutes (a finding left unfixed): prove.ts expects it refuted, and every
  // other law of the rule proven.
  refutes?: string[]
  bridge?: () => Promise<BridgeResult>
}

const lazy = (file: string) => async () => (await import(file)).bridge() as Promise<BridgeResult>

export const RULES: RuleEntry[] = [
  {name: 'merge-retry', source: 'lib/wrap/wrap-common.sh:_gh_merge_retry', make: mergeRetry.mergeRetry, laws: mergeRetry.laws,
    variants: mergeRetry.VARIANTS, bridge: lazy('./merge-retry.bridge.ts')},
  {name: 'merge-dispatch', source: 'lib/wrap/wrap-common.sh:_merge_pr', make: mergeDispatch.mergeDispatch, laws: mergeDispatch.laws,
    variants: mergeDispatch.VARIANTS, bridge: lazy('./merge-dispatch.bridge.ts')},
  {name: 'merge-command', source: 'lib/config/merge-command.sh:kit_merge_command', make: mergeCommand.mergeCommand, laws: mergeCommand.laws,
    variants: mergeCommand.VARIANTS, bridge: lazy('./merge-command.bridge.ts')},
  {name: 'merge-cycle', source: 'lib/wrap/wrap-common.sh:_merge_verify_push', make: mergeCycle.mergeCycle, laws: mergeCycle.laws,
    variants: mergeCycle.VARIANTS, bridge: lazy('./merge-cycle.bridge.ts')},
  {name: 'check-verdict', source: 'lib/wrap/wrap-merge.sh:_pr_gate (checks)', make: prGate.checkVerdict, laws: prGate.checkLaws,
    variants: prGate.CHECK_VARIANTS},
  {name: 'pr-gate', source: 'lib/wrap/wrap-merge.sh:_pr_gate', make: prGate.prGate, laws: prGate.gateLaws,
    variants: prGate.GATE_VARIANTS, bridge: lazy('./pr-gate.bridge.ts')},
  {name: 'land', source: 'lib/wrap/wrap-land.sh:_land_run', make: land.land, laws: land.laws,
    variants: land.VARIANTS, bridge: lazy('./land.bridge.ts')},
  {name: 'land-many', source: 'lib/wrap/wrap-land.sh:cmd_land', make: landMany.landMany, laws: landMany.laws,
    variants: landMany.VARIANTS, bridge: lazy('./land-many.bridge.ts')},
  {name: 'worktree-sweep', source: 'lib/wrap/wrap-apply.sh:_apply_worktrees', make: worktreeSweep.worktreeSweep, laws: worktreeSweep.laws,
    variants: worktreeSweep.VARIANTS, bridge: lazy('./worktree-sweep.bridge.ts')},
  {name: 'deploy-wait', source: 'lib/wrap/wrap-deploy.sh:_deploy_wait_poll', make: deployWait.deployWait, laws: deployWait.laws,
    liveness: (r) => [deployWait.ends(r)], variants: deployWait.VARIANTS, bridge: lazy('./deploy-wait.bridge.ts')},
  {name: 'config-precedence', source: 'lib/config/kit-config.sh:kit_config_get + lib/config/config.sh:_resolve',
    make: configPrecedence.configPrecedence, laws: configPrecedence.laws, variants: configPrecedence.VARIANTS, bridge: lazy('./config-precedence.bridge.ts')},
  {name: 'module-switch', source: 'lib/config/hook-module.sh', make: moduleSwitch.moduleSwitch, laws: moduleSwitch.laws,
    variants: moduleSwitch.VARIANTS, bridge: lazy('./module-switch.bridge.ts')},
  {name: 'gate-policy', source: 'lib/gate/gate-policy.sh:enabled', make: gatePolicy.gatePolicy, laws: gatePolicy.laws,
    variants: gatePolicy.VARIANTS, bridge: lazy('./gate-policy.bridge.ts')},
  {name: 'handoff-archive', source: 'lib/session/handoffs.sh:cmd_archive', make: handoffs.handoffArchive, laws: handoffs.archiveLaws,
    variants: handoffs.ARCHIVE_VARIANTS, bridge: lazy('./handoffs.bridge.ts')},
  {name: 'handoff-liveness', source: 'lib/session/handoffs.sh:handoff_liveness', make: handoffs.handoffLiveness, laws: handoffs.livenessLaws,
    variants: handoffs.LIVE_VARIANTS},
  {name: 'throttle', source: 'lib/reflect/hook-util.sh:hu_throttled', make: throttle.throttle, laws: throttle.laws,
    variants: throttle.VARIANTS, bridge: lazy('./throttle.bridge.ts')},
  {name: 'kit-migrate', source: 'lib/telemetry/kit-migrate.sh:_kit_migrate_corpus', make: kitMigrate.kitMigrate, laws: kitMigrate.laws,
    variants: kitMigrate.VARIANTS, bridge: lazy('./kit-migrate.bridge.ts')},
  {name: 'debt-disposition', source: 'lib/reflect/weekend-batch.sh:_disposition', make: debt.debtDisposition, laws: (r) => debt.laws(r),
    variants: debt.VARIANTS, refutes: ['a paid item is never collected again'], bridge: lazy('./debt-disposition.bridge.ts')},
]
