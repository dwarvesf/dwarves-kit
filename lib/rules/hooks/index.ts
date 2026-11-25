// Every hooks-and-autonomy rule of the kit, for lib/rules/hooks/prove.ts and for whoever wires a rule into the
// code that runs it. Each entry: the rule (make), the code it models (source), its laws, its kept broken variants
// (each must be refuted), the promised laws the code-faithful rule refutes (findings, kept so they stay visible),
// and the bridge that holds the real bash to the rule.
import * as advisory from './advisory.ts'
import * as anchorRoot from './anchor-root.ts'
import * as antiRat from './anti-rationalization.ts'
import * as batchDebt from './batch-debt-warn.ts'
import * as boardRow from './board-row-gate.ts'
import * as citation from './citation-guard.ts'
import * as codex from './codex-hook-adapter.ts'
import * as commitFormat from './commit-format.ts'
import * as ctxBudget from './context-budget.ts'
import * as ctxHints from './context-hints.ts'
import * as ctxReady from './context-readiness.ts'
import * as hardStops from './hard-stops.ts'
import * as stopTrigger from './harvest-stop-trigger.ts'
import * as updateNotice from './kit-update-notice.ts'
import * as moneyGate from './money-gate.ts'
import * as offload from './output-offload.ts'
import * as permission from './permission-auto-approve.ts'
import * as postCompact from './post-compact-reinject.ts'
import * as qlVerdict from './ql-verdict.ts'
import * as safetyGate from './safety-gate.ts'
import * as secrets from './secrets-guard.ts'
import * as slop from './slop-cleaner.ts'
import * as specDrift from './spec-drift-guard.ts'
import * as throttle from './throttle.ts'
import * as toolPolicy from './tool-policy-guard.ts'

export type BridgeResult = {agree: number, diverge: null | object, disagree?: number, notes?: string[]}
export type Entry = {
  name: string
  source: string
  kind: 'decision' | 'stateful'
  make: (variant?: any) => any
  laws: (r: any) => {laws: any[], stepLaws: any[], decisions?: any[], refutedSteps?: any[], refutedDecisions?: any[]}
  variants: string[]
  fixed?: string          // the kept variant that mirrors the bash before this branch fixed it
  bridge?: () => Promise<BridgeResult>
}

const lazy = (path: string) => async () => (await import(path)).bridge() as Promise<BridgeResult>

