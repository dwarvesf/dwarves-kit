// Bridge: hold hooks/post-compact-reinject.sh to the post-compact-reinject rule in temp repos with zero, one or two
// open specs, with python3 on PATH and with a PATH that has none.
import {postCompactReinject} from './post-compact-reinject.ts'
import {gitRepo, pathWithout, rng, runHook, sandbox, sh, Tally, type BridgeResult} from './_bridge.ts'

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const f = postCompactReinject()
  const noPy = pathWithout('python')
  const g = rng(17)
  for (let i = 0; i < 24; i++) {
    const n = g.int(3), files: Record<string, string> = {'CLAUDE.md': '## Project\nA kit.\n\n## Other\n'}
    for (let k = 0; k < n; k++) files[`docs/specs/SPEC-00${k + 1}-s${k}.md`] = `# s\nStatus: DRAFT\n\n## Problem\nThe "thing" breaks.\n`
    const dir = gitRepo(files)
    const onBranch = n > 0 && g.bool()
    if (onBranch) sh('git checkout -q -b feat/s0', dir)
    const spec = n === 1 || (n === 2 && onBranch), ambig = n === 2 && !onBranch
    const python = g.bool()
    const s = sandbox()
    const env = python ? s.env : {...s.env, PATH: noPy}
    const out = f.run({spec, ambig, python})
    const r = runHook('post-compact-reinject.sh', {hook_event_name: 'SessionStart', source: 'compact'}, {env, cwd: dir})
    let ctx = ''
    try { ctx = JSON.parse(r.stdout).hookSpecificOutput.additionalContext } catch { ctx = '' }
    const hook = {rules: ctx.includes('Do NOT push to main/master') && ctx.includes('Do NOT use rm -rf'),
      namesSpec: /SPEC: docs\/specs\/SPEC-/.test(ctx), ambigLine: ctx.includes('SPEC: ambiguous')}
    t.check(hook.rules === out.rules && hook.namesSpec === out.namesSpec && hook.ambigLine === out.ambigLine,
      () => ({case: i, n, onBranch, python, rule: out, hook, code: r.code, stderr: r.stderr.slice(0, 200)}))
  }
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
