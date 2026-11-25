// Bridge: the real quiz-gate.sh, copied into a throwaway kit tree whose significance classifier is a stub that
// prints the verdict under test (STUB_VERDICT; the classifier itself is lib/classify's, outside this area), run
// for every (PR kind, verdict); and the real `respond` for every response word, with the debt ledger read back.
import {join} from 'node:path'
import {cpSync} from 'node:fs'
import {bash, GATE, KIT, product, sandbox, write, type BridgeResult} from './harness.ts'
import {KINDS, quizRespond, quizTap, RESPONSES, SIG} from './quiz-gate.ts'

const KIND: Record<string, string[]> = {gate: ['gate', ''], gatedFinal: ['gated-final'], routine: ['routine', 'docs']}
const VERDICT: Record<string, string> = {tap: 'tap', log: 'log', notSignificant: 'not-significant', nothing: ''}

export async function bridge(): Promise<BridgeResult> {
  const sb = sandbox(), tap = quizTap(), resp = quizRespond()
  const tree = join(sb.dir, 'kit')
  cpSync(join(GATE, 'quiz-gate.sh'), join(tree, 'lib/gate/quiz-gate.sh'))
  cpSync(join(GATE, 'gate-ledger.sh'), join(tree, 'lib/gate/gate-ledger.sh'))
  for (const d of ['config', 'telemetry', 'ledger', 'spec']) cpSync(join(KIT, 'lib', d), join(tree, 'lib', d), {recursive: true})
  for (const f of ['lane-data.sh', 'ledger-key.sh']) cpSync(join(GATE, f), join(tree, 'lib/gate', f))
  cpSync(join(KIT, 'kit.toml'), join(tree, 'kit.toml'))
  write(join(tree, 'lib/classify/significance-classify.sh'), '#!/usr/bin/env bash\n[ -n "$STUB_VERDICT" ] || exit 1\necho "$STUB_VERDICT"\n')
  const QG = join(tree, 'lib/gate/quiz-gate.sh'), GL = join(tree, 'lib/gate/gate-ledger.sh')
  let agree = 0
  try {
    for (const c of product({kind: KINDS, verdict: SIG})) for (const flag of KIND[c.kind]) {
      const real = bash(sb, [QG, 'tap', 'rid-q', ...(flag ? ['--pr-kind', flag] : []), 'a change'], {env: {STUB_VERDICT: VERDICT[c.verdict]}})
      const o = tap.run(c)
      if ((real.out.includes('worth understanding') !== o.nudge) || (real.code === 0) !== o.exit0)
        return {agree, diverge: {part: 'tap', facts: c, flag, model: o, bash: {code: real.code, out: real.out}}}
      agree++
    }
    for (const [i, r] of RESPONSES.entries()) {
      const rid = `resp-${i}`
      const real = bash(sb, [QG, 'respond', rid, r === 'other' ? 'ignore' : r])
      const log = bash(sb, [GL, 'show', rid]).out
      const o = resp.run({response: r})
      const loggedAs = (log.match(/\| DEBT \|.*response=([a-z]+)/) ?? [])[1]
      const ok = o.logged ? real.code === 0 && loggedAs === (o.asAccept ? 'accept' : r) : real.code === 64 && !loggedAs
      if (!ok) return {agree, diverge: {part: 'respond', response: r, model: o, bash: {code: real.code, log}}}
      agree++
    }
  } finally { sb.done() }
  return {agree, diverge: null}
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