export const RULES: Entry[] = [
  {name: 'safety-gate', source: 'hooks/safety-gate.sh:main loop (per-segment rules :253-343)', kind: 'decision', make: safetyGate.make, laws: safetyGate.laws, variants: safetyGate.VARIANTS, fixed: 'pre-fix', bridge: lazy('./safety-gate.bridge.ts')},
  {name: 'secrets-guard', source: 'hooks/secrets-guard.sh:is_secret + Bash token check', kind: 'decision', make: secrets.make, laws: secrets.laws, variants: secrets.VARIANTS, bridge: lazy('./secrets-guard.bridge.ts')},
  {name: 'commit-format', source: 'hooks/commit-format.sh:subject lint', kind: 'decision', make: commitFormat.make, laws: commitFormat.laws, variants: commitFormat.VARIANTS, fixed: 'pre-fix', bridge: lazy('./commit-format.bridge.ts')},
  {name: 'anti-rationalization', source: 'hooks/anti-rationalization.sh (with the host stop loop)', kind: 'stateful', make: antiRat.make, laws: antiRat.laws, variants: antiRat.VARIANTS, fixed: 'pre-fix', bridge: lazy('./anti-rationalization.bridge.ts')},
  {name: 'hard-stops', source: 'docs/guides/autonomy.md + gates-and-proof.md (prose dial over the four stops)', kind: 'decision', make: hardStops.make, laws: hardStops.laws, variants: hardStops.VARIANTS},
  {name: 'spec-drift-guard', source: 'hooks/spec-drift-guard.sh', kind: 'decision', make: specDrift.make, laws: specDrift.laws, variants: specDrift.VARIANTS, bridge: lazy('./spec-drift-guard.bridge.ts')},
  {name: 'context-readiness', source: 'hooks/context-readiness.sh:SUGGEST routing', kind: 'decision', make: ctxReady.make, laws: ctxReady.laws, variants: ctxReady.VARIANTS, bridge: lazy('./context-readiness.bridge.ts')},
  {name: 'post-compact-reinject', source: 'hooks/post-compact-reinject.sh', kind: 'decision', make: postCompact.make, laws: postCompact.laws, variants: postCompact.VARIANTS, fixed: 'pre-fix', bridge: lazy('./post-compact-reinject.bridge.ts')},
  {name: 'money-gate', source: 'hooks/money-gate.sh (lib/money-gate/SPEC.md)', kind: 'decision', make: moneyGate.make, laws: moneyGate.laws, variants: moneyGate.VARIANTS, bridge: lazy('./money-gate.bridge.ts')},
  {name: 'tool-policy-guard', source: 'hooks/tool-policy-guard.sh', kind: 'decision', make: toolPolicy.make, laws: toolPolicy.laws, variants: toolPolicy.VARIANTS, bridge: lazy('./tool-policy-guard.bridge.ts')},
  {name: 'permission-auto-approve', source: 'hooks/permission-auto-approve.sh:stages a-f', kind: 'decision', make: permission.make, laws: permission.laws, variants: permission.VARIANTS, bridge: lazy('./permission-auto-approve.bridge.ts')},
  {name: 'board-row-gate', source: 'hooks/board-row-gate.sh', kind: 'decision', make: boardRow.make, laws: boardRow.laws, variants: boardRow.VARIANTS, bridge: lazy('./board-row-gate.bridge.ts')},
  {name: 'output-offload', source: 'hooks/output-offload.sh', kind: 'decision', make: offload.make, laws: offload.laws, variants: offload.VARIANTS, bridge: lazy('./output-offload.bridge.ts')},
  {name: 'citation-guard', source: 'hooks/citation-guard.sh', kind: 'decision', make: citation.make, laws: citation.laws, variants: citation.VARIANTS, bridge: lazy('./citation-guard.bridge.ts')},
  {name: 'anchor-root', source: 'hooks/anchor-root.sh + lib/config/hook-module.sh', kind: 'decision', make: anchorRoot.make, laws: anchorRoot.laws, variants: anchorRoot.VARIANTS, bridge: lazy('./anchor-root.bridge.ts')},
  {name: 'codex-hook-adapter', source: 'hooks/codex-hook-adapter.sh', kind: 'decision', make: codex.make, laws: codex.laws, variants: codex.VARIANTS, bridge: lazy('./codex-hook-adapter.bridge.ts')},
  {name: 'advisory-hooks', source: 'every advisory hook in hooks/ (exit code under hostile input)', kind: 'decision', make: advisory.make, laws: advisory.laws, variants: advisory.VARIANTS, fixed: 'pre-fix', bridge: lazy('./advisory.bridge.ts')},
  {name: 'batch-debt-warn', source: 'hooks/batch-debt-warn.sh (ledger merge-watch/<sid>.log)', kind: 'stateful', make: batchDebt.make ?? batchDebt.batchDebtWarn, laws: batchDebt.laws, variants: batchDebt.VARIANTS, bridge: lazy('./batch-debt-warn.bridge.ts')},
  {name: 'context-budget', source: 'hooks/context-budget.sh (state file per session)', kind: 'stateful', make: ctxBudget.make, laws: ctxBudget.laws, variants: ctxBudget.VARIANTS, bridge: lazy('./context-budget.bridge.ts')},
  {name: 'context-hints', source: 'hooks/context-hints.sh:temporal', kind: 'stateful', make: ctxHints.make, laws: ctxHints.laws, variants: ctxHints.VARIANTS, bridge: lazy('./context-hints.bridge.ts')},
  {name: 'kit-update-notice', source: 'hooks/kit-update-notice.sh:main', kind: 'stateful', make: updateNotice.make, laws: updateNotice.laws, variants: updateNotice.VARIANTS, bridge: lazy('./kit-update-notice.bridge.ts')},
  {name: 'slop-cleaner', source: 'hooks/slop-cleaner.sh (marker + seen-file)', kind: 'stateful', make: slop.make, laws: slop.laws, variants: slop.VARIANTS, fixed: 'pre-fix', bridge: lazy('./slop-cleaner.bridge.ts')},
  {name: 'harvest-throttle', source: 'lib/reflect/hook-util.sh:hu_throttled (backlog-stage, intake-sweep; harvest.sh:debounced)', kind: 'stateful', make: throttle.make, laws: throttle.laws, variants: throttle.VARIANTS, bridge: lazy('./throttle.bridge.ts')},
  {name: 'harvest-stop-trigger', source: 'hooks/harvest.sh --stop-trigger', kind: 'stateful', make: stopTrigger.make, laws: stopTrigger.laws, variants: stopTrigger.VARIANTS, bridge: lazy('./harvest-stop-trigger.bridge.ts')},
  {name: 'ql-verdict', source: 'lib/loop/ql-verdict.sh:resume', kind: 'stateful', make: qlVerdict.make, laws: qlVerdict.laws, variants: qlVerdict.VARIANTS, fixed: 'pre-fix', bridge: lazy('./ql-verdict.bridge.ts')},
]
