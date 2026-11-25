// Bridge for the review-verdict rule, three parts, each against the real bash:
//  spec    seeded random spec bodies (fences, sections, verdict spellings) through ship-rules.sh's
//          _sr_review_last_verdict, compared with specVerdict's interpreter;
//  ledger  seeded random row sequences written with gate-ledger.sh record/override/action, read back with
//          `gate-ledger.sh review-verdict`, compared with ledgerVerdict's interpreter;
//  gate    every combination of (spec readable, switch, ledger present, spec verdict, recorded verdict) through
//          ship_rule_review_verdict itself, compared with reviewGate.run.
import {join} from 'node:path'
import {bash, GATE, product, q, rng, sandbox, write, type BridgeResult, type Sandbox} from './harness.ts'
import {ledgerVerdict, LINES, reviewGate, ROWS, specVerdict, VERDICTS} from './review-verdict.ts'

const RULES = join(GATE, 'ship-rules.sh'), LEDGER = join(GATE, 'gate-ledger.sh')
const OUT: Record<string, string> = {'': 'none', 'SHIP': 'SHIP', 'FIX THEN SHIP': 'FIX', 'DO NOT SHIP': 'DNS'}
type R = ReturnType<typeof rng>

const SPELL: Record<string, string[]> = {
  SHIP: ['SHIP', 'ship', 'SHIP (clean)', '**SHIP**'], FIX: ['FIX THEN SHIP', 'fix-then-ship', 'Fix then ship: 2 nits'],
  DNS: ['DO NOT SHIP', 'do-not-ship', 'DO NOT SHIP.'], none: ['SECURE', 'SOLID', 'PASS'],
}
function specLine(rand: R, line: string, word: string): string {
  switch (line) {
    case 'fence': return rand.pick(['```', '  ~~~', '```bash'])
    case 'review': return rand.pick(['## Review', '## Review  '])
    case 'heading': return rand.pick(['## Other', '# Title', '## Review disposition'])
    case 'verdict': return rand.pick(['### Verdict: ', '**Verdict:** ', 'Verdict: ', '  ### Verdict: ', '### Verdict after fixes: ']) + rand.pick(SPELL[word])
    case 'indented': return '    ### Verdict: ' + rand.pick(SPELL[word])
    default: return rand.pick(['some text', '- a bullet', 'Verdict is not here'])
  }
}

function specPart(sb: Sandbox, rand: R, n: number) {
  const r = specVerdict(), it = r.interpreter()
  const cases: {lines: {line: string, word: string}[], text: string}[] = []
  for (let i = 0; i < n; i++) {
    const lines = Array.from({length: 1 + rand.int(7)}, () => ({line: rand.pick(LINES), word: rand.pick(VERDICTS)}))
    cases.push({lines, text: lines.map(l => specLine(rand, l.line, l.word)).join('\n') + '\n'})
  }
  cases.forEach((c, i) => write(join(sb.dir, `spec/${i}.md`), c.text))
  const res = bash(sb, ['-c', `source ${q(RULES)}; for i in $(seq 0 ${n - 1}); do printf '%s\\n' "$(_sr_review_last_verdict < ${q(sb.dir)}/spec/$i.md)"; done`])
  const got = res.out.split('\n')
  for (let i = 0; i < n; i++) {
    let st = it.init({})
    for (const l of cases[i].lines) st = it.step({}, st, r.encodeInput(l as any))
    const want = (r.decode(st) as any).v
    if (OUT[got[i]] !== want) return {agree: i, diverge: {part: 'spec', text: cases[i].text, lines: cases[i].lines, model: want, bash: got[i]}}
  }
  return {agree: n, diverge: null}
}

// A reason must START with the verdict followed by a space, : ; , . or the end (lib/gate/README.md). The reader
// strips leading `* _ backtick`, so `**SHIP**` reads as SHIP followed by `*`: not a verdict (the spec reader,
// by contrast, accepts `**SHIP**`; FINDINGS.md, observations).
const REASON: Record<string, string[]> = {
  SHIP: ['SHIP findings=0', 'ship: clean', '**SHIP all good'], FIX: ['FIX THEN SHIP findings=2', 'fix-then-ship; nits'],
  DNS: ['DO NOT SHIP. findings=3', 'do not ship'], none: ['SHIP-clean', 'ok', 'shipping later', 'note', '**SHIP** all good', '**DO NOT SHIP** x'],
}
function rowCall(rand: R, rid: string, row: string, word: string, k: number): string[] {
  const text = rand.pick(REASON[word])
  switch (row) {
    case 'ran': return ['record', rid, rand.pick(['review', 'battery']), 'ran', text]
    case 'other': return rand.next() < 0.5 ? ['record', rid, 'review', rand.pick(['skipped', 'rejected']), text] : ['override', rid, 'review', `${text} #${k}`]
    case 'phase': return ['record', rid, rand.pick(['build', 'docs']), 'ran', text]
    default: return ['action', rid, `| GATE | review | ran | ${text}`]
  }
}

