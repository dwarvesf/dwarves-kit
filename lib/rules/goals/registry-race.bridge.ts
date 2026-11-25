// Bridge: one real `goal-registry.sh claim` interleaved with another session's record, against registryRace().
// The other session's record is seeded before the claim (absent, partial = no touches= line yet, or full), and a
// `date` stub on PATH rewrites it at the one point reg_claim calls `date` (between its gate and its write), so the
// other session's steps land exactly between this claim's gate and its re-read. Every combination of the two record
// states and the two regions is run; the outcome (claimed or refused, which records remain) is compared with the
// rule run through the same interleaving.
import {existsSync, writeFileSync, rmSync, mkdirSync} from 'node:fs'
import {join} from 'node:path'
import {GLOBS} from './goal-registry.ts'
import {PCS, registryRace} from './registry-race.ts'
import {cleanup, initRepo, lib, sh, stub, tmp, type BridgeResult} from './_bridge.ts'

const SCRIPT = lib('goal/goal-registry.sh')
const STAGES = ['absent', 'partial', 'full'] as const
type Stage = typeof STAGES[number]

const record = (stage: Stage, region: number) => stage === 'absent' ? null
  : stage === 'partial' ? 'slug=s1\nlane=normal\n'
  : `slug=s1\nlane=normal\nbranch=x\nworktree=/elsewhere\ntouches=${GLOBS[region]}\nstarted=t\nupdated=t\n`

export async function bridge(): Promise<BridgeResult> {
  const root = tmp('race-'), reg = join(root, 'reg'), bin = join(root, 'bin'), repo = join(root, 'wt')
  mkdirSync(bin); initRepo(repo)
  stub(bin, 'date', `if [ -n "\${RACE_INJECT:-}" ] && [ ! -e "$RACE_DONE" ]; then : > "$RACE_DONE"; if [ "$RACE_INJECT" = absent ]; then rm -f "$RACE_FILE"; else printf '%b' "$RACE_BODY" > "$RACE_FILE"; fi; fi\nexec /bin/date "$@"`)
  const r = registryRace(), it = r.interpreter()
  let agree = 0, diverge: BridgeResult['diverge'] = null
  try {
    for (const before of STAGES) for (const during of STAGES) {
      if (STAGES.indexOf(during) < STAGES.indexOf(before)) continue   // a record never goes back while it is being claimed
      for (let mine = 0; mine < 4 && !diverge; mine++) for (let theirs = 0; theirs < 4 && !diverge; theirs++) {
        // --- the rule, through the same interleaving
        const step = (st: any, who: 's0' | 's1', p = 0) => it.step({}, st, r.encodeInput({who, p}))
        let st = it.init({})
        const advance = (from: Stage, to: Stage) => {
          let k = STAGES.indexOf(from)
          while (k < STAGES.indexOf(to)) {
            st = k === 0 ? step(step(st, 's1', theirs), 's1') : step(st, 's1')   // absent -> partial is gate + begin
            k++
          }
        }
        advance('absent', before)
        st = step(st, 's0', mine)                                                // my gate
        const gated = PCS[st.scalars.pc0] === 'gated'
        if (gated) {
          advance(before, during)
          st = step(step(step(st, 's0'), 's0'), 's0')                            // begin, finish, reread
        }
        const want = `${PCS[st.scalars.pc0] === 'claimed' ? 'claimed' : 'refused'}`
        // --- the real script
        rmSync(reg, {recursive: true, force: true}); mkdirSync(reg)
        const other = join(reg, 's1.goal'), done = join(root, 'injected')
        rmSync(done, {force: true})
        const b0 = record(before, theirs); if (b0) writeFileSync(other, b0)
        const b1 = record(during, theirs)
        const res = sh('bash', [SCRIPT, 'claim', 's0', 'normal', GLOBS[mine]], {cwd: repo, env: {
          GOAL_REGISTRY_DIR: reg, PATH: `${bin}:${process.env.PATH}`,
          RACE_INJECT: gated ? during : '', RACE_FILE: other, RACE_DONE: done, RACE_BODY: (b1 ?? '').replace(/\n/g, '\\n'),
        }})
        const got = res.code === 0 && existsSync(join(reg, 's0.goal')) ? 'claimed'
          : res.code === 1 && !existsSync(join(reg, 's0.goal')) ? 'refused' : `exit ${res.code}, record ${existsSync(join(reg, 's0.goal'))}`
        if (got !== want) diverge = {other_before: before, other_during: during, mine: GLOBS[mine], theirs: GLOBS[theirs], rule: want, bash: got, stderr: res.err.trim()}
        else agree++
      }
    }
  } finally { cleanup(root) }
  return {agree, diverge}
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const t0 = Date.now()
  const res = await bridge()
  console.log(JSON.stringify(res, null, 1), `${Date.now() - t0}ms`)
  process.exit(res.diverge ? 1 : 0)
}
