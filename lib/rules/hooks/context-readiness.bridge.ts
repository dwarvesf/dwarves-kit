// Bridge: hold hooks/context-readiness.sh's "next:" suggestion to the context-readiness rule. Each case is a temp git
// repo with specs under docs/specs/ (status header, checkbox tasks, a ## Review section), a branch, and a board
// (_meta/BACKLOG.md) with queued rows; the hook's suggestion text is mapped back to the rule's output.
import {contextReadiness} from './context-readiness.ts'
import {gitRepo, rng, runHook, sandbox, sh, Tally, type BridgeResult} from './_bridge.ts'

const SUGGEST: [string, string][] = [
  ['disambiguate', 'multiple live specs'], ['board', 'queued on the board'], ['think', 'no spec found'],
  ['validate', 'spec is DRAFT'], ['ship', "say 'ship it'"], ['review', "say 'review it'"], ['cont', "say 'continue'"],
]

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const f = contextReadiness()
  const g = rng(99)
  for (let i = 0; i < 70; i++) {
    const nSpecs = g.pick([0, 1, 1, 1, 2])
    const files: Record<string, string> = {'CLAUDE.md': '# x\n'}
    const specs: {status: string, total: number, done: number, reviewed: boolean}[] = []
    for (let k = 0; k < nSpecs; k++) {
      const status = g.pick(['DRAFT', 'APPROVED', 'VALIDATED', 'NONE', 'IMPLEMENTED', 'SHIPPED'])
      const total = g.int(4), done = g.int(total + 1), reviewed = g.bool()
      const tasks = Array.from({length: total}, (_, j) => `- [${j < done ? 'x' : ' '}] task ${j}`).join('\n')
      files[`docs/specs/SPEC-00${k + 1}-thing-${k}.md`] = `# SPEC-00${k + 1} thing\n${status === 'NONE' ? '' : `Status: ${status}\n`}\n## Tasks\n${tasks}\n${reviewed ? '\n## Review\nSHIP\n' : ''}`
      specs.push({status: status === 'IMPLEMENTED' ? 'VALIDATED' : status, total, done, reviewed})
    }
    const queued = g.pick([0, 0, 2])
    if (g.bool()) files['_meta/BACKLOG.md'] = `| ID | title | status |\n|---|---|---|\n${Array.from({length: queued}, (_, j) => `| ID-${j + 1} | t | queued |`).join('\n')}\n| ID-9 | t | done |\n`
    const hasBoard = '_meta/BACKLOG.md' in files
    const dir = gitRepo(files)
    const onSpecBranch = nSpecs > 0 && g.bool()
    if (onSpecBranch) sh('git checkout -q -b feat/thing-0', dir)
    // What spec_active --live would resolve: open specs (not SHIPPED); the branch's own spec wins.
    const open = specs.map((s, k) => ({...s, k})).filter((s) => s.status !== 'SHIPPED')
    const branchSpec = onSpecBranch ? open.find((s) => s.k === 0) : undefined
    const chosen = branchSpec ?? (open.length === 1 ? open[0] : undefined)
    const ambig = !chosen && open.length > 1
    const facts = {ambig, spec: !!chosen, status: chosen?.status ?? 'NONE', total: chosen?.total ?? 0, done: chosen?.done ?? 0,
      reviewed: chosen?.reviewed ?? false, queued: hasBoard ? queued : 0}
    const out = f.run(facts as any) as Record<string, boolean>
    const r = runHook('context-readiness.sh', {hook_event_name: 'SessionStart', source: 'startup'}, {env: sandbox().env, cwd: dir})
    let ctx = ''
    try { ctx = JSON.parse(r.stdout).additionalContext ?? '' } catch { ctx = `UNPARSEABLE ${r.stdout}` }
    const hookSaid = SUGGEST.filter(([, needle]) => ctx.includes(needle)).map(([k]) => k)
    const ruleSaid = SUGGEST.filter(([k]) => out[k]).map(([k]) => k)
    t.check(r.code === 0 && hookSaid.join() === ruleSaid.join(), () => ({case: i, specs, onSpecBranch, facts, rule: ruleSaid, hook: hookSaid, ctx}))
    if (out.silent && !ctx.includes('next:')) t.note('a live spec with no Status header gets no next step (spec:NONE)')
  }
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