function ledgerPart(sb: Sandbox, rand: R, n: number) {
  const r = ledgerVerdict(), it = r.interpreter()
  for (let i = 0; i < n; i++) {
    const rid = `rv-${i}`, rows = Array.from({length: 1 + rand.int(5)}, () => ({row: rand.pick(ROWS), word: rand.pick(VERDICTS)}))
    let st = it.init({})
    rows.forEach((x, k) => { bash(sb, [LEDGER, ...rowCall(rand, rid, x.row, x.word, k)]); st = it.step({}, st, r.encodeInput(x as any)) })
    const got = bash(sb, [LEDGER, 'review-verdict', rid]).out.trim()
    const want = (r.decode(st) as any).v
    if (OUT[got] !== want) return {agree: i, diverge: {part: 'ledger', rid, rows, model: want, bash: got, ledger: bash(sb, [LEDGER, 'show', rid]).out}}
  }
  return {agree: n, diverge: null}
}

function gatePart(sb: Sandbox) {
  const f = reviewGate()
  const off = join(sb.dir, 'op-off'), on = join(sb.dir, 'op-on')
  write(join(off, 'kit.toml'), '[gate]\nreview_verdict = false\n'); write(join(on, 'kit.toml'), '[gate]\nreview_verdict = true\n')
  const root = join(sb.dir, 'cwd')
  const specText: Record<string, string> = {none: '# Spec\n\n## Review\nnothing yet\n', SHIP: '## Review\n### Verdict: SHIP\n',
    FIX: '## Review\n### Verdict: FIX THEN SHIP\n', DNS: '## Review\n### Verdict: DO NOT SHIP\n'}
  for (const v of VERDICTS) write(join(root, `docs/specs/SPEC-1-${v}.md`), specText[v])
  for (const v of VERDICTS) if (v !== 'none') bash(sb, [LEDGER, 'record', `rec-${v}`, 'review', 'ran', `${({SHIP: 'SHIP', FIX: 'FIX THEN SHIP', DNS: 'DO NOT SHIP'} as any)[v]} findings=1`])
  const combos = [...product({readable: [true, false], on: [true, false], ledger: [true, false], spec: VERDICTS, rec: VERDICTS})]
  const lines = combos.map(c => {
    const spec = c.readable ? join(root, `docs/specs/SPEC-1-${c.spec}.md`) : join(root, 'docs/specs/missing.md')
    const led = c.ledger ? LEDGER : join(sb.dir, 'no-ledger.sh')
    return `KIT_CONFIG_OPERATOR=${q(c.on ? on : off)} ship_rule_review_verdict ${q(root)} '' '' ${q(spec)} rec-${c.rec} ${q(led)} 2>/dev/null; echo $?`
  })
  const res = bash(sb, ['-c', `source ${q(RULES)}\n${lines.join('\n')}`])
  const got = res.out.trim().split('\n')
  for (let i = 0; i < combos.length; i++) {
    const want = f.run(combos[i] as any).block
    if ((got[i] === '2') !== want) return {agree: i, diverge: {part: 'gate', combo: combos[i], model: want ? 'block' : 'pass', bash: got[i]}}
  }
  return {agree: combos.length, diverge: null}
}

export async function bridge(opts: {n?: number, seed?: number} = {}): Promise<BridgeResult> {
  const n = opts.n ?? Number(process.env.BRIDGE_N ?? 40), rand = rng(opts.seed ?? 11), sb = sandbox()
  try {
    let agree = 0
    for (const part of [() => specPart(sb, rand, n * 5), () => ledgerPart(sb, rand, n), () => gatePart(sb)]) {
      const r = part(); agree += r.agree
      if (r.diverge) return {agree, diverge: r.diverge}
    }
    return {agree, diverge: null}
  } finally { sb.done() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
