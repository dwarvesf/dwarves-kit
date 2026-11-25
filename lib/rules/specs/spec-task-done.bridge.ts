// Bridge: run the real lib/spec/spec-task-done.sh on generated specs (0-2 unchecked and 0-1 checked lines for the
// id T1, beside decoys T10 and T1a that must never match) and compare the counts, the log entries and the exit
// with the rule's compiled step. `logOk` false points --verify-log under a regular file, so no mkdir can make its
// directory (true even as root, unlike a chmod).
import {existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {specTaskDone, type Variant} from './spec-task-done.ts'
import {KIT, run, seeded, tmp, type BridgeResult} from './util.ts'

const SH = join(KIT, 'lib/spec/spec-task-done.sh')
type Call = {valid: boolean, withLog: boolean, logOk: boolean, pass: boolean}

const count = (text: string, box: string) =>
  text.split('\n').filter(l => {
    const s = l.replace(/^[ \t]*/, ''); const p = `- [${box}] T1`
    if (!s.startsWith(p)) return false
    const c = s.charAt(p.length); return c === '' || c === ':' || c === ' ' || c === '('
  }).length

function fixture(open: number, done: number) {
  const lines = ['# SPEC-001: x', '', 'Status: VALIDATED', '', '## Tasks', '', '- [ ] T10: a longer id', '- [ ] T1a: a suffixed id']
  for (let i = 0; i < open; i++) lines.push('- [ ] T1: title one')
  for (let i = 0; i < done; i++) lines.push('  - [x] T1 (DONE, commit abcdef1, verified): title one')
  return lines.join('\n') + '\n'
}

export async function bridge(variant: Variant = 'shipped'): Promise<BridgeResult> {
  const r = specTaskDone(variant)
  const step = r.compiled().step
  const t = tmp('task-done')
  let agree = 0
  try {
    mkdirSync(join(t.dir, 'ok')); writeFileSync(join(t.dir, 'blocker'), 'a file, not a dir\n')
    const okLog = join(t.dir, 'ok', 'verify', 'log.md'), badLog = join(t.dir, 'blocker', 'log.md')
    const entries = () => existsSync(okLog) ? readFileSync(okLog, 'utf8').split('\n').filter(l => l.startsWith('## T1 ')).length : 0
    const check = (open: number, done: number, calls: Call[], n: number) => {
      const spec = join(t.dir, `SPEC-${n}-x.md`)
      writeFileSync(spec, fixture(open, done))
      let st: any = {scalars: {open, done, logged: entries(), failed: 0}, maps: {}}
      const trail: Call[] = []
      for (const c of calls) {
        const argv = ['bash', SH, spec, 'T1', '--commit', c.valid ? 'abc1234' : 'xyz']
        if (c.withLog) argv.push('--verify-log', c.logOk ? okLog : badLog, '--command', 'bash t.sh', '--exit', '0',
          '--excerpt', 'ok\n```\nfenced', '--verdict', c.pass ? 'PASS' : 'FAIL')
        const res = run(argv)
        st = step({}, st, r.encodeInput(c))
        const m = r.decode(st) as {open: number, done: number, logged: number, failed: boolean}
        const text = readFileSync(spec, 'utf8')
        const bash = {open: count(text, ' '), done: count(text, 'x'), logged: entries(), failed: res.code !== 0}
        trail.push(c)
        if (bash.open !== m.open || bash.done !== m.done || bash.logged !== m.logged || bash.failed !== m.failed)
          return {start: {open, done}, calls: trail, bash, rule: m, exit: res.code, stderr: res.err.trim()}
        if (!text.includes('- [ ] T10: a longer id') || !text.includes('- [ ] T1a: a suffixed id'))
          return {start: {open, done}, calls: trail, error: 'a decoy id was touched'}
        agree++
      }
      return null
    }
    const bools = [false, true]
    let n = 0
    for (const open of [0, 1, 2]) for (const done of [0, 1]) for (const valid of bools) for (const withLog of bools)
      for (const logOk of bools) for (const pass of bools) {
        const d = check(open, done, [{valid, withLog, logOk, pass}], n++); if (d) return {agree, diverge: d}
      }
    const rand = seeded(129)
    for (let i = 0; i < 40; i++) {
      const calls = Array.from({length: 2 + rand(3)}, () => ({valid: rand(5) > 0, withLog: rand(2) > 0, logOk: rand(3) > 0, pass: rand(2) > 0}))
      const d = check(rand(3), rand(2), calls, n++); if (d) return {agree, diverge: d}
    }
    return {agree, diverge: null}
  } finally { t.done() }
}

// The refuted reviewer law, replayed: no --verify-log, and a FAIL verdict, are both accepted and tagged verified.
export async function confirm() {
  const t = tmp('task-done-cx')
  try {
    const spec = join(t.dir, 'SPEC-001-x.md')
    writeFileSync(spec, fixture(1, 0))
    const a = run(['bash', SH, spec, 'T1', '--commit', 'abc1234'])
    const tagged = readFileSync(spec, 'utf8').includes('- [x] T1 (DONE, commit abc1234, verified): title one')
    writeFileSync(spec, fixture(1, 0))
    const log = join(t.dir, 'log.md')
    const b = run(['bash', SH, spec, 'T1', '--commit', 'abc1234', '--verify-log', log, '--command', 'x', '--exit', '1', '--excerpt', 'boom', '--verdict', 'FAIL'])
    const tagged2 = readFileSync(spec, 'utf8').includes('verified')
    return [{law: 'a task is marked verified only with a recorded PASS verification log entry',
      repro: "printf -- '- [ ] T1: t\\n' > s.md; bash lib/spec/spec-task-done.sh s.md T1 --commit abc1234",
      reproduced: a.code === 0 && tagged && b.code === 0 && tagged2, noLog: {exit: a.code, tagged}, failVerdict: {exit: b.code, tagged: tagged2}}]
  } finally { t.done() }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const v = (process.argv[2] ?? 'shipped') as Variant
  console.log(JSON.stringify({variant: v, bridge: await bridge(v), confirm: await confirm()}, null, 1))
}
