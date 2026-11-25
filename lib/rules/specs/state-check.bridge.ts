// Bridge: generated registries (states a, b, c and legacy `old`, spelled lowercase or Title case; with or without
// transitions a -> b -> c; ignore_case on or off) and stored values (none, a declared state, the legacy one, or
// `bogus`, in any case when ignore_case is on), passed through the real lib/board/state_check.py `norm` and
// `move_problem` in one python process; whether and why each move is refused is compared with the rule.
import {join} from 'node:path'
import {stateCheck, type Variant} from './state-check.ts'
import {KIT, run, seeded, tmp, type BridgeResult} from './util.ts'

const PY = `
import json, sys
import state_check as s
out = []
for c in json.load(sys.stdin):
    ic = c["m"].get("ignore_case", False)
    old = s.norm(c["old"], ic) if c["old"] is not None else None
    out.append(s.move_problem(c["m"], "k", old, s.norm(c["new"], ic)))
print(json.dumps(out))
`

export async function bridge(variant: Variant = 'shipped'): Promise<BridgeResult> {
  const f = stateCheck(variant)
  const t = tmp('state-check')
  try {
    const rand = seeded(460)
    const cases: any[] = [], inputs: any[] = []
    const spell = (w: string, lower: boolean) => lower ? w : w[0].toUpperCase() + w.slice(1)
    const anyCase = (w: string) => [w, w.toUpperCase(), w[0].toUpperCase() + w.slice(1)][rand(3)]
    for (let i = 0; i < 400; i++) {
      const ic = rand(2) === 1, lower = rand(2) === 1, hasTrans = rand(3) > 0
      const S = ['a', 'b', 'c'].map(w => spell(w, lower)), L = [spell('old', lower)]
      const m: any = {states: S, legacy: L}
      if (ic) m.ignore_case = true
      if (hasTrans) m.transitions = {[S[0]]: [S[1]], [S[1]]: [S[2]], [S[2]]: []}
      const pickVal = (allowNone: boolean) => {
        const k = rand(allowNone ? 4 : 3)
        const kind = allowNone ? ['none', 'declared', 'legacy', 'undeclared'][k] : ['declared', 'legacy', 'undeclared'][k]
        const word = kind === 'declared' ? ['a', 'b', 'c'][rand(3)] : kind === 'legacy' ? 'old' : 'bogus'
        const raw = kind === 'none' ? null : ic ? anyCase(word) : spell(word, lower)
        return {kind, word, raw}
      }
      const o = pickVal(true), n = pickVal(false)
      const listed = hasTrans && (o.word === 'a' && n.word === 'b' || o.word === 'b' && n.word === 'c')
      cases.push({m, old: o.raw, new: n.raw})
      inputs.push({oldKind: o.kind, newKind: n.kind, hasTrans, listed, ic, regLower: lower})
    }
    const res = run(['python3', '-c', PY], {cwd: t.dir, input: JSON.stringify(cases), env: {PYTHONPATH: join(KIT, 'lib/board'), STATES_ROOT: t.dir}})
    let got: (string | null)[]
    try { got = JSON.parse(res.out) } catch { return {agree: 0, diverge: {error: res.err.slice(0, 400)}} }
    let agree = 0
    for (let i = 0; i < cases.length; i++) {
      const p = got[i]
      const why = p === null ? 'ok' : p.includes('is not a declared state') ? 'undeclared' : p.includes('legacy value') ? 'legacy' : 'transition'
      const m = f.run(inputs[i]) as {why: string}
      if (why !== m.why) return {agree, diverge: {registry: cases[i].m, old: cases[i].old, new: cases[i].new, bash: p, rule: m.why, input: inputs[i]}}
      agree++
    }
    return {agree, diverge: null}
  } finally { t.done() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify({bridge: await bridge((process.argv[2] ?? 'shipped') as Variant)}, null, 1))
