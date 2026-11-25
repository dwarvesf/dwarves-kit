// Bridge: the real `negctl.sh <root> <test-cmd> <mutate-cmd>` on temp repos built for each fact set, compared with
// the rule's verdict. The suite (t.sh) is green while f.txt says good and no ignored state/flag exists; on failure it
// prints msg.txt (an assertion line, or a bash load-error line). The mutation edits f.txt (relevant), other.txt
// (irrelevant: a vacuous control) or nothing, plus an optional leftover: an untracked file, the ignored flag (the
// suite stays red after restore), or a new staged file (no HEAD blob: unrestorable). A dirty tree is other.txt
// modified before the run. The facts per step follow from the scenario; the verdict line and exit code are compared.
import {join} from 'node:path'
import {bash, GATE, product, rng, sandbox, sh, write, type BridgeResult} from './harness.ts'
import {negctl} from './negctl.ts'

const NC = join(GATE, 'negctl.sh')
const REASON: Record<string, string> = {notGreen: 'not green before the mutation', noChange: 'changed no tracked file',
  vacuous: 'stayed green under the mutation', loadRed: 'load or compile error', restore: '', notGreenAfter: 'not green after restore'}

export async function bridge(opts: {seed?: number, full?: boolean} = {}): Promise<BridgeResult> {
  const sb = sandbox(), rand = rng(opts.seed ?? 19), r = negctl(), it = r.interpreter()
  const all = [...product({dirty: [false, true], good: [true, false], mut: ['none', 'rel', 'irr'], left: ['none', 'untracked', 'flag', 'newTracked'],
    load: [false, true], allow: [false, true]})]
  const full = opts.full ?? process.env.BRIDGE_FULL === '1'
  const cases = full ? all : all.filter(() => rand.next() < Number(process.env.BRIDGE_FRAC ?? 0.25))
  let agree = 0
  try {
    for (const [i, c] of cases.entries()) {
      const root = join(sb.dir, `n${i}`)
      write(join(root, 'f.txt'), c.good ? 'good\n' : 'nope\n'); write(join(root, 'other.txt'), 'other\n')
      write(join(root, 'msg.txt'), c.load ? "t.sh: line 9: syntax error near unexpected token `fi'\n" : 'FAIL: f.txt is not good\n')
      write(join(root, '.gitignore'), 'state/\n')
      write(join(root, 't.sh'), '[ -e state/flag ] && { echo "FAIL: flag set"; exit 1; }\ngrep -q good f.txt && exit 0\ncat msg.txt; exit 1\n')
      sh(sb, `git init -q -b main . && git add -A && git commit -q -m init${c.dirty ? ' && echo dirt >> other.txt' : ''}`, root)
      const mut = [c.mut === 'rel' ? 'echo bad > f.txt' : c.mut === 'irr' ? 'echo changed > other.txt' : 'true',
        c.left === 'untracked' ? 'echo x > leftover.txt' : c.left === 'flag' ? 'mkdir -p state && touch state/flag' : c.left === 'newTracked' ? 'echo n > new.txt && git add new.txt' : 'true'].join(' && ')
      const real = bash(sb, [NC, root, 'bash t.sh', mut], {env: c.allow ? {NEGCTL_ALLOW_LOAD_RED: '1'} : {}})
      // the observation at each step, from the scenario
      const flag = c.left === 'flag'
      const red = flag || c.mut === 'rel' || !c.good
      const obs = [
        {ok: !c.dirty, load: false},
        {ok: c.good, load: false},
        {ok: c.mut !== 'none' || c.left === 'newTracked', load: false},
        {ok: red, load: red && !flag && c.load && !(c.mut !== 'rel' && c.good)},
        {ok: c.left !== 'untracked' && c.left !== 'newTracked', load: false},
        {ok: c.good && !flag, load: false},
      ]
      let st = it.init({allowLoad: +c.allow} as any)
      for (const o of obs) st = it.step({allowLoad: +c.allow} as any, st, r.encodeInput(o as any))
      const v = (r.decode(st) as any).verdict as string
      const vline = (real.out.match(/^Verdict: (.*)$/m) ?? [])[1] ?? ''
      const ok = v === 'refused' ? real.code === 2
        : v === 'pass' ? real.code === 0 && vline === 'PASS'
          : real.code === 1 && vline.startsWith('FAIL') && (v !== 'restore' ? vline.includes(REASON[v]) : /tree differs|cannot be restored/.test(vline))
      if (!ok) return {agree, diverge: {facts: c, mutate: mut, model: v, bash: {code: real.code, verdict: vline, err: real.err.trim().slice(0, 300)}}}
      agree++
    }
  } finally { sb.done() }
  return {agree, diverge: null}
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
