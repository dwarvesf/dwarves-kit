// Bridge: a temp repo with four tagged bases (a full [test] config, no failure_line, no count_line, a known-failures
// path outside the repo), seeded random run logs and flags through the real `known-failures.sh classify`, compared
// with the decision (stdout verdict and exit code).
import {join} from 'node:path'
import {bash, GATE, gitRepo, q, rng, sandbox, sh, write, type BridgeResult} from './harness.ts'
import {knownFailures} from './known-failures.ts'

const KF = join(GATE, 'known-failures.sh')
const FAIL = `failure_line = '^FAIL: ([a-z]+)$'`, COUNT = `count_line = '^ran ([0-9]+) tests'`
const BASES = {full: [FAIL, COUNT], nofail: [COUNT], nocount: [FAIL], badpath: [FAIL, COUNT, `known_failures = '../outside.txt'`]} as const

export async function bridge(opts: {n?: number, seed?: number} = {}): Promise<BridgeResult> {
  const sb = sandbox(), rand = rng(opts.seed ?? 13), f = knownFailures()
  const n = opts.n ?? Number(process.env.BRIDGE_N ?? 120)
  let agree = 0
  try {
    const root = gitRepo(sb, 'kf')
    for (const [tag, lines] of Object.entries(BASES)) {
      write(join(root, '.kit.toml'), `[test]\n${lines.join('\n')}\n`)
      write(join(root, 'tests/known-failures.txt'), '# known\nalpha\nbeta\n')
      sh(sb, `git add -A && git commit -q --allow-empty -m ${tag} && git tag ${tag}`, root)
    }
    for (let i = 0; i < n; i++) {
      const base = rand.pick(Object.keys(BASES)), names = rand.pick(['none', 'known', 'new'] as const)
      const count = rand.pick([null, 0, 5, 10]), exit = rand.pick(['zero', 'nonzero', 'absent', 'garbage'] as const)
      const prev = rand.pick([null, '5', '20', 'x']), bcount = rand.pick([null, '5', '20', 'x']), logExists = rand.next() < 0.93
      const log = join(sb.dir, `run${i}.log`)
      if (logExists) write(log, [...(names === 'none' ? [] : ['FAIL: alpha']), ...(names === 'new' ? ['FAIL: gamma'] : []),
        'some output', ...(count === null ? [] : [`ran ${count} tests`])].join('\n') + '\n')
      const args = [KF, 'classify', log, root, base,
        ...(exit === 'zero' ? ['--exit', '0'] : exit === 'nonzero' ? ['--exit', '3'] : exit === 'garbage' ? ['--exit', 'abc'] : []),
        ...(prev ? ['--prev-count', prev] : []), ...(bcount ? ['--base-count', bcount] : [])]
      const real = bash(sb, args, {cwd: root})
      const cfg = BASES[base as keyof typeof BASES] as readonly string[]
      const facts = {log: logExists, exit, failLine: cfg.includes(FAIL), names, listOk: base !== 'badpath', countLine: cfg.includes(COUNT),
        count: count ?? 0, prevSet: prev !== null && prev !== 'x', prev: prev && prev !== 'x' ? Number(prev) : 0,
        baseSet: bcount !== null, baseOk: bcount !== null && bcount !== 'x', base: bcount && bcount !== 'x' ? Number(bcount) : 0}
      const o = f.run(facts as any)
      const want = o.pass ? 'pass' : o.known ? 'known' : 'fail'
      const got = real.out.trim()
      if (got !== want || (real.code === 0) !== (want !== 'fail'))
        return {agree, diverge: {facts, args: args.slice(1).map(a => q(a)).join(' '), model: want, bash: {code: real.code, out: got, err: real.err.trim()}}}
      agree++
    }
  } finally { sb.done() }
  return {agree, diverge: null}
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
