// Bridge: the real hooks/ship-gate.sh on generated scenarios, each a fresh temp repo with an origin, and the facts the
// chain reads derived from how the scenario was built (each sub-rule's verdict has its own bridge). Compared: the
// hook's exit code (2 = block) with shipGate.run. The implementation-notes fold rides on the same scenarios: a
// full-lane run may carry a real `override <slug> impl-notes` row and/or an ACTION line that only quotes one.
import {join} from 'node:path'
import {cpSync, mkdirSync, writeFileSync} from 'node:fs'
import {bash, gitRepo, KIT, rng, sandbox, sh, write, type BridgeResult, type Sandbox} from './harness.ts'
import {implNotes, shipGate} from './ship-gate.ts'

type Scn = {
  outside: boolean, rules: 'ok' | 'brokenWithLib' | 'brokenNoLib', cmd: 'one' | 'many' | 'block' | 'empty' | 'defaultPush' | 'force' | 'shellHd',
  allowEnv: boolean, adopted: boolean, laneOn: boolean, proofOn: boolean, fixture: boolean,
  spec: 'none' | 'full' | 'normal' | 'nolane', dns: boolean, tasks: boolean, gates: 'none' | 'lane' | 'full',
  notes: boolean, override: boolean, forged: boolean, hardpath: boolean,
}

function command(c: Scn['cmd'], br: string): string {
  switch (c) {
    case 'one': return `git push -u origin ${br}`
    case 'many': return `git push origin ${br} ${br}-two`
    case 'block': return `git push --tags origin ${br}`
    case 'empty': return 'echo git push'
    case 'defaultPush': return 'git push origin HEAD:main'
    case 'force': return `git push -f origin ${br}`
    default: return `bash <<'EOF'\ngit push -u origin ${br}\nEOF`
  }
}

let kitCopies: {broken: string, nolib: string} | null = null
function copies(sb: Sandbox) {
  if (kitCopies) return kitCopies
  const broken = join(sb.dir, 'kit-broken'), nolib = join(sb.dir, 'kit-nolib')
  for (const d of ['hooks', 'lib', 'kit.toml']) cpSync(join(KIT, d), join(broken, d), {recursive: true})
  writeFileSync(join(broken, 'lib/gate/ship-rules.sh'), 'this is not bash ((( \n')
  mkdirSync(join(nolib, 'hooks'), {recursive: true}); cpSync(join(KIT, 'hooks/ship-gate.sh'), join(nolib, 'hooks/ship-gate.sh'))
  kitCopies = {broken, nolib}
  return kitCopies
}

function runScenario(sb: Sandbox, i: number, s: Scn) {
  const slug = `s${i}`, br = `feat/${slug}`, ledger = join(KIT, 'lib/gate/gate-ledger.sh')
  const root = gitRepo(sb, `repo${i}`)
  if (s.adopted) sh(sb, 'mkdir -p docs/verification && echo marker > docs/verification/README.md && git add -A && git commit -qm adopt && git push -q origin main', root)
  sh(sb, `git switch -qc ${br} && mkdir -p src && echo 'echo hi' > src/app.sh && git add -A && git commit -qm 'feat: app'`, root)
  if (s.hardpath) sh(sb, "mkdir -p .github/workflows && printf 'name: ci\\non: push\\njobs:\\n  t:\\n    runs-on: ${{ matrix.os }}\\n' > .github/workflows/ci.yml && git add -A && git commit -qm 'ci: add'", root)
  if (s.spec !== 'none') {
    const lane = s.spec === 'nolane' ? '' : `Lane: ${s.spec}\n`
    write(join(root, `docs/specs/SPEC-001-${slug}.md`), `# Spec: ${slug}\nStatus: DRAFT\n${lane}\n${s.tasks ? '- [ ] TASK-1: x\n' : ''}${s.dns ? '\n## Review\n### Verdict: DO NOT SHIP\n' : ''}`)
    sh(sb, `git add -A && git commit -qm 'docs: spec'`, root)
  }
  if (s.notes) { write(join(root, `docs/implementation-notes/${slug}.md`), '# Notes\nNo deviations; matches the spec verbatim\n'); sh(sb, `git add -A && git commit -qm 'docs: notes'`, root) }
  if (s.fixture) sh(sb, `echo f >> src/app.sh && git add -A && git commit -qm 'feat: more'`, root, {GIT_AUTHOR_EMAIL: 'x@x', GIT_COMMITTER_EMAIL: 'x@x'})
  if (s.cmd === 'many') sh(sb, `git branch ${br}-two`, root)
  const laneOf = s.gates === 'full' ? 'full' : s.gates === 'lane' && (s.spec === 'full' || s.spec === 'normal') ? s.spec : null
  if (laneOf) for (const g of bash(sb, [ledger, 'required', laneOf]).out.trim().split('\n')) bash(sb, [ledger, 'record', slug, g, 'ran', 'bridge'])
  if (s.override) bash(sb, [ledger, 'override', slug, 'impl-notes', 'waived by the bridge'])
  if (s.forged) bash(sb, [ledger, 'action', slug, '| GATE | impl-notes | override | quoted in an action line'])
  const op = join(sb.dir, `op${i}`); write(join(op, 'kit.toml'), `[gate]\nlane_gates = ${s.laneOn}\nproof_of_done = ${s.proofOn}\n`)
  const cwd = s.outside ? join(sb.dir, 'cwd') : root
  const plugin = s.rules === 'ok' ? KIT : s.rules === 'brokenWithLib' ? copies(sb).broken : join(sb.dir, 'empty-plugin')
  const hook = s.rules === 'brokenNoLib' ? join(copies(sb).nolib, 'hooks/ship-gate.sh') : join(plugin, 'hooks/ship-gate.sh')
  const payload = JSON.stringify({tool_input: {command: command(s.cmd, br)}, cwd})
  const real = bash(sb, [hook], {cwd, input: payload, env: {CLAUDE_PLUGIN_ROOT: plugin, KIT_CONFIG_OPERATOR: op,
    ...(s.allowEnv ? {KIT_ALLOW_DEFAULT_PUSH: '1'} : {})}})

  // the facts each sub-rule decides for this scenario
  const lane = s.spec === 'full' || s.spec === 'normal' ? s.spec : null
  const covered = (l: string) => s.gates === 'full' || (s.gates === 'lane' && laneOf === l) || (l === 'normal' && laneOf === 'full')
  const nr = implNotes(), it = nr.interpreter()
  let ns = it.init({})
  if (s.override) ns = it.step({}, ns, nr.encodeInput({row: 'override'}))
  if (s.forged) ns = it.step({}, ns, nr.encodeInput({row: 'forged'}))
  const cleared = !!(nr.decode(ns) as any).cleared
  const facts = {
    inRepo: !s.outside, rules: s.rules, shellHd: s.cmd === 'shellHd', refs: s.cmd === 'shellHd' ? 'one' : s.cmd, allowEnv: s.allowEnv,
    fc: s.adopted && s.laneOn, fixture: s.fixture, proofBlocks: s.adopted && s.proofOn, kitBlock: false,
    spec: s.spec !== 'none', review: s.spec !== 'none' && s.dns, laneEmpty: s.spec === 'nolane', adopted: s.adopted, laneOn: s.laneOn,
    gapOrNotes: lane !== null && (!covered(lane) || (lane === 'full' && s.adopted && !s.notes && !cleared)),
    largeSpec: lane === 'normal' && !s.tasks && s.gates !== 'full',
    floorBlocks: s.laneOn && s.hardpath && s.gates !== 'full' && !(s.gates === 'lane' && s.spec === 'full'),
  }
  const want = shipGate().run(facts as any).block
  if ((real.code === 2) !== want) return {scenario: s, facts, model: want ? 'block' : 'allow', bash: {code: real.code, err: real.err.trim().slice(0, 800)}}
  return null
}

