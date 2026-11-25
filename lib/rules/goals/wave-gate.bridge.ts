// Bridge: lib/queue/orchestrate.sh `_wave_gate` (sourced, called directly as tests/test-orchestrate-hardening.sh
// does) against waveGate(). Seeded random mega-goals: four SG-NN sub-goals with a policy, a checked box, `depends`
// edges, and a goal file whose `## Touches` is one of the four provable prefixes, an unprovable glob, absent, or no goal
// file at all; random running ids, a random convergence hold and WAVE_CAP 1-3. The printed run/defer lines are
// compared with the rule's decisions over the same walk.
import {mkdirSync, rmSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {DEC, waveGate} from './wave-gate.ts'
import {cleanup, lib, rng, sh, tmp, type BridgeResult} from './_bridge.ts'

const TOUCH = ['lib/**', 'lib/a/**', 'lib/b/**', 'docs/**', 'src/*.md']
const N = 4

export async function bridge(opts: {cases?: number, seed?: number} = {}): Promise<BridgeResult> {
  const cases = opts.cases ?? 150
  const g = rng(opts.seed ?? 17)
  const r = waveGate(), it = r.interpreter()
  const root = tmp('wavegate-')
  let agree = 0, diverge: BridgeResult['diverge'] = null
  try {
    for (let c = 0; c < cases && !diverge; c++) {
      const dir = join(root, `m${c}`)
      rmSync(dir, {recursive: true, force: true}); mkdirSync(join(dir, 'goals'), {recursive: true})
      const sgs = Array.from({length: N}, (_, i) => ({
        id: `SG-0${i + 1}`, pol: g.pick(['auto', 'auto', 'auto', 'gate', 'gate!'] as const), checked: g.next() < 0.25,
        deps: Array.from({length: N}, (_, j) => j).filter(j => j !== i && g.next() < 0.2),
        p: g.pick([0, 1, 2, 3, 0, 1, 2, 3, 4, 5]), gf: g.next() < 0.9,
      }))
      const lines = sgs.map(s => `- [${s.checked ? 'x' : ' '}] ${s.id} title ${s.id} , ${s.pol}${s.deps.length ? ` , depends ${s.deps.map(j => `SG-0${j + 1}`).join(' ')}` : ''} , PR #__`)
      writeFileSync(join(dir, 'ROADMAP.md'), `# Mega-goal\n## Sub-goals\n${lines.join('\n')}\n`)
      for (const [i, s] of sgs.entries()) if (s.gf) writeFileSync(join(dir, 'goals', `0${i + 1}-x.md`), s.p === 5 ? '# goal\n\nno touches here\n' : `# goal\n\n## Touches\n- ${TOUCH[s.p]}\n`)
      const cap = g.pick([1, 2, 3])
      const running = sgs.filter(s => !s.checked && g.next() < 0.2).map(s => s.id)
      const hold = g.next() < 0.3 ? sgs.filter(() => g.next() < 0.4).map(s => s.id) : []
      const res = sh('bash', ['-c', `. "${lib('queue/orchestrate.sh')}" >/dev/null 2>&1; WAVE_CAP=${cap} _WAVE_GATE_HOLD="${hold.join(' ')}" _wave_gate "$1" "$1/ROADMAP.md" ${running.map(x => `"${x}"`).join(' ')}`, 'x', dir])
      const got = res.out.trim().split('\n').filter(Boolean).map(l => l.replace('\t', ' '))
      // --- the rule
      const P = r.encodeParams({cap})
      let st: any = it.init(P)
      for (const id of running) {
        const s = sgs.find(x => x.id === id)!
        st = it.step(P, st, r.encodeInput({op: 'seed', p: s.p, gf: s.gf, pol: s.pol, ready: true, running: true, held: false}))
      }
      const want: string[] = []
      for (const s of sgs) {
        const ready = !s.checked && s.deps.every(j => sgs[j].checked)
        const held = hold.length > 0 && s.deps.some(j => hold.includes(sgs[j].id))
        st = it.step(P, st, r.encodeInput({op: 'cand', p: s.p, gf: s.gf, pol: s.pol, ready, running: running.includes(s.id), held}))
        const d = DEC[st.scalars.dec]
        if (d !== 'none') want.push(`${d} ${s.id}`)
      }
      if (JSON.stringify(want) !== JSON.stringify(got)) diverge = {cap, running, hold, roadmap: lines, touches: sgs.map(s => s.gf ? (s.p === 5 ? '(none)' : TOUCH[s.p]) : '(no goal file)'), rule: want, bash: got, stderr: res.err.slice(0, 400)}
      else agree++
    }
  } finally { cleanup(root) }
  return {agree, diverge}
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const t0 = Date.now()
  const res = await bridge({cases: Number(process.env.CASES ?? 150), seed: Number(process.env.SEED ?? 17)})
  console.log(JSON.stringify(res, null, 1), `${Date.now() - t0}ms`)
  process.exit(res.diverge ? 1 : 0)
}
