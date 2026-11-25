// Bridge: a temp ledger root (KIT_LEDGER_DIR), the real lib/ledger/ledger.sh `append` on `runs/r.log` (append) or
// `../escape.log` (appendUp), and torn writes made by hand (a record with no newline, as a crash leaves it). After
// each step the stream is read back: complete lines, a torn tail, whether a record already written changed, and
// what landed outside the root; all compared with the rule's compiled step (ledger-append.ts).
import {appendFileSync, existsSync, mkdirSync, readFileSync} from 'node:fs'
import {join} from 'node:path'
import {OPS, ledgerAppend, type Variant} from './ledger-append.ts'
import {KIT, run, seeded, tmp, type BridgeResult} from './util.ts'

const SH = join(KIT, 'lib/ledger/ledger.sh')

export async function bridge(variant: Variant = 'shipped'): Promise<BridgeResult> {
  const r = ledgerAppend(variant)
  const step = r.compiled().step
  const t = tmp('ledger')
  let agree = 0
  try {
    const rand = seeded(85)
    for (let i = 0; i < 40; i++) {
      const base = join(t.dir, `b${i}`), root = join(base, 'root'); mkdirSync(root, {recursive: true})
      const file = join(root, 'runs/r.log'), out = join(base, 'escape.log')
      let st: any = r.compiled().init({})
      let records: string[] = [], tornText = '', changed = false
      const trail: string[] = []
      for (let j = 0; j < 2 + rand(6); j++) {
        const op = OPS[rand(10) < 6 ? 0 : 1 + rand(2)]
        const text = `2026-11-25T00:00:0${j}Z | GATE | step${j} | ran`
        let res = {code: 0, out: '', err: ''}
        if (op === 'tear') { mkdirSync(join(root, 'runs'), {recursive: true}); appendFileSync(file, `torn${j} | GATE | half`) }
        else res = run(['bash', SH, 'append', op === 'append' ? 'runs/r.log' : '../escape.log', text], {env: {KIT_LEDGER_DIR: root, HOME: base}})
        st = step({}, st, r.encodeInput({op}))
        const m = r.decode(st) as {lines: number, torn: boolean, changed: boolean, outside: number, refused: boolean}
        const body = existsSync(file) ? readFileSync(file, 'utf8') : ''
        const lines = body.split('\n'), complete = lines.slice(0, -1)
        // A record already written must still be its own line, in place; a torn fragment must be kept as written.
        for (let k = 0; k < records.length; k++) if (complete[k] !== records[k]) changed = true
        if (tornText && complete.length > records.length && complete[records.length] !== tornText) changed = true
        records = complete.slice(); tornText = lines[lines.length - 1]
        const outside = existsSync(out) ? readFileSync(out, 'utf8').split('\n').length - 1 : 0
        const bash = {lines: complete.length, torn: tornText !== '', changed, outside, refused: op === 'appendUp' && res.code !== 0}
        trail.push(op)
        if (bash.lines !== m.lines || bash.torn !== m.torn || bash.changed !== m.changed || bash.outside !== m.outside || bash.refused !== m.refused)
          return {agree, diverge: {trail, bash, rule: m, stream: body, stderr: res.err.trim()}}
        agree++
      }
    }
    return {agree, diverge: null}
  } finally { t.done() }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const v = (process.argv[2] ?? 'shipped') as Variant
  console.log(JSON.stringify({variant: v, bridge: await bridge(v)}, null, 1))
}
