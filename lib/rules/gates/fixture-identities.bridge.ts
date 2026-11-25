// Bridge: (1) every shape, in several spellings, through the real _sr_fixture_email; (2) seeded random commit
// sequences (author, committer, Co-authored-by per commit) committed in a temp repo and judged by the real
// ship_rule_identities, under every (origin, switch, range) setting, compared with the fold and its decision.
import {join} from 'node:path'
import {bash, GATE, gitRepo, q, rng, sandbox, sh, write, type BridgeResult} from './harness.ts'
import {blockDecision, fixtureEmail, identities, SHAPES} from './fixture-identities.ts'

const RULES = join(GATE, 'ship-rules.sh')
export const SPELL: Record<string, string[]> = {
  empty: [''], noAt: ['jane', 'Builder'], bareHost: ['x@x', 'user@Host', 'a@localhost'], tdev: ['t@t.dev', 'T@T.DEV'],
  testExample: ['test@example.com', 'TEST@Example.com'], exampleDom: ['a@example.org', 'b@EXAMPLE.net', 'c@example.com'],
  reservedTld: ['a@b.test', 'c@d.invalid', 'u@mac.local', 'x@y.localhost', 'q@z.example'],
  real: ['jane@dwarves.foundation', 'han@d.foundation'], noreply: ['123+jane@users.noreply.github.com', '41898282+github-actions[bot]@users.noreply.github.com'],
}

export async function bridge(opts: {n?: number, seed?: number} = {}): Promise<BridgeResult> {
  const sb = sandbox(), rand = rng(opts.seed ?? 3), f = fixtureEmail()
  let agree = 0
  try {
    const emails = SHAPES.flatMap(s => SPELL[s].map(e => ({s, e})))
    const out = bash(sb, ['-c', `source ${q(RULES)}\n` + emails.map(x => `_sr_fixture_email ${q(x.e)} && echo 1 || echo 0`).join('\n')]).out.trim().split('\n')
    for (let i = 0; i < emails.length; i++) {
      const want = f.run({e: emails[i].s}).fixture
      if ((out[i] === '1') !== want) return {agree, diverge: {part: 'email', email: emails[i].e, shape: emails[i].s, model: want, bash: out[i]}}
      agree++
    }
    const off = join(sb.dir, 'op-off'); write(join(off, 'kit.toml'), '[gate]\nfixture_identities = false\n')
    const r = identities(), it = r.interpreter()
    const commitShapes = SHAPES.filter(s => s !== 'empty')
    const n = opts.n ?? Number(process.env.BRIDGE_N ?? 30)
    for (let k = 0; k < n; k++) {
      const origin = rand.next() < 0.85, on = rand.next() < 0.8, ranged = rand.next() < 0.85
      const root = gitRepo(sb, `id${k}`)
      if (!origin) sh(sb, 'git remote remove origin', root)
      const base = sh(sb, 'git rev-parse HEAD', root).out.trim()
      const commits = Array.from({length: 1 + rand.int(3)}, () => ({author: rand.pick(commitShapes), committer: rand.pick(commitShapes), coauthor: rand.pick(SHAPES)}))
      let st = it.init({origin: +origin, on: +on, ranged: +ranged} as any)
      for (const [i, c] of commits.entries()) {
        const co = c.coauthor === 'empty' ? '' : `\n\nCo-authored-by: Pair <${rand.pick(SPELL[c.coauthor])}>`
        const res = sh(sb, `echo ${i} >> f.txt && git add -A && git commit -q -m ${q(`change ${i}${co}`)}`, root,
          {GIT_AUTHOR_EMAIL: rand.pick(SPELL[c.author]), GIT_COMMITTER_EMAIL: rand.pick(SPELL[c.committer])})
        if (res.code !== 0) throw new Error(res.err)
        st = it.step({origin: +origin, on: +on, ranged: +ranged} as any, st, r.encodeInput(c as any))
      }
      const head = ranged ? sh(sb, 'git rev-parse HEAD', root).out.trim() : base
      const real = bash(sb, ['-c', `source ${q(RULES)}; ship_rule_identities ${q(root)} ${q(base)} ${q(head)}; echo $?`],
        {env: on ? {} : {KIT_CONFIG_OPERATOR: off}})
      const d = r.decode(st) as any
      const block = blockDecision.run({origin, on, ranged, bad: !!d.bad}).block
      if ((real.out.trim().split('\n').pop() === '2') !== block)
        return {agree, diverge: {part: 'fold', origin, on, ranged, commits, model: block ? 'block' : 'pass', bash: real.out.trim(), err: real.err.trim()}}
      agree++
    }
  } finally { sb.done() }
  return {agree, diverge: null}
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
