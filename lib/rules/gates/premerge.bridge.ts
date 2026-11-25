// Bridge: the real `premerge.sh check <repo>` on temp repos built per case (outside git, detached, on main, already
// current, behind with a clean merge, behind with a conflict, an unreachable origin), compared with the decision.
// It also checks the script's history promise on every case: the pre-run HEAD is an ancestor of the post-run HEAD.
import {join} from 'node:path'
import {bash, GATE, gitRepo, sandbox, sh, type BridgeResult} from './harness.ts'
import {premerge} from './premerge.ts'

const PM = join(GATE, 'premerge.sh')
const CASES = ['outside', 'detached', 'onMain', 'current', 'cleanMerge', 'conflict', 'fetchFails'] as const

export async function bridge(): Promise<BridgeResult> {
  const sb = sandbox(), f = premerge()
  let agree = 0
  try {
    for (const c of CASES) {
      let root = join(sb.dir, 'cwd')
      if (c !== 'outside') {
        root = gitRepo(sb, `pm-${c}`)
        sh(sb, 'echo base > shared.txt && git add -A && git commit -qm shared && git push -q origin main && git switch -qc feat/x && echo mine > mine.txt && git add -A && git commit -qm mine', root)
        if (c === 'detached') sh(sb, 'git checkout -q --detach', root)
        if (c === 'onMain') sh(sb, 'git switch -q main', root)
        if (c === 'cleanMerge' || c === 'conflict' || c === 'fetchFails') {
          const other = join(sb.dir, `pm-${c}-other`)
          sh(sb, `git clone -q ${join(sb.dir, `pm-${c}.git`)} ${other} && cd ${other} && echo ${c === 'conflict' ? 'theirs' : 'base'} > shared.txt && echo t > theirs.txt && git add -A && git commit -qm theirs && git push -q origin main`, root)
          if (c === 'conflict') sh(sb, 'echo ours > shared.txt && git commit -qam ours', root)
          if (c === 'fetchFails') sh(sb, `git remote set-url origin ${join(sb.dir, 'gone.git')}`, root)
        }
      }
      const before = c === 'outside' ? '' : sh(sb, 'git rev-parse HEAD', root).out.trim()
      const real = bash(sb, [PM, 'check', root])
      const after = c === 'outside' ? '' : sh(sb, 'git rev-parse HEAD', root).out.trim()
      const facts = {repo: c !== 'outside', detached: c === 'detached', resolved: true, onDefault: c === 'onMain',
        fetchOk: c !== 'fetchFails', current: c === 'current' || c === 'detached' || c === 'onMain', mergeOk: c !== 'conflict'}
      const o = f.run(facts)
      const kept = c === 'outside' || sh(sb, `git merge-base --is-ancestor ${before} ${after}`, root).code === 0
      const merged = before !== after
      if ((real.code === 0) !== o.ok || merged !== o.merged || !kept)
        return {agree, diverge: {case: c, facts, model: o, bash: {code: real.code, out: real.out.trim(), err: real.err.trim(), merged, historyKept: kept}}}
      agree++
    }
  } finally { sb.done() }
  return {agree, diverge: null}
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
