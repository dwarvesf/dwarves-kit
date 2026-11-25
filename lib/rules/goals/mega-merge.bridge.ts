// Bridge: `lib/goal/mega-merge.sh merge` against megaMerge(), offline the way tests/test-mega-merge.sh runs it: every
// GitHub read is injected (MEGA_MERGE_PR_{HEAD,INFO,FILES,BASE,FETCH}_CMD), the gate ledger is a pass/fail stub
// (MEGA_MERGE_GATE_LEDGER), MEGA_MERGE_ROOT is a throwaway repo whose HEAD is the pinned PR head, and a fake `gh` on
// PATH records whether `gh pr merge` ran. Seeded random combinations of every input, plus each single-input flip of a
// mergeable baseline, are run; the outcome (exit 64 / 75 / BLOCKED / DRY-RUN / gh pr merge) is compared with the rule.
// The project merge command is bridged as absent or unreadable (a [merge] key with no origin to verify it); the custom
// command's exec and verify arms are proven but not bridged (they need a GitHub remote; FINDINGS.md "gaps").
import {rmSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {megaMerge, OUT} from './mega-merge.ts'
import {cleanup, git, initRepo, lib, rng, sh, stub, tmp, type BridgeResult} from './_bridge.ts'

type In = {expect: 'none' | 'malformed' | 'match' | 'mismatch', headOk: boolean, excl: 'clear' | 'held' | 'unreadable', cfg: 'clear' | 'touches' | 'unreadable',
  baseOk: boolean, fetch: 'ok' | 'fail' | 'moved', gate: boolean, mcmd: 'none' | 'unreadable', review: boolean, execute: boolean, baseSame: boolean}

export async function bridge(opts: {cases?: number, seed?: number} = {}): Promise<BridgeResult> {
  const cases = opts.cases ?? 160
  const g = rng(opts.seed ?? 29)
  const f = megaMerge()
  const root = tmp('megamerge-'), repo = join(root, 'fix')
  initRepo(repo)
  const tip = git(repo, 'rev-parse', 'HEAD')
  git(repo, 'commit', '-q', '--allow-empty', '-m', 'pr')
  const head = git(repo, 'rev-parse', 'HEAD')
  const S = (n: string, body: string) => stub(root, n, body)
  const env = {
    MEGA_MERGE_ROOT: repo, KIT_CONFIG_OPERATOR: join(root, 'no-operator'), PATH: `${root}/bin:${process.env.PATH}`,
    MEGA_MERGE_PR_HEAD_CMD: S('prhead', `[ "$BR_HEADOK" = 1 ] && echo ${head} || exit 1`),
    MEGA_MERGE_PR_INFO_CMD: S('prinfo', `case "$BR_EXCL" in clear) printf 'false\\037enhancement\\037normal PR\\n' ;; held) printf 'false\\037do-not-merge\\037held final\\n' ;; *) exit 1 ;; esac`),
    MEGA_MERGE_PR_FILES_CMD: S('prfiles', `case "$BR_CFG" in clear) printf 'src/app.ts\\n' ;; touches) printf 'docs/x.md\\n.kit.toml\\n' ;; *) exit 1 ;; esac`),
    MEGA_MERGE_PR_BASE_CMD: S('prbase', `n=$(cat "$BR_CALLS" 2>/dev/null || echo 0); echo $((n + 1)) > "$BR_CALLS"\n[ "$BR_BASEOK" = 1 ] || exit 1\nif [ "$n" -ge 1 ] && [ "$BR_BASESAME" != 1 ]; then echo retargeted; else echo main; fi`),
    MEGA_MERGE_PR_FETCH_CMD: S('prfetch', `case "$BR_FETCH" in ok) echo ${tip} ;; moved) exit 2 ;; *) exit 1 ;; esac`),
    GL_PASS: S('gl-pass', 'exit 0'), GL_FAIL: S('gl-fail', 'echo "MISSING-GATE: build" >&2; exit 1'),
  }
  sh('mkdir', ['-p', `${root}/bin`])
  stub(join(root, 'bin'), 'gh', `echo "$*" >> "${root}/gh.log"\nexit 0`)
  const base: In = {expect: 'none', headOk: true, excl: 'clear', cfg: 'clear', baseOk: true, fetch: 'ok', gate: true, mcmd: 'none', review: false, execute: true, baseSame: true}
  const flips: Partial<In>[] = [{}, {expect: 'malformed'}, {expect: 'match'}, {expect: 'mismatch'}, {headOk: false}, {excl: 'held'}, {excl: 'unreadable'},
    {cfg: 'touches'}, {cfg: 'unreadable'}, {baseOk: false}, {fetch: 'fail'}, {fetch: 'moved'}, {gate: false}, {mcmd: 'unreadable'},
    {review: true}, {execute: false}, {baseSame: false}]
  const inputs: In[] = [...flips.map(x => ({...base, ...x}))]
  for (let i = 0; i < cases; i++) inputs.push({
    expect: g.pick(['none', 'none', 'malformed', 'match', 'mismatch'] as const), headOk: g.next() < 0.85, excl: g.pick(['clear', 'clear', 'held', 'unreadable'] as const),
    cfg: g.pick(['clear', 'clear', 'touches', 'unreadable'] as const), baseOk: g.next() < 0.85, fetch: g.pick(['ok', 'ok', 'fail', 'moved'] as const),
    gate: g.next() < 0.7, mcmd: g.pick(['none', 'none', 'unreadable'] as const), review: g.next() < 0.3, execute: g.next() < 0.6, baseSame: g.next() < 0.8})
  let agree = 0, diverge: BridgeResult['diverge'] = null
  try {
    for (const q of inputs) {
      rmSync(join(root, 'gh.log'), {force: true}); rmSync(join(root, 'calls'), {force: true})
      if (q.mcmd === 'unreadable') writeFileSync(join(repo, '.kit.toml'), '[merge]\ncommand = "bin/land"\n'); else rmSync(join(repo, '.kit.toml'), {force: true})
      const args = [lib('goal/mega-merge.sh'), 'merge', '7', 'somerid', 'full']
      if (q.execute) args.push('--execute')
      if (q.review) args.push('--posture=per-pr-review')
      if (q.expect !== 'none') args.push('--expect-head', q.expect === 'match' ? head : q.expect === 'mismatch' ? 'a'.repeat(40) : 'xyz')
      const res = sh('bash', args, {env: {...env, MEGA_MERGE_GATE_LEDGER: q.gate ? env.GL_PASS : env.GL_FAIL, MEGA_MERGE_POSTURE: '',
        BR_HEADOK: q.headOk ? '1' : '0', BR_EXCL: q.excl, BR_CFG: q.cfg, BR_BASEOK: q.baseOk ? '1' : '0', BR_BASESAME: q.baseSame ? '1' : '0',
        BR_CALLS: join(root, 'calls'), BR_FETCH: q.fetch}})
      let ghlog = ''; try { ghlog = sh('cat', [join(root, 'gh.log')]).out } catch { /* none */ }
      const got = /pr merge/.test(ghlog) ? 'gh-merge' : res.code === 64 ? 'usage' : res.code === 75 ? 'head-moved'
        : res.code === 0 && /DRY-RUN/.test(res.out) ? 'dry-run' : res.code === 1 && /BLOCKED/.test(res.err + res.out) ? 'blocked' : `exit ${res.code}: ${(res.err + res.out).trim().slice(-200)}`
      const want = OUT[(f.run({...q, execOk: true, verified: true} as never) as {out: number}).out]
      if (want !== got) { diverge = {inputs: q, rule: want, bash: got, stderr: res.err.trim().split('\n').slice(-3)}; break }
      agree++
    }
  } finally { cleanup(root) }
  return {agree, diverge}
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const t0 = Date.now()
  const res = await bridge({cases: Number(process.env.CASES ?? 160), seed: Number(process.env.SEED ?? 29)})
  console.log(JSON.stringify(res, null, 1), `${Date.now() - t0}ms`)
  process.exit(res.diverge ? 1 : 0)
}
