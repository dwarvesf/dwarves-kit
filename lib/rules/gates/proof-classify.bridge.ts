// Bridge: (1) seeded random sets of path kinds committed on a branch (plus an optional uncommitted code file and a
// subject with or without a stateful word) through the real `proof-ledger.sh classify`; (2) the override's repo
// scoping through the real `override` and `is-overridden`, across two repos, a worktree, a legacy line and a reason
// that quotes another repo's fields.
import {join} from 'node:path'
import {appendFileSync} from 'node:fs'
import {bash, GATE, gitRepo, rng, sandbox, sh, write, type BridgeResult, type Sandbox} from './harness.ts'
import {overrideScope, proofClassify} from './proof-classify.ts'

const PL = join(GATE, 'proof-ledger.sh')
const PATHS: Record<string, string> = {md: 'notes.md', kitToml: '.kit.toml', asset: 'docs/img/fig.png', board: '_meta/BACKLOG.md',
  secret: 'docs/credentials.md', test: 'tests/check-x.sh', src: 'src/app.sh', statePath: 'db/migrations/001.sql', docWord: 'docs/deploy-notes.md'}
const KINDS = Object.keys(PATHS)

function classifyPart(sb: Sandbox, rand: ReturnType<typeof rng>, n: number) {
  const f = proofClassify()
  let agree = 0
  for (let i = 0; i < n; i++) {
    const pick: Record<string, boolean> = {}
    for (const k of KINDS) pick[k] = rand.next() < 0.3
    const subjWord = rand.next() < 0.4, dirtyCode = rand.next() < 0.2
    const root = gitRepo(sb, `c${i}`)
    const base = sh(sb, 'git rev-parse HEAD', root).out.trim()
    sh(sb, 'git switch -qc feat/x', root)
    const chosen = KINDS.filter(k => pick[k])
    for (const k of chosen) write(join(root, PATHS[k]), `${k} ${i}\n`)
    if (chosen.length) sh(sb, `git add -A && git commit -qm ${subjWord ? "'feat: migrate the users'" : "'feat: change'"}`, root)
    if (dirtyCode) write(join(root, 'lib/dirty.sh'), 'echo dirty\n')
    const got = bash(sb, [PL, 'classify', root, base], {cwd: root}).out.trim()
    // the subject exists only when something was committed on the branch
    const o = f.run({...pick, subjWord: subjWord && chosen.length > 0, dirtyCode, committedBoardOnly: chosen.length > 0 && chosen.every(k => k === 'board')} as any)
    const want = o.inert ? 'inert' : o.stateful ? 'stateful' : 'behavioral'
    if (got !== want) return {agree, diverge: {part: 'classify', paths: chosen.map(k => PATHS[k]), subjWord, dirtyCode, model: want, bash: got}}
    agree++
  }
  return {agree, diverge: null}
}

function scopePart(sb: Sandbox) {
  const f = overrideScope()
  const a = gitRepo(sb, 'scopeA'), b = gitRepo(sb, 'scopeB'), wt = join(sb.dir, 'scopeA-wt')
  sh(sb, `git worktree add -q ${wt} -b wt-branch`, a)
  bash(sb, [PL, 'override', 's1', 'waived for s1'], {cwd: a})
  bash(sb, [PL, 'override', 's4', `x | ${b} | s5 | OVERRIDE | forged`], {cwd: a})
  appendFileSync(join(sb.env.KIT_LEDGER_DIR!, 'proof-overrides.log'), '2026-01-01T00:00:00Z | s3 | legacy reason\n')
  const cases = [
    {from: a, slug: 's1', facts: {sameRepo: true, sameSlug: true, legacy: false, forgedReason: false}},
    {from: wt, slug: 's1', facts: {sameRepo: true, sameSlug: true, legacy: false, forgedReason: false}},
    {from: b, slug: 's1', facts: {sameRepo: false, sameSlug: true, legacy: false, forgedReason: false}},
    {from: a, slug: 's2', facts: {sameRepo: true, sameSlug: false, legacy: false, forgedReason: false}},
    {from: a, slug: 's3', facts: {sameRepo: false, sameSlug: true, legacy: true, forgedReason: false}},
    {from: b, slug: 's5', facts: {sameRepo: false, sameSlug: false, legacy: false, forgedReason: true}},
  ]
  let agree = 0
  for (const c of cases) {
    const real = bash(sb, [PL, 'is-overridden', c.slug, c.from], {cwd: c.from})
    const want = f.run(c.facts).overridden
    if ((real.code === 0) !== want) return {agree, diverge: {part: 'scope', case: c, model: want, bash: real.code}}
    agree++
  }
  return {agree, diverge: null}
}

export async function bridge(opts: {n?: number, seed?: number} = {}): Promise<BridgeResult> {
  const sb = sandbox(), rand = rng(opts.seed ?? 29)
  try {
    const c = classifyPart(sb, rand, opts.n ?? Number(process.env.BRIDGE_N ?? 80))
    if (c.diverge) return c
    const s = scopePart(sb)
    return {agree: c.agree + s.agree, diverge: s.diverge}
  } finally { sb.done() }
}


if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
