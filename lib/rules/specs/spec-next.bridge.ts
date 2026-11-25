// Bridge: a temp git repo per run, the reservation ledger and the log dir in temp dirs, the PR scan off. Each step
// runs the real lib/spec/spec-next.sh (`reserve`, `next`), or makes a spec file SPEC-<k> appear in the worktree
// (realize), or ages every ledger line past the TTL (expire); every printed number is compared with the rule's.
import {existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {OPS, specNext} from './spec-next.ts'
import {KIT, run, seeded, tmp, type BridgeResult} from './util.ts'

const SH = join(KIT, 'lib/spec/spec-next.sh')

function repo(dir: string) {
  mkdirSync(join(dir, 'docs/specs'), {recursive: true})
  const g = (...a: string[]) => run(['git', '-C', dir, '-c', 'user.email=t@t', '-c', 'user.name=t', '-c', 'commit.gpgsign=false', ...a])
  g('init', '-q', '-b', 'main'); writeFileSync(join(dir, 'README.md'), 'x\n'); g('add', '.'); g('commit', '-q', '-m', 'init')
}

export async function bridge(): Promise<BridgeResult> {
  const r = specNext()
  const step = r.compiled().step
  const t = tmp('spec-next')
  let agree = 0
  try {
    const rand = seeded(64)
    for (let i = 0; i < 30; i++) {
      const dir = join(t.dir, `r${i}`), res = join(t.dir, `res${i}.log`)
      repo(dir)
      const env = {SPEC_RESERVE_FILE: res, KIT_LEDGER_DIR: join(t.dir, 'ledger'), SPEC_NEXT_NO_PR_SCAN: '1', HOME: t.dir, GIT_CONFIG_GLOBAL: '/dev/null'}
      let st: any = r.compiled().init({})
      const trail: string[] = []
      for (let j = 0; j < 3 + rand(5); j++) {
        const op = OPS[rand(10) < 4 ? 0 : 1 + rand(3)]
        const m0 = r.decode(st) as {scan: number, res: number}
        const k = Math.max(1, Math.max(m0.scan, m0.res) + rand(4) - 1)
        st = step({}, st, r.encodeInput({op, k}))
        const m = r.decode(st) as {out: number}
        let out = 0
        if (op === 'reserve' || op === 'next') {
          const x = run(['bash', SH, op], {cwd: dir, env})
          if (x.code !== 0) return {agree, diverge: {trail, op, exit: x.code, stderr: x.err}}
          out = parseInt(x.out.trim(), 10)
        } else if (op === 'realize') {
          writeFileSync(join(dir, 'docs/specs', `SPEC-${String(k).padStart(3, '0')}-x.md`), '# x\n')
        } else if (existsSync(res)) {
          writeFileSync(res, readFileSync(res, 'utf8').replace(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ/gm, '2000-01-01T00:00:00Z'))
        }
        trail.push(op === 'realize' ? `realize ${k}` : op)
        if (out !== m.out) return {agree, diverge: {trail, bash: out, rule: m.out}}
        agree++
      }
    }
    return {agree, diverge: null}
  } finally { t.done() }
}

// The by-design refutation on the real bash: reserve, age the line past the TTL, reserve again: the same number.
export async function confirm() {
  const t = tmp('spec-next-cx')
  try {
    const dir = join(t.dir, 'r'), res = join(t.dir, 'res.log'); repo(dir)
    const env = {SPEC_RESERVE_FILE: res, KIT_LEDGER_DIR: join(t.dir, 'ledger'), SPEC_NEXT_NO_PR_SCAN: '1', HOME: t.dir, GIT_CONFIG_GLOBAL: '/dev/null'}
    const a = run(['bash', SH, 'reserve'], {cwd: dir, env}).out.trim()
    writeFileSync(res, readFileSync(res, 'utf8').replace(/^\S+/gm, '2000-01-01T00:00:00Z'))
    const b = run(['bash', SH, 'reserve'], {cwd: dir, env}).out.trim()
    return [{law: 'a reserved number is never handed out twice', repro: 'spec-next.sh reserve; age its ledger line past SPEC_RESERVE_TTL; spec-next.sh reserve',
      reproduced: a === b && a !== '', first: a, second: b}]
  } finally { t.done() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify({bridge: await bridge(), confirm: await confirm()}, null, 1))
