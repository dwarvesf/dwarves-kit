// Bridge: (1) ship_rule_large_spec, sourced from the real ship-rules.sh, over every (lane, spec size, latest
// validate state) with the real spec.sh sizing a 1-task, a 0-task and a 4-task spec; (2) ship_rule_floor on temp
// repos over (merge base known, lane_gates false committed at the base, false committed only on the branch, head
// moved, a hard-path hit, the full lane's gates recorded, a ledger script present), compared with the decisions.
import {join} from 'node:path'
import {bash, GATE, gitRepo, product, q, rng, sandbox, sh, write, type BridgeResult, type Sandbox} from './harness.ts'
import {floor, largeSpec, VSTATES} from './ship-rules.ts'

const RULES = join(GATE, 'ship-rules.sh'), LEDGER = join(GATE, 'gate-ledger.sh')
const SPEC: Record<string, string> = {small: '# Spec\nLane: normal\n\n- [ ] TASK-1: a\n', large: '# Spec\nLane: normal\n\nno tasks here\n',
  large4: '# Spec\nLane: normal\n\n- [ ] TASK-1: a\n- [ ] TASK-2: b\n- [ ] TASK-3: c\n- [ ] TASK-4: d\n'}

function largePart(sb: Sandbox) {
  const f = largeSpec()
  for (const [k, t] of Object.entries(SPEC)) write(join(sb.dir, `spec-${k}.md`), t)
  let agree = 0, i = 0
  for (const c of product({lane: ['normal', 'full'], size: ['small', 'large', 'large4', 'unreadable'], validate: VSTATES})) {
    const rid = `ls-${i++}`
    if (c.validate !== 'none') {
      bash(sb, [LEDGER, 'record', rid, 'validate', c.validate === 'ran' ? 'skipped' : 'ran', 'an earlier row'])
      if (c.validate === 'override') bash(sb, [LEDGER, 'override', rid, 'validate', `waived ${rid}`])
      else bash(sb, [LEDGER, 'record', rid, 'validate', c.validate, 'the latest row'])
    }
    const spec = c.size === 'unreadable' ? join(sb.dir, 'missing.md') : join(sb.dir, `spec-${c.size}.md`)
    const real = bash(sb, ['-c', `source ${q(RULES)}; ship_rule_large_spec ${q(spec)} ${rid} ${c.lane} ${q(LEDGER)} 2>/dev/null; echo $?`])
    const o = f.run({normal: c.lane === 'normal', specSh: true, size: c.size === 'large4' ? 'large' : c.size as any, validate: c.validate})
    if ((real.out.trim() === '2') !== o.block) return {agree, diverge: {part: 'large-spec', case: c, model: o.block ? 'block' : 'pass', bash: real.out.trim()}}
    agree++
  }
  return {agree, diverge: null}
}

function floorPart(sb: Sandbox, rand: ReturnType<typeof rng>, frac: number) {
  const f = floor()
  const op = join(sb.dir, 'op-floor'); write(join(op, 'kit.toml'), '[gate]\nlane_gates = true\n')
  let agree = 0, i = 0
  for (const c of product({base: [true, false], offAtBase: [false, true], offAtHead: [false, true], moved: [true, false], hit: [true, false], fullGates: [false, true], ledger: [true, false]})) {
    if (rand.next() > frac) continue
    const slug = `fl${i}`, root = gitRepo(sb, `floor${i++}`)
    if (c.offAtBase) sh(sb, `printf '[gate]\\nlane_gates = false\\n' > .kit.toml && git add -A && git commit -qm off && git push -q origin main`, root)
    const base = sh(sb, 'git rev-parse HEAD', root).out.trim()
    sh(sb, `git switch -qc feat/${slug} && mkdir -p src && echo x > src/a.sh && git add -A && git commit -qm feat`, root)
    if (c.hit) sh(sb, "mkdir -p .github/workflows && printf 'name: ci\\non: push\\njobs:\\n  t:\\n    runs-on: ${{ matrix.os }}\\n' > .github/workflows/ci.yml && git add -A && git commit -qm ci", root)
    if (c.offAtHead) sh(sb, `printf '[gate]\\nlane_gates = false\\n' > .kit.toml && git add -A && git commit -qm head-off`, root)
    if (c.fullGates) for (const g of bash(sb, [LEDGER, 'required', 'full']).out.trim().split('\n')) bash(sb, [LEDGER, 'record', slug, g, 'ran', 'ok'])
    const head = c.moved ? sh(sb, 'git rev-parse HEAD', root).out.trim() : base
    const ledger = c.ledger ? LEDGER : join(sb.dir, 'no-ledger.sh')
    const real = bash(sb, ['-c', `source ${q(RULES)}; ship_rule_floor ${q(root)} ${c.base ? base : "''"} ${head} ${slug} '' ${q(ledger)} 2>/dev/null; echo $?`],
      {cwd: root, env: {KIT_CONFIG_OPERATOR: op}})
    // .kit.toml is itself a hard path (kit-config): a head-only switch-off commit is a hit of its own
    const o = f.run({...c, hit: c.hit || c.offAtHead, classifier: true})
    if ((real.out.trim() === '2') !== o.block) return {agree, diverge: {part: 'floor', case: c, model: o.block ? 'block' : 'pass', bash: real.out.trim()}}
    agree++
  }
  return {agree, diverge: null}
}

export async function bridge(opts: {seed?: number, frac?: number} = {}): Promise<BridgeResult> {
  const sb = sandbox(), rand = rng(opts.seed ?? 37)
  try {
    const a = largePart(sb)
    if (a.diverge) return a
    const b = floorPart(sb, rand, opts.frac ?? Number(process.env.BRIDGE_FRAC ?? 0.3))
    return {agree: a.agree + b.agree, diverge: b.diverge}
  } finally { sb.done() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
