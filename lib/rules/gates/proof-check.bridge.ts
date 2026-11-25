// Bridge: build the real situation for each fact set and run the real `proof-ledger.sh check`.
// One temp repo per (class, source-or-not, negative control owed) with a base commit and a branch commit touching
// one path of that class; the fresh proof file docs/verification/proof.md is written in the working tree from the
// file facts (each marker on its own line), and the override is logged with the real `proof-ledger.sh override`
// for slug `ov` (never for slug `plain`). The relevant facts of each class are enumerated; the rest are seeded random.
import {join} from 'node:path'
import {rmSync} from 'node:fs'
import {bash, GATE, gitRepo, product, rng, sandbox, sh, write, type BridgeResult} from './harness.ts'
import {proofCheck} from './proof-check.ts'

const PL = join(GATE, 'proof-ledger.sh')
const REPOS = [
  {cls: 'behavioral', src: true, path: 'src/app.sh', negReq: true}, {cls: 'behavioral', src: true, path: 'src/app.sh', negReq: false},
  {cls: 'behavioral', src: false, path: 'config/app.yaml', negReq: true}, {cls: 'behavioral', src: false, path: 'config/app.yaml', negReq: false},
  {cls: 'stateful', src: true, path: 'db/migrations/001.sql', negReq: true}, {cls: 'stateful', src: false, path: 'deploy/rollout.yaml', negReq: true},
  {cls: 'inert', src: false, path: 'notes.md', negReq: true},
] as const

type Facts = {proof: boolean, out: boolean, green: boolean, negctl: boolean, lastBad: boolean, rollback: boolean, unavail: boolean, cmd: boolean}
export function proofText(f: Facts): string {
  return ['# Proof of done', '',
    ...(f.cmd ? ['- Command: bash run.sh'] : []),
    ...(f.green ? ['| run | PASS |'] : []),
    ...(f.out ? ['Output: 12 tests passed'] : []),
    '',
    ...(f.negctl ? ['NEGATIVE CONTROL: revert, then RED, then restore'] : []),
    ...(f.rollback ? ['Rollback: revert the change'] : []),
    ...(f.unavail ? ['[UNAVAILABLE: no staging database here]'] : []),
    ...(f.lastBad ? ['Verdict: FAIL'] : []), ''].join('\n')
}

export async function bridge(opts: {seed?: number} = {}): Promise<BridgeResult> {
  const f = proofCheck(), sb = sandbox(), rand = rng(opts.seed ?? 5)
  let agree = 0
  try {
    for (const [ri, rp] of REPOS.entries()) {
      const root = gitRepo(sb, `repo${ri}`)
      if (!rp.negReq) sh(sb, `printf '[gate]\\nnegative_control = "full"\\n' > .kit.toml && git add -A && git commit -qm config`, root)
      const base = sh(sb, 'git rev-parse HEAD', root).out.trim()
      sh(sb, `git switch -qc feat/x && mkdir -p ${rp.path.includes('/') ? rp.path.replace(/\/[^/]*$/, '') : '.'} && echo change > ${rp.path} && git add -A && git commit -qm 'feat: change'`, root)
      bash(sb, [PL, 'override', 'ov', 'bridge override'], {cwd: root})
      const rel = rp.cls === 'behavioral' ? ['out', 'green', 'negctl', 'lastBad'] : rp.cls === 'stateful' ? ['out', 'rollback', 'unavail', 'cmd', 'lastBad'] : []
      const doms: Record<string, readonly boolean[]> = {}
      for (const k of rel) doms[k] = [false, true]
      const cases: (Facts & {slug: string, reachable: boolean})[] = []
      for (const c of product(doms)) for (const slug of ['ov', 'plain']) {
        const rnd = () => rand.next() < 0.5
        const g = {out: rnd(), green: rnd(), negctl: rnd(), lastBad: rnd(), rollback: rnd(), unavail: rnd(), cmd: rnd(), ...c} as any
        cases.push({proof: true, ...g, slug, reachable: true})
      }
      for (const slug of ['ov', 'plain']) cases.push({proof: false, out: false, green: false, negctl: false, lastBad: false, rollback: false, unavail: false, cmd: false, slug, reachable: true})
      cases.push({proof: true, out: false, green: false, negctl: false, lastBad: true, rollback: false, unavail: false, cmd: false, slug: 'plain', reachable: false})
      const proofPath = join(root, 'docs/verification/proof.md')
      for (const c of cases) {
        if (c.proof) write(proofPath, proofText(c)); else rmSync(proofPath, {force: true})
        const real = bash(sb, [PL, 'check', root, c.reachable ? base : 'no-such-rev', c.slug], {cwd: root})
        const facts = {reachable: c.reachable, cls: rp.cls, negReq: rp.negReq, proof: c.proof, out: c.out, green: c.green, negctl: c.negctl,
          lastBad: c.lastBad, rollback: c.rollback, unavail: c.unavail, cmd: c.cmd, overridden: c.slug === 'ov', src: rp.src}
        const want = f.run(facts as any).pass
        if ((real.code === 0) !== want) return {agree, diverge: {facts, path: rp.path, proof: c.proof ? proofText(c) : null, model: want ? 'pass' : 'block', bash: {code: real.code, err: real.err.trim().slice(0, 600)}}}
        agree++
      }
    }
  } finally { sb.done() }
  return {agree, diverge: null}
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
