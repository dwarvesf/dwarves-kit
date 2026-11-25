// Bridge: `bin/wrap apply [--apply] --worktrees <repo>` (the real verb) on real git fixtures against worktree-sweep.
// Baseline: a clone whose worktree holds branch feat, an ancestor of origin/main (merged, provable without gh: the
// gh stub reports not signed in). Each case changes one thing: dirty (an untracked file), detached HEAD, the branch
// named master (protected), the fetch fails (origin gone), the branch has an unmerged commit, a lock naming a live
// pid (this node process) or a dead one, no --worktrees flag, the dry run, and a foreign index.lock (fresh, which
// outlives the stale window because sleep is stubbed and the clock does not move, or 60 s old). The busy check is
// off (KIT_WRAP_SKIP_BUSY_CHECK=1) except in 'busy', where a background `sleep` sits in the worktree.
import {join} from 'node:path'
import {bash, KIT, sandbox, stub, type BridgeResult} from './bridge-util.ts'
import {worktreeSweep} from './worktree-sweep.ts'

type Case = {name: string, setup: string, flags: string, inputs: Partial<Record<string, boolean>>}
const BASE = {scope: true, dirty: false, detached: false, protected: false, current: false, fetchOk: true, merged: true,
  dirtyAfter: false, tipMoved: false, lockLive: false, busy: false, apply: true, indexFree: true, cleared: true}

export async function bridge(): Promise<BridgeResult> {
  const sb = sandbox('worktree-sweep')
  try {
    stub(sb.bin, 'gh', 'exit 1')
    const realSleep = '/bin/sleep'
    const cases: Case[] = [
      {name: 'happy', setup: '', flags: '--apply --worktrees', inputs: {}},
      {name: 'dry', setup: '', flags: '--worktrees', inputs: {apply: false}},
      {name: 'noflag', setup: '', flags: '--apply', inputs: {scope: false}},
      {name: 'dirty', setup: 'echo x > "$WT/scratch.txt"', flags: '--apply --worktrees', inputs: {dirty: true}},
      {name: 'detached', setup: 'git -C "$WT" checkout -q --detach', flags: '--apply --worktrees', inputs: {detached: true}},
      {name: 'protected', setup: 'git -C "$WT" branch -q -m feat master', flags: '--apply --worktrees', inputs: {protected: true}},
      {name: 'fetchfail', setup: 'git -C "$R" remote set-url origin "$D/gone.git"', flags: '--apply --worktrees', inputs: {fetchOk: false}},
      {name: 'unmerged', setup: 'echo y > "$WT/y.txt"; git -C "$WT" add -A; git -C "$WT" commit -q -m unmerged', flags: '--apply --worktrees', inputs: {merged: false}},
      {name: 'locklive', setup: `git -C "$R" worktree lock --reason "claude agent a1 (pid ${process.pid} start x)" "$WT"`, flags: '--apply --worktrees', inputs: {lockLive: true}},
      {name: 'lockdead', setup: 'git -C "$R" worktree lock --reason "claude agent a1 (pid 999999 start x)" "$WT"', flags: '--apply --worktrees', inputs: {}},
      {name: 'indexfresh', setup: ': > "$R/.git/index.lock"', flags: '--apply --worktrees', inputs: {indexFree: false}},
      {name: 'indexold', setup: ': > "$R/.git/index.lock"; touch -t 202001010000 "$R/.git/index.lock"', flags: '--apply --worktrees', inputs: {indexFree: false}},
      {name: 'busy', setup: `( cd "$WT" && exec ${realSleep} 30 ) & echo $! > "$D/busy.pid"; ${realSleep} 0.3`, flags: '--apply --worktrees', inputs: {busy: true}},
    ]
    const f = worktreeSweep()
    // Without lsof the bash answers "not busy" by design (one NOTE): the busy case needs lsof to mean anything.
    const hasLsof = bash('command -v lsof >/dev/null', sb.env).status === 0
    let agree = 0
    for (const c of cases) {
      if (c.name === 'busy' && !hasLsof) continue
      const D = join(sb.dir, c.name)
      const out = bash(`
        D='${D}'; mkdir -p "$D"
        git init -q -b main "$D/seed"; echo base > "$D/seed/base.txt"; git -C "$D/seed" add -A; git -C "$D/seed" commit -q -m base
        git clone -q --bare "$D/seed" "$D/origin.git"; git clone -q "$D/origin.git" "$D/repo"; R="$D/repo"
        git -C "$R" remote set-head origin main >/dev/null 2>&1
        WT="$D/repo-wt"; git -C "$R" worktree add -q -b feat "$WT" main
        ${c.setup}
        ${c.name === 'busy' ? '' : 'export KIT_WRAP_SKIP_BUSY_CHECK=1'}
        bash '${KIT}/bin/wrap' apply ${c.flags} "$R" > "$D/out" 2>&1 </dev/null; rc=$?
        [ -f "$D/busy.pid" ] && kill "$(cat "$D/busy.pid")" 2>/dev/null
        removed=0; [ -e "$WT" ] || removed=1
        would=0; grep -q "WOULD remove worktree" "$D/out" && would=1
        # the worktree step's own branch delete (the later all-branches sweep is another rule's business)
        delbr=0; grep -q "\\[APPLY\\] delete .* worktree is gone" "$D/out" && delbr=1
        echo "RESULT $rc $removed $would $delbr"`, sb.env, sb.dir, 120_000)
      const m = /RESULT (\d+) (\d) (\d) (\d)/.exec(out.stdout)
      const real = {would: m?.[3] === '1', remove: m?.[2] === '1', deleteBranch: m?.[4] === '1'}
      const want = f.run({...BASE, ...c.inputs})
      if (JSON.stringify(real) !== JSON.stringify(want)) {
        return {agree, diverge: {case: c.name, bash: real, rule: want, out: bash(`tail -20 '${D}/out'`, sb.env).stdout}}
      }
      agree++
    }
    return {agree, diverge: null}
  } finally { sb.cleanup() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge(), null, 1))
