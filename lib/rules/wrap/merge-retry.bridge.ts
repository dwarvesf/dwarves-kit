// Bridge: lib/wrap/wrap-common.sh:_gh_merge_retry against the merge-retry rule.
// A stub `gh` answers each `gh pr merge` from a scripted list (ok, "already merged", a 502, a real refusal); past the
// list it keeps answering 502 (an outage that never clears) up to call 50, then a refusal, so even the unbounded
// pre-fix code ends. Every list of length 1..3 over the four answers, plus 100 seeded random lists of length up to 8, for
// WRAP_MERGE_RETRY_MAX in {0, 1, 2, 3, 5, five, 3.5, -1}. The rule is fed the same padded answers.
// `source: 'head'` runs the committed (pre-fix) wrap-common.sh instead, against the variant that models it.
import {readFileSync} from 'node:fs'
import {join} from 'node:path'
import {execFileSync} from 'node:child_process'
import {bash, KIT, rng, sandbox, sequences, stub, type BridgeResult} from './bridge-util.ts'
import {ANSWERS, mergeRetry, type Variant} from './merge-retry.ts'

const PAD_TO = 50
const MAXES = ['0', '1', '2', '3', '5', 'five', '3.5', '-1']

function padded(seq: string[]) {
  const out = [...seq]
  while (out.length < PAD_TO) out.push('transient')
  out.push('refusal')
  return out
}

function model(variant: Variant, maxRaw: string, seq: string[]) {
  const r = mergeRetry(variant)
  const isNum = /^[0-9]+$/.test(maxRaw)
  // The bash's `-ge` on a negative number is still a number test; the fix maps it to 3, the old code compares.
  const negative = /^-[0-9]+$/.test(maxRaw)
  let max = isNum ? Number(maxRaw) : 0, maxIsNum = isNum
  if (negative && variant === 'unvalidated-max') { max = 0; maxIsNum = true }
  const it = r.interpreter(), p = r.encodeParams({max, maxIsNum})
  let st = it.init(p)
  for (const ans of padded(seq)) {
    if (r.decode(st).phase !== 'trying') break
    st = it.step(p, st, r.encodeInput({ans}))
  }
  const d = r.decode(st) as {phase: string, calls: number}
  return {rc0: d.phase === 'merged', calls: d.calls}
}

const SNIPPET = (src: string) => {
  const lines = src.split('\n')
  const pick: string[] = []
  let on = false
  for (const l of lines) {
    if (/^_gh_merge_transient\(\)|^_gh_merge_retry\(\)/.test(l)) on = true
    if (/^WRAP_MERGE_RETRY_(MAX|SLEEP)=|^case "\$WRAP_MERGE_RETRY_(MAX|SLEEP)"/.test(l)) pick.push(l)
    if (on) pick.push(l)
    if (on && l === '}') on = false
  }
  return pick.join('\n')
}

export async function bridge(opts: {source?: 'work' | 'head', seed?: number, random?: number, maxes?: string[]} = {}): Promise<BridgeResult> {
  const source = opts.source ?? 'work'
  const variant: Variant = source === 'head' ? 'unvalidated-max' : 'shipped'
  const src = source === 'head'
    ? execFileSync('git', ['-C', KIT, 'show', 'HEAD:lib/wrap/wrap-common.sh'], {encoding: 'utf8'})
    : readFileSync(join(KIT, 'lib/wrap/wrap-common.sh'), 'utf8')
  const sb = sandbox('merge-retry')
  try {
    const fn = join(sb.dir, 'fn.sh')
    execFileSync('bash', ['-c', `cat > ${fn}`], {input: SNIPPET(src)})
    stub(sb.bin, 'gh', `
n=$(cat "$GHS_N" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$GHS_N"
a="$(sed -n "\${n}p" "$GHS_SEQ")"; [ -n "$a" ] || a=refusal
case "$a" in
  ok) echo "merged"; exit 0 ;;
  already) echo "! Pull request o/r#7 was already merged" >&2; exit 1 ;;
  transient) echo "HTTP 502: Bad Gateway (https://api.github.com/graphql)" >&2; exit 1 ;;
  refusal) echo "Pull request o/r#7 is not mergeable: the base branch policy prohibits the merge." >&2; exit 1 ;;
esac`)
    const rand = rng(opts.seed ?? 20261125)
    const cases: string[][] = sequences(ANSWERS as readonly string[], 3)
    for (let i = 0; i < (opts.random ?? 100); i++) {
      const len = 1 + rand.int(8)
      cases.push(Array.from({length: len}, () => rand.pick(ANSWERS)))
    }
    let agree = 0
    for (const maxRaw of opts.maxes ?? MAXES) {
      // One bash per MAX (the value is read when the file is sourced); it walks every case.
      const caseFile = join(sb.dir, `cases-${maxRaw}`)
      execFileSync('bash', ['-c', `cat > '${caseFile}'`], {input: cases.map((c) => padded(c).join(' ')).join('\n') + '\n'})
      const out = bash(`
        export WRAP_MERGE_RETRY_MAX='${maxRaw}' WRAP_MERGE_RETRY_SLEEP=0
        source '${fn}'
        while IFS= read -r line; do
          printf '%s\\n' $line > "$GHS_SEQ"; : > "$GHS_N"
          _gh_merge_retry 7 https://github.com/o/r deadbeef >/dev/null 2>&1; rc=$?
          echo "$rc $(cat "$GHS_N")"
        done < '${caseFile}'`, {...sb.env, GHS_SEQ: join(sb.dir, 'seq'), GHS_N: join(sb.dir, 'n')}, sb.dir, 300_000)
      const rows = out.stdout.trim().split('\n')
      for (let i = 0; i < cases.length; i++) {
        const [rc, calls] = (rows[i] ?? '').split(' ')
        const real = {rc0: rc === '0', calls: Number(calls)}
        const want = model(variant, maxRaw, cases[i])
        if (real.rc0 !== want.rc0 || real.calls !== want.calls) {
          return {agree, diverge: {source, WRAP_MERGE_RETRY_MAX: maxRaw, answers: cases[i], bash: real, rule: want}}
        }
        agree++
      }
    }
    return {agree, diverge: null}
  } finally { sb.cleanup() }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const head = process.argv[2] === 'head'
  // The committed code loops to the stub's 50-call cap on a non-number MAX, so the head run keeps to two values.
  const r = await bridge(head ? {source: 'head', maxes: ['3', 'five'], random: 0} : {})
  console.log(JSON.stringify(r))
}
