// Bridge: descriptions joined from phrases that each fire exactly one rule of task-type-classify.sh (checked: the
// atoms share no trigger words), every single feature and seeded mixes; the real `classify` against the rule.
import {join} from 'node:path'
import {FEATURES, taskType} from './task-type.ts'
import {KIT, run, seeded, type BridgeResult} from './util.ts'

const SH = join(KIT, 'lib/classify/task-type-classify.sh')
const ATOM: Record<(typeof FEATURES)[number], string> = {
  incident: 'triage the outage', learning: 'flashcard deck', planning: 're-rank', operate: 'payroll', absorb: 'absorb ideas',
  kitCo: 'into the kit', eval: 'benchmark', research: 'literature', reviewPos: 'security review', reviewNeg: 'address the review',
  doc: 'changelog', migration: 'rollout', reconcile: 'hygiene', dataTool: 'scraper',
}

export async function bridge(): Promise<BridgeResult> {
  const f = taskType()
  let agree = 0
  const one = (on: Set<string>) => {
    const desc = [...FEATURES.filter(k => on.has(k)).map(k => ATOM[k]), 'for the widget'].join(' and ')
    const bash = run(['bash', SH, 'classify', desc]).out.trim()
    const m = f.run(Object.fromEntries(FEATURES.map(k => [k, on.has(k)])) as never) as {type: string}
    if (bash !== m.type) return {desc, bash, rule: m.type}
    agree++
    return null
  }
  const x0 = one(new Set()); if (x0) return {agree, diverge: x0}
  for (const k of FEATURES) { const x = one(new Set([k])); if (x) return {agree, diverge: x} }
  const rand = seeded(11)
  for (let i = 0; i < 150; i++) {
    const on = new Set(FEATURES.filter(() => rand(4) === 0))
    const x = one(on); if (x) return {agree, diverge: x}
  }
  return {agree, diverge: null}
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify({bridge: await bridge()}, null, 1))
