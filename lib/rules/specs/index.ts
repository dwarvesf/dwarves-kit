// The specs, board and intake area's rules: one entry per rule, with the bash it mirrors, its laws, its kept
// broken variants, the laws it refutes (findings), and the bridge that runs the real bash beside it.
// lib/rules/specs/prove.ts proves every entry; FINDINGS.md reports them.
import * as boardDedupe from './board-dedupe.ts'
import * as boardQueue from './board-queue.ts'
import * as boardRun from './board-run.ts'
import * as boardSet from './board-set.ts'
import * as boardWork from './board-work.ts'
import * as intakeGate from './intake-gate.ts'
import * as laneClassify from './lane-classify.ts'
import * as ledgerAppend from './ledger-append.ts'
import * as routeSuggest from './route-suggest.ts'
import * as significance from './significance.ts'
import * as specActive from './spec-active.ts'
import * as specDepth from './spec-depth.ts'
import * as specNext from './spec-next.ts'
import * as specStatus from './spec-status.ts'
import * as specTaskDone from './spec-task-done.ts'
import * as stateCheck from './state-check.ts'
import * as taskType from './task-type.ts'
import type {BridgeResult} from './util.ts'

type Laws = {laws: any[], stepLaws: any[], decisions?: any[]}
export type Entry = {
  name: string
  source: string
  kind: 'rule' | 'fun'
  make: (variant?: any) => any
  laws: (r: any) => Laws
  variants: string[]
  refuted?: (r: any) => Laws
  bridgeFile?: string
  bridge?: () => Promise<BridgeResult>
  fixed?: string
}

const lazy = (file: string) => async () => (await import(`./${file}`)).bridge() as Promise<BridgeResult>

