// Bridge: lib/wrap/wrap-merge.sh:_pr_gate (its real jq, CI_JQ_DEFS included) against the two rules in pr-gate.ts.
// Seeded random PR JSON: draft or not, base main or another, every mergeable, review and merge state (including a
// missing mergeStateStatus), and a rollup of CheckRun and StatusContext entries, several runs per name, pending or
// completed, with real, zero or missing times. The rule side never re-implements the grouping: each name's runs are
// stepped through check-verdict's interpreter in array order, and pr-gate reads the standing runs.
import {bash, KIT, rng, sandbox, type BridgeResult} from './bridge-util.ts'
import {checkVerdict, prGate, type GateVariant} from './pr-gate.ts'
import {execFileSync} from 'node:child_process'
import {join} from 'node:path'

type Run = Record<string, unknown>
const iso = (t: number) => `2026-01-01T00:${String(Math.floor(t / 60)).padStart(2, '0')}:${String(t % 60).padStart(2, '0')}Z`

function genRun(rand: ReturnType<typeof rng>, name: string): Run {
  const t = 1 + rand.int(5)
  const zeroOrMissing = () => rand.pick([undefined, '', '0001-01-01T00:00:00Z'])
  if (rand.next() < 0.6) {
    const status = rand.pick(['COMPLETED', 'COMPLETED', 'IN_PROGRESS', 'QUEUED', undefined])
    const done = status === 'COMPLETED' || status === undefined
    const run: Run = {name, status, conclusion: done ? rand.pick(['SUCCESS', 'FAILURE', 'SKIPPED', 'NEUTRAL', 'success']) : rand.pick(['', null])}
    if (done) run.completedAt = rand.next() < 0.8 ? iso(t) : zeroOrMissing()
    else run.completedAt = '0001-01-01T00:00:00Z'
    run.startedAt = rand.next() < 0.7 ? iso(Math.max(1, t - 1)) : zeroOrMissing()
    return run
  }
  return {context: name, state: rand.pick(['SUCCESS', 'FAILURE', 'PENDING', 'EXPECTED', 'ERROR']), startedAt: rand.next() < 0.8 ? iso(t) : zeroOrMissing()}
}

const real = (v: unknown) => v !== undefined && v !== null && v !== '' && v !== '0001-01-01T00:00:00Z'
const secs = (v: string) => { const m = /T00:(\d\d):(\d\d)Z$/.exec(v); return m ? Number(m[1]) * 60 + Number(m[2]) : 0 }

// The rule's view of one entry: its field values, read the way CI_JQ_DEFS defines them.
function entryInputs(r: Run) {
  const pending = ((r.status ?? 'COMPLETED') !== 'COMPLETED') || r.state === 'PENDING' || r.state === 'EXPECTED'
  const t = [r.completedAt, r.startedAt, r.createdAt].find(real) as string | undefined
  const c = String((r.conclusion ?? r.state ?? '') as string).toUpperCase()
  return {pending, time: t ? secs(t) : 0, ok: c === 'SUCCESS' || c === 'SKIPPED'}
}

export async function bridge(opts: {seed?: number, n?: number, variant?: GateVariant, source?: 'work' | 'head'} = {}): Promise<BridgeResult> {
  const rand = rng(opts.seed ?? 7)
  const n = opts.n ?? 3000
  const cv = checkVerdict(), gate = prGate(opts.variant ?? 'shipped')
  const it = cv.interpreter(), p = cv.encodeParams({})
  const sb = sandbox('pr-gate')
  try {
    const prs: Record<string, unknown>[] = []
    for (let i = 0; i < n; i++) {
      const names = ['lint', 'test', 'deploy'].slice(0, rand.int(4))
      const rollup: Run[] = []
      for (const nm of names) for (let k = 0, m = 1 + rand.int(3); k < m; k++) rollup.push(genRun(rand, nm))
      for (let k = rollup.length - 1; k > 0; k--) { const j = rand.int(k + 1); [rollup[k], rollup[j]] = [rollup[j], rollup[k]] }
      const pr: Record<string, unknown> = {
        number: 9, isDraft: rand.pick([true, false, false, undefined]), baseRefName: rand.pick(['main', 'main', 'dev']),
        mergeable: rand.pick(['MERGEABLE', 'MERGEABLE', 'CONFLICTING', 'UNKNOWN']),
        reviewDecision: rand.pick(['APPROVED', 'CHANGES_REQUESTED', 'REVIEW_REQUIRED', null]),
        statusCheckRollup: rand.next() < 0.1 ? null : rollup,
      }
      const ms = rand.pick(['CLEAN', 'CLEAN', 'HAS_HOOKS', 'UNSTABLE', 'BLOCKED', 'BEHIND', 'DIRTY', undefined])
      if (ms !== undefined) pr.mergeStateStatus = ms
      prs.push(pr)
    }
    const file = join(sb.dir, 'prs.jsonl')
    execFileSync('bash', ['-c', `cat > '${file}'`], {input: prs.map((x) => JSON.stringify(x)).join('\n') + '\n'})
    const lib = opts.source === 'head' ? `<(git -C '${KIT}' show HEAD:lib/wrap/wrap-merge.sh)` : `'${KIT}/lib/wrap/wrap-merge.sh'`
    const out = bash(`source '${KIT}/lib/wrap/wrap.sh' >/dev/null 2>&1; source ${lib}
      while IFS= read -r line; do v="$(_pr_gate "$line" main)"; echo "\${v%% *}"; done < '${file}'`, sb.env, sb.dir, 300_000)
    const verdicts = out.stdout.trim().split('\n')
    let agree = 0
    for (let i = 0; i < n; i++) {
      const pr = prs[i] as Record<string, any>
      const rollup: Run[] = pr.statusCheckRollup ?? []
      const groups = new Map<string, Run[]>()
      for (const r of rollup) { const k = String(r.name ?? r.context); groups.set(k, [...(groups.get(k) ?? []), r]) }
      let anyBad = false
      for (const runs of groups.values()) {
        let st = it.init(p)
        for (const r of runs) st = it.step(p, st, cv.encodeInput(entryInputs(r)))
        if (!cv.decode(st).bOk) anyBad = true
      }
      const o = gate.run({
        isDraft: pr.isDraft === true, baseOk: pr.baseRefName === 'main', mergeable: pr.mergeable,
        hasChecks: rollup.length > 0, anyBad,
        review: pr.reviewDecision === 'APPROVED' || pr.reviewDecision === 'CHANGES_REQUESTED' ? pr.reviewDecision : 'NONE',
        mstate: pr.mergeStateStatus ?? 'ABSENT',
      })
      const want = o.ok ? 'OK' : o.conflict ? 'CONFLICT' : o.wait ? 'WAIT' : 'SKIP'
      if (verdicts[i] !== want) return {agree, diverge: {pr, bash: verdicts[i], rule: want}}
      agree++
    }
    return {agree, diverge: null}
  } finally { sb.cleanup() }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const head = process.argv[2] === 'head'
  console.log(JSON.stringify(await bridge(head ? {source: 'head', variant: 'absent-is-clean'} : {})))
  if (!head) console.log('vs head code:', JSON.stringify(await bridge({source: 'head'})))
}
