// Bridge: one real `orchestrate.sh run <megadir>` cycle against orchestratePick().
// Seeded random mega-goals of three SG-NN sub-goals (policy, `depends`, a goal file with **Branch:** and `## Touches`),
// some gate PRs already open (a fake `gh` answers `pr view <branch>`), WAVE_CAP 1 or 2. A fake `claude` records the
// sub-goal it was sent and exits 0 without flipping its box (NOCLAIM_RETRIES=0, so the run halts right after), and the
// megadir sits outside any git repo (so a wave fails at once, before any worktree). What the run did first (dispatched
// SG-NN, a wave, a STOP, a blocked halt) is compared with the rule. The decision's inputs are read off the same
// fixture; the wave admission count comes from the proven waveGate() rule (bridged on its own in wave-gate.bridge.ts).
import {existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {ACT, orchestratePick, type Variant} from './orchestrate-pick.ts'
import {DEC, waveGate} from './wave-gate.ts'
import {cleanup, lib, rng, sh, stub, tmp, type BridgeResult} from './_bridge.ts'

const TOUCH = ['lib/a/**', 'lib/b/**', 'docs/**']
const REGION = [1, 2, 3]   // their regions in goal-registry.ts's universe

export async function bridge(opts: {cases?: number, seed?: number, variant?: Variant} = {}): Promise<BridgeResult> {
  const cases = opts.cases ?? 60
  const g = rng(opts.seed ?? 23)
  const f = orchestratePick(opts.variant ?? 'shipped')
  const wg = waveGate(), wit = wg.interpreter()
  const root = tmp('orchpick-')
  const bin = join(root, 'bin'); mkdirSync(bin)
  stub(bin, 'claude', 'grep -m1 -oE "NEXT SUB-GOAL: SG-[0-9]+" | sed "s/NEXT SUB-GOAL: //" >> "$PICK_LOG"; exit 0')
  stub(bin, 'gh', '[ "${1:-}" = pr ] && [ "${2:-}" = view ] || exit 1\nawk -v b="${3:-}" \'$1==b {print $2; found=1} END{exit !found}\' "$GH_PRS" 2>/dev/null')
  let agree = 0, diverge: BridgeResult['diverge'] = null
  const acts: Record<string, number> = {}
  try {
    for (let c = 0; c < cases && !diverge; c++) {
      const dir = join(root, `m${c}`); mkdirSync(join(dir, 'goals'), {recursive: true})
      const sgs = Array.from({length: 3}, (_, i) => ({
        id: `SG-0${i + 1}`, pol: g.pick(['auto', 'auto', 'gate', 'gate!'] as const), checked: g.next() < 0.15,
        dep: i > 0 && g.next() < 0.25 ? i - 1 : -1, t: g.int(3), touches: g.next() < 0.85, pr: g.next() < 0.6,
      }))
      writeFileSync(join(dir, 'ROADMAP.md'), `# Mega-goal\n## Sub-goals\n${sgs.map(s => `- [${s.checked ? 'x' : ' '}] ${s.id} do ${s.id} , ${s.pol}${s.dep >= 0 ? ` , depends SG-0${s.dep + 1}` : ''} , PR #__`).join('\n')}\n`)
      writeFileSync(join(dir, 'POINTER_PROMPT.md'), 'POINTER: resume from ROADMAP\n')
      sgs.forEach((s, i) => writeFileSync(join(dir, 'goals', `0${i + 1}-x.md`), `**Branch:** feat/sg-${i + 1}\nDone = it works\n${s.touches ? `\n## Touches\n- ${TOUCH[s.t]}\n` : ''}`))
      writeFileSync(join(dir, 'prs.txt'), sgs.map((s, i) => s.pr && s.pol !== 'auto' ? `feat/sg-${i + 1} https://example.invalid/pr/${i + 1}\n` : '').join(''))
      const cap = g.pick([1, 2])
      const log = join(dir, 'picks.log')
      const res = sh('bash', [lib('queue/orchestrate.sh'), 'run', dir, '--board=roadmap'], {env: {
        PATH: `${bin}:${process.env.PATH}`, CLAUDE_CMD: 'claude', CLAUDE_FLAGS: '', GH_CMD: 'gh', GH_PRS: join(dir, 'prs.txt'), PICK_LOG: log,
        WAVE_CAP: String(cap), NOCLAIM_RETRIES: '0', TIER4_CLOSE: '0', TURN_CAP: '0', MEGA_GATE_DISPATCH: '1',
        DWARVES_KIT_LOG_DIR: join(dir, 'logs'), KIT_LEDGER_DIR: join(dir, 'logs'), PANE_VIEWER: 'none', MULTIPLEXER: '0', WAVE_ROLLING: '0',
      }})
      const out = res.out + res.err
      const picked = existsSync(log) ? readFileSync(log, 'utf8').trim().split('\n').filter(Boolean)[0] : undefined
      const got = picked ? `dispatch ${picked}` : /\[wave\]/.test(out) && /did not complete|not inside a git repo|cannot stand up/.test(out) ? 'wave'
        : /STOP|all sub-goals checked/.test(out) ? 'stop' : /blocked/.test(out) ? 'halt' : `?? ${out.slice(-300)}`
      // --- the decision's inputs, read off the fixture
      const ready = sgs.map(s => !s.checked && (s.dep < 0 || sgs[s.dep].checked))
      const P = wg.encodeParams({cap})
      let st: any = wit.init(P); const admittedIds: string[] = []
      sgs.forEach((s, i) => {
        st = wit.step(P, st, wg.encodeInput({op: 'cand', p: s.touches ? REGION[s.t] : 5, gf: true, pol: s.pol, ready: ready[i], running: false, held: false}))
        if (DEC[st.scalars.dec] === 'run') admittedIds.push(s.id)
      })
      const bangIdx = sgs.findIndex((s, i) => ready[i] && s.pol === 'gate!')
      const pickIdx = sgs.findIndex(s => !s.checked)
      const pick = pickIdx >= 0 ? sgs[pickIdx] : sgs[0]
      const out1 = f.run({cap2: cap >= 2, bang: bangIdx >= 0, bangHeld: bangIdx >= 0 && sgs[bangIdx].pr, admitted: Math.min(admittedIds.length, 2),
        pol: pick.pol, pickReady: pickIdx >= 0 && ready[pickIdx], pickHeld: pick.pol !== 'auto' && pick.pr, any: pickIdx >= 0} as never) as {act: number}
      const act = ACT[out1.act]
      const want = act === 'dispatch-pick' ? `dispatch ${pick.id}` : act === 'dispatch-bang' ? `dispatch ${sgs[bangIdx].id}`
        : act === 'dispatch-other' ? `dispatch ${admittedIds[0]}` : act
      if (want !== got) diverge = {cap, roadmap: readFileSync(join(dir, 'ROADMAP.md'), 'utf8').split('\n').filter(l => l.startsWith('- [')),
        touches: sgs.map(s => s.touches ? TOUCH[s.t] : '(none)'), open_prs: sgs.filter(s => s.pr && s.pol !== 'auto').map(s => s.id), rule: want, bash: got, tail: out.trim().split('\n').slice(-3)}
      else { agree++; acts[act] = (acts[act] ?? 0) + 1 }
    }
  } finally { cleanup(root) }
  return {agree, diverge, acts} as BridgeResult
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const t0 = Date.now()
  const res = await bridge({cases: Number(process.env.CASES ?? 60), seed: Number(process.env.SEED ?? 23), variant: (process.env.VARIANT as Variant) ?? 'shipped'})
  console.log(JSON.stringify(res, null, 1), `${Date.now() - t0}ms`)
  process.exit(res.diverge ? 1 : 0)
}