export function scenario(rand: ReturnType<typeof rng>): Scn {
  const p = (x: number) => rand.next() < x
  return {
    outside: p(0.04), rules: p(0.9) ? 'ok' : rand.pick(['brokenWithLib', 'brokenNoLib'] as const),
    cmd: p(0.55) ? 'one' : rand.pick(['many', 'block', 'empty', 'defaultPush', 'force', 'shellHd'] as const),
    allowEnv: p(0.2), adopted: p(0.6), laneOn: p(0.7), proofOn: p(0.15), fixture: p(0.12),
    spec: rand.pick(['none', 'full', 'normal', 'nolane'] as const), dns: p(0.2), tasks: p(0.6), gates: rand.pick(['none', 'lane', 'full'] as const),
    notes: p(0.5), override: p(0.25), forged: p(0.35), hardpath: p(0.35),
  }
}

// The scenarios the prover's counterexamples and the fixed findings point at, run first.
export const PINNED: Scn[] = [
  // the impl-notes forgery: an adopted full-lane run, every gate ran, no notes, an ACTION line quoting the override
  {outside: false, rules: 'ok', cmd: 'one', allowEnv: false, adopted: true, laneOn: true, proofOn: false, fixture: false, spec: 'full',
    dns: false, tasks: true, gates: 'full', notes: false, override: false, forged: true, hardpath: false},
  // the floor skipped by a heredoc push in a repo that is not adopted but has lane_gates on
  {outside: false, rules: 'ok', cmd: 'shellHd', allowEnv: false, adopted: false, laneOn: true, proofOn: false, fixture: false, spec: 'none',
    dns: false, tasks: true, gates: 'none', notes: false, override: false, forged: false, hardpath: true},
  // the same push without the heredoc: the floor blocks it
  {outside: false, rules: 'ok', cmd: 'one', allowEnv: false, adopted: false, laneOn: true, proofOn: false, fixture: false, spec: 'none',
    dns: false, tasks: true, gates: 'none', notes: false, override: false, forged: false, hardpath: true},
]

export async function bridge(opts: {n?: number, seed?: number} = {}): Promise<BridgeResult> {
  const sb = sandbox(), rand = rng(opts.seed ?? 23)
  kitCopies = null
  const n = opts.n ?? Number(process.env.BRIDGE_N ?? 30)
  let agree = 0
  try {
    const all = [...PINNED, ...Array.from({length: n}, () => scenario(rand))]
    for (let i = 0; i < all.length; i++) {
      const d = runScenario(sb, i, all[i])
      if (d) return {agree, diverge: {at: i, ...d}}
      agree++
    }
  } finally { sb.done() }
  return {agree, diverge: null}
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