export const RULES: Entry[] = [
  {name: 'spec-status', source: 'lib/spec/spec-status.sh:_set', kind: 'rule', make: specStatus.specStatus, laws: specStatus.laws,
    variants: specStatus.VARIANTS, refuted: specStatus.refuted, bridgeFile: 'spec-status.bridge.ts', bridge: lazy('spec-status.bridge.ts')},
  {name: 'spec-task-done', source: 'lib/spec/spec-task-done.sh:main', kind: 'rule', make: specTaskDone.specTaskDone, laws: specTaskDone.laws,
    variants: specTaskDone.VARIANTS, refuted: specTaskDone.refuted, bridgeFile: 'spec-task-done.bridge.ts', bridge: lazy('spec-task-done.bridge.ts'),
    fixed: 'the --verify-log destination is checked before the spec is renamed'},
  {name: 'spec-next', source: 'lib/spec/spec-next.sh:reserve', kind: 'rule', make: specNext.specNext, laws: specNext.laws,
    variants: specNext.VARIANTS, refuted: specNext.refuted, bridgeFile: 'spec-next.bridge.ts', bridge: lazy('spec-next.bridge.ts')},
  {name: 'spec-active', source: 'lib/spec/spec-active.sh:spec_active', kind: 'fun', make: specActive.specActive, laws: specActive.laws,
    variants: specActive.VARIANTS, refuted: specActive.refuted, bridgeFile: 'spec-active.bridge.ts', bridge: lazy('spec-active.bridge.ts')},
  {name: 'spec-depth', source: 'lib/spec/spec-depth.sh:cmd_size,cmd_check', kind: 'fun', make: specDepth.specDepth, laws: specDepth.laws,
    variants: specDepth.VARIANTS, bridgeFile: 'spec-depth.bridge.ts', bridge: lazy('spec-depth.bridge.ts'),
    fixed: 'a Depth line that names no valid level reads large, not standard'},
  {name: 'board-set', source: 'lib/board/backlog.sh:set_state', kind: 'rule', make: boardSet.boardSet, laws: boardSet.laws,
    variants: boardSet.VARIANTS, refuted: boardSet.refuted, bridgeFile: 'board-set.bridge.ts', bridge: lazy('board-set.bridge.ts')},
  {name: 'board-dedupe', source: 'lib/board/backlog.sh:dedupe,dedupe_all', kind: 'fun', make: boardDedupe.boardDedupe, laws: boardDedupe.laws,
    variants: boardDedupe.VARIANTS, refuted: boardDedupe.refuted, bridgeFile: 'board-dedupe.bridge.ts', bridge: lazy('board-dedupe.bridge.ts')},
  {name: 'board-queue', source: 'lib/board/parse-board.sh:pb_queue_rows', kind: 'fun', make: boardQueue.boardQueue, laws: boardQueue.laws,
    variants: boardQueue.VARIANTS, bridgeFile: 'board-queue.bridge.ts', bridge: lazy('board-queue.bridge.ts')},
  {name: 'board-run', source: 'lib/board/board-run.sh:main,_write_once', kind: 'rule', make: boardRun.boardRun, laws: boardRun.laws,
    variants: boardRun.VARIANTS, bridgeFile: 'board-run.bridge.ts', bridge: lazy('board-run.bridge.ts')},
  {name: 'board-work', source: 'lib/board/work.sh:JOIN(rung_of,agent_of,rec)', kind: 'fun', make: boardWork.boardWork, laws: boardWork.laws,
    variants: boardWork.VARIANTS, bridgeFile: 'board-work.bridge.ts', bridge: lazy('board-work.bridge.ts')},
  {name: 'state-check', source: 'lib/board/state_check.py:move_problem', kind: 'fun', make: stateCheck.stateCheck, laws: stateCheck.laws,
    variants: stateCheck.VARIANTS, bridgeFile: 'state-check.bridge.ts', bridge: lazy('state-check.bridge.ts'),
    fixed: 'ignore_case folds the transition lookup like classify()'},
  {name: 'intake-gate', source: 'lib/intake/intake.sh:cmd_gate,_row_kind', kind: 'fun', make: intakeGate.intakeGate, laws: intakeGate.laws,
    variants: intakeGate.VARIANTS, bridgeFile: 'intake-gate.bridge.ts', bridge: lazy('intake-gate.bridge.ts'),
    fixed: '`eval` must be a word for row_kind eval'},
  {name: 'lane-classify', source: 'lib/classify/lane-classify.sh:classify_core,lane_check,escalate', kind: 'fun', make: laneClassify.laneClassify,
    laws: laneClassify.laws, variants: laneClassify.VARIANTS, refuted: laneClassify.refuted, bridgeFile: 'lane-classify.bridge.ts', bridge: lazy('lane-classify.bridge.ts')},
  {name: 'significance', source: 'lib/classify/significance-classify.sh:classify_core', kind: 'fun', make: significance.significance,
    laws: significance.laws, variants: significance.VARIANTS, bridgeFile: 'significance.bridge.ts', bridge: lazy('significance.bridge.ts')},
  {name: 'task-type', source: 'lib/classify/task-type-classify.sh:task_type_classify', kind: 'fun', make: taskType.taskType, laws: taskType.laws,
    variants: taskType.VARIANTS, bridgeFile: 'task-type.bridge.ts', bridge: lazy('task-type.bridge.ts')},
  {name: 'route-suggest', source: 'lib/classify/route-suggest.sh:tier_of,main', kind: 'fun', make: routeSuggest.routeSuggest, laws: routeSuggest.laws,
    variants: routeSuggest.VARIANTS, bridgeFile: 'route-suggest.bridge.ts', bridge: lazy('route-suggest.bridge.ts'),
    fixed: 'an unknown model is no tier; MIN starts set'},
  {name: 'ledger-append', source: 'lib/ledger/ledger.sh:ledger_append', kind: 'rule', make: ledgerAppend.ledgerAppend, laws: ledgerAppend.laws,
    variants: ledgerAppend.VARIANTS, bridgeFile: 'ledger-append.bridge.ts', bridge: lazy('ledger-append.bridge.ts'),
    fixed: 'a torn last line is ended first; a `..` stream is refused'},
]
