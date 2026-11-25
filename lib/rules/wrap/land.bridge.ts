// Bridge: `bin/wrap land` (the real verb, end to end) against land. It runs inside the kit's own wrap test harness
// (tests/lib/wrap-stub.sh: the gh stub that lands a merge on the bare origin, the fixture builders, a temp TMPD), so
// the fixture is the one the kit's tests trust. Each case scripts one outcome per step: the ship-gate passes or
// blocks (WRAP_LAND_SHIP_GATE), --draft, the merge succeeds or is refused (not CONFLICTING), GitHub does not report
// MERGED, the merge never reaches the default branch (the tree check cannot verify it), or the project's
// [merge] command refuses. Compared: the LAND: line's kind, the exit class (0, 3, or another refusal), whether
// the branch was pushed, whether a merge call succeeded, and whether the worktree is gone.
import {writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {bash, KIT, sandbox, type BridgeResult} from './bridge-util.ts'
import {land, KIND} from './land.ts'

type Case = {name: string, draft: boolean, events: string[], env: string, mergeRc0: boolean}
const CASES: Case[] = [
  {name: 'happy', draft: false, mergeRc0: true, env: 'LAND_SINK=1',
    events: ['gatePass', 'pushOk', 'prOk', 'checksOk', 'mergeOk', 'stateMerged', 'treeOk', 'tidyOk']},
  {name: 'gateblock', draft: false, mergeRc0: true, env: 'WRAP_LAND_SHIP_GATE="$BLOCK" LAND_SINK=1', events: ['gateBlock']},
  {name: 'draft', draft: true, mergeRc0: true, env: 'LAND_SINK=1', events: ['gatePass', 'pushOk', 'prOk']},
  {name: 'draftblock', draft: true, mergeRc0: true, env: 'WRAP_LAND_SHIP_GATE="$BLOCK" LAND_SINK=1', events: ['gateBlock']},
  {name: 'mergefail', draft: false, mergeRc0: false,
    env: `GH_STUB_MERGE_RC=1 GH_STUB_MERGE_ERR='Pull request is not mergeable: required status check' GH_STUB_PR_42="{\\"number\\":42,\\"headRefOid\\":\\"$TIP\\",\\"mergeable\\":\\"MERGEABLE\\",\\"mergeStateStatus\\":\\"BLOCKED\\"}" WRAP_MERGE_RETRY_SLEEP=0 LAND_SINK=1`,
    events: ['gatePass', 'pushOk', 'prOk', 'checksOk', 'mergeFail']},
  {name: 'notmerged', draft: false, mergeRc0: true, env: `GH_STUB_VIEW_STATE='{"state":"OPEN","mergeCommit":null}' LAND_SINK=1`,
    events: ['gatePass', 'pushOk', 'prOk', 'checksOk', 'mergeOk', 'stateNot']},
  {name: 'unverified', draft: false, mergeRc0: true, env: 'LAND_SINK=0',
    events: ['gatePass', 'pushOk', 'prOk', 'checksOk', 'mergeOk', 'stateMerged', 'treeBad']},
  {name: 'project', draft: false, mergeRc0: true,
    env: `KIT_CONFIG_OPERATOR="$OPDIR" GH_STUB_PR_42="{\\"number\\":42,\\"headRefOid\\":\\"$TIP\\"}" LAND_SINK=1`,
    events: ['gatePass', 'pushOk', 'prOk', 'checksOk', 'mergeProject']},
]

export async function bridge(): Promise<BridgeResult> {
  const sb = sandbox('land')
  try {
    // Each case's environment is a small file sourced with `set -a` inside the case's own subshell.
    for (const c of CASES) {
      writeFileSync(join(sb.dir, `env-${c.name}.sh`), [
        `GH_STUB_OPEN_PRS='[]'`, 'GH_STUB_CREATE_NUM=42', 'GH_STUB_LAND_REMOTE="$TMPD/ld-bare-$c"', 'GH_STUB_LAND_BRANCH=feat/land',
        'GH_STUB_LAND_DEF=main', ...c.env.split(/ (?=[A-Z_]+=)/), '[ "$LAND_SINK" = 1 ] && GH_STUB_LAND_REPO="$WT"', ':'].join('\n') + '\n')
    }
    const script = `
      KIT_DIR='${KIT}'; source "$KIT_DIR/tests/lib/wrap-stub.sh"
      BLOCK="$TMPD/block.sh"; printf '#!/usr/bin/env bash\\ncat >/dev/null\\necho "BLOCKED: fixture gate" >&2\\nexit 2\\n' > "$BLOCK"; chmod +x "$BLOCK"
      OPDIR="$TMPD/op-merge"; mkdir -p "$OPDIR"; printf '[merge]\\ncommand = "false"\\n' > "$OPDIR/kit.toml"
      printf 'the change\\n' > "$TMPD/body.md"
      for c in ${CASES.map((c) => `${c.name}:${c.draft ? 1 : 0}`).join(' ')}; do
        d="\${c#*:}"; c="\${c%%:*}"
        build_land "$c" >/dev/null 2>&1
        R="$TMPD/ld-repo-$c"; WT="$(cd "$R/wt" && pwd -P)"; TIP="$(git -C "$WT" rev-parse HEAD)"
        : > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
        FLAGS=""; [ "$d" = 1 ] && FLAGS="--draft --body-file $TMPD/body.md"
        out="$( ( set -a; source '${sb.dir}'/env-$c.sh; set +a; "$WRAP" land "$WT" $FLAGS ) 2>&1 </dev/null)"; rc=$?
        land_line="$(printf '%s\\n' "$out" | grep '^LAND: ' | tail -1)"
        pushed=0; printf '%s' "$out" | grep -q "pushed feat/land" && pushed=1
        merges="$(grep -c '^pr merge' "$GH_STUB_CALLS")"
        wt=1; [ -e "$WT" ] || wt=0
        echo "RESULT|$c|$rc|$land_line|$pushed|$merges|$wt"
      done`
    const out = bash(script, sb.env, sb.dir, 600_000)
    if (process.env.LAND_DEBUG) console.error(out.stdout.split("\n").filter((l) => l.startsWith("RESULT|")).join("\n"))
    const rows = out.stdout.split('\n').filter((l) => l.startsWith('RESULT|'))
    let agree = 0
    for (const c of CASES) {
      const row = rows.find((r) => r.split('|')[1] === c.name)
      if (!row) return {agree, diverge: {case: c.name, error: 'no result', stderr: out.stderr.slice(-800)}}
      const [, , rc, landLine, pushed, merges, wt] = row.split('|')
      const kind = /^LAND: (merged|already|draft|refused)/.exec(landLine)?.[1] ?? 'none'
      const real = {kind, rcClass: rc === '0' ? 0 : rc === '3' ? 3 : 1, pushed: pushed === '1', mergeOk: Number(merges) > 0 && c.mergeRc0, wtRemoved: wt === '0'}
      const r = land(), it = r.interpreter(), p = r.encodeParams({draft: c.draft})
      let st = it.init(p)
      for (const ev of c.events) st = it.step(p, st, r.encodeInput({ev}))
      const d = r.decode(st) as Record<string, any>
      const want = {kind: KIND[d.phase] ?? 'none', rcClass: d.phase === 'landed' || d.phase === 'draft' ? 0 : d.phase === 'mismatch' ? 3 : 1,
        pushed: d.pushed, mergeOk: d.mergeDone, wtRemoved: d.wtRemoved}
      if (JSON.stringify(real) !== JSON.stringify(want)) return {agree, diverge: {case: c.name, events: c.events, bash: {...real, rc, landLine}, rule: {...want, phase: d.phase}}}
      agree++
    }
    return {agree, diverge: null}
  } finally { sb.cleanup() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge(), null, 1))
