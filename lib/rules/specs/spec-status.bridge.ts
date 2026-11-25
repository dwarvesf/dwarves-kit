// Bridge: run the real lib/spec/spec-status.sh `set` and `get` on temp spec files and compare every step with
// the proven rule's compiled step (spec-status.ts). Every header form x every target, then seeded random runs.
import {writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {STATES, TARGETS, specStatus} from './spec-status.ts'
import {KIT, run, seeded, tmp, type BridgeResult} from './util.ts'

const SH = join(KIT, 'lib/spec/spec-status.sh')
// Header forms the reader accepts, with the canonical state `get` must read from each.
const HEADERS: [string, (typeof STATES)[number]][] = [
  ['# Spec\n\nno header here\n', 'NONE'],
  ['# Spec\nStatus: DRAFT\n', 'DRAFT'],
  ['# Spec\n**Status:** VALIDATED (round 4, 2026-07-01)\n', 'VALIDATED'],
  ['# Spec\nstatus: shipped\n', 'SHIPPED'],
  ['# Spec\nStatus: BUILT\n', 'VALIDATED'],
  ['# Spec\nStatus: SUPERSEDED by SPEC-9\n', 'PARKED'],
  ['# Spec\nStatus: Wibble\n', 'UNKNOWN'],
  ['# Spec\n**Status**: APPROVED\n', 'APPROVED'],
  ['# Spec\nStatus: PARKED\n', 'PARKED'],
  ['# Spec\n**Status:** SHIPPED-PENDING\nStatus: DRAFT\n', 'SHIPPED'],
]
// A target word for the bash, and the rule's input it stands for.
const WORDS: [string, (typeof TARGETS)[number]][] = [
  ['DRAFT', 'DRAFT'], ['approved', 'APPROVED'], ['Validated', 'VALIDATED'], ['SHIPPED', 'SHIPPED'], ['parked', 'PARKED'],
  ['BUILT', 'NONCANON'], ['superseded', 'NONCANON'], ['frobbed', 'NONCANON'],
]

export async function bridge(): Promise<BridgeResult> {
  const r = specStatus()
  const step = r.compiled().step
  const t = tmp('spec-status')
  let agree = 0
  try {
    const check = (seq: number[], header: number): null | Record<string, unknown> => {
      const f = join(t.dir, 'SPEC-001-x.md')
      writeFileSync(f, HEADERS[header][0])
      const got0 = run(['bash', SH, 'get', f]).out.trim()
      if (got0 !== HEADERS[header][1]) return {header: HEADERS[header][0], get: got0, want: HEADERS[header][1]}
      let st: any = {scalars: {st: STATES.indexOf(HEADERS[header][1]), notice: 0, refused: 0}, maps: {}}
      const trail: string[] = []
      for (const w of seq) {
        const [word, input] = WORDS[w]
        const res = run(['bash', SH, 'set', f, word])
        st = step({}, st, r.encodeInput({to: input}))
        const m = r.decode(st) as {st: string, notice: boolean, refused: boolean}
        const got = run(['bash', SH, 'get', f]).out.trim()
        const bash = {st: got, notice: res.err.includes('reopens from terminal'), refused: res.code !== 0}
        trail.push(`set ${word}`)
        if (bash.st !== m.st || bash.notice !== m.notice || bash.refused !== m.refused) {
          return {header: HEADERS[header][0], steps: trail, bash, rule: m, stderr: res.err.trim()}
        }
        agree++
      }
      return null
    }
    for (let h = 0; h < HEADERS.length; h++) for (let w = 0; w < WORDS.length; w++) {
      const d = check([w], h); if (d) return {agree, diverge: d}
    }
    const rand = seeded(417)
    for (let i = 0; i < 60; i++) {
      const seq = Array.from({length: 2 + rand(4)}, () => rand(WORDS.length))
      const d = check(seq, rand(HEADERS.length)); if (d) return {agree, diverge: d}
    }
    return {agree, diverge: null}
  } finally { t.done() }
}

// Replay each refuted law's counterexample on the real bash: a permissive writer accepts both, silently.
export async function confirm() {
  const t = tmp('spec-status-cx')
  try {
    const f = join(t.dir, 'SPEC-002-y.md')
    const out = []
    for (const [from, to, law] of [['DRAFT', 'SHIPPED', 'a spec becomes SHIPPED only from APPROVED or VALIDATED (its declared next)'],
      ['VALIDATED', 'DRAFT', 'a move off the declared next path (a skip or a step back) is announced']]) {
      writeFileSync(f, `# Spec\nStatus: ${from}\n`)
      const res = run(['bash', SH, 'set', f, to])
      const got = run(['bash', SH, 'get', f]).out.trim()
      out.push({law, repro: `printf '# Spec\\nStatus: ${from}\\n' > s.md; bash lib/spec/spec-status.sh set s.md ${to}`,
        reproduced: res.code === 0 && got === to && res.err.trim() === '', exit: res.code, get: got, stderr: res.err.trim()})
    }
    return out
  } finally { t.done() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify({bridge: await bridge(), confirm: await confirm()}, null, 1))
