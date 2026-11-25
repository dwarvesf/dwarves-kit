// Bridge: lib/wrap/wrap-common.sh:_merge_pr against the merge-dispatch decision. The real _merge_pr is sourced (the
// whole wrap library, through lib/wrap/wrap.sh with no verb); the two readers it calls and the two ways it merges are
// replaced by shell functions that record the call, so the bridge sees exactly which way the bash went and what it set
// WRAP_MERGE_PROJECT to. Every combination of {repo dir, slug, neither} x {set, unset, unreadable (rc 2), rc 3}.
import {bash, KIT, sandbox, type BridgeResult} from './bridge-util.ts'
import {mergeDispatch} from './merge-dispatch.ts'

export async function bridge(): Promise<BridgeResult> {
  const sb = sandbox('merge-dispatch')
  const f = mergeDispatch()
  try {
    const cases: {hasRepo: boolean, hasSlug: boolean, rc: number}[] = []
    for (const hasRepo of [true, false]) for (const hasSlug of [true, false]) for (const rc of [0, 1, 2, 3]) cases.push({hasRepo, hasSlug, rc})
    const script = `
      source '${KIT}/lib/wrap/wrap.sh' >/dev/null 2>&1
      kit_merge_command() { echo "read:repo" >> "$LOG"; [ "$MC_RC" = 0 ] && printf 'bash scripts/m.sh'; return "$MC_RC"; }
      kit_merge_command_slug() { echo "read:slug" >> "$LOG"; [ "$MC_RC" = 0 ] && printf 'bash scripts/m.sh'; return "$MC_RC"; }
      kit_merge_exec() { echo "ran:project" >> "$LOG"; return 0; }
      _gh_merge_retry() { echo "ran:plain" >> "$LOG"; return 0; }
      for c in ${cases.map((c) => `${c.hasRepo ? 1 : 0}:${c.hasSlug ? 1 : 0}:${c.rc}`).join(' ')}; do
        IFS=: read -r hr hs MC_RC <<< "$c"; : > "$LOG"
        repo=""; slug=""; [ "$hr" = 1 ] && repo="$TMPDIR"; [ "$hs" = 1 ] && slug="o/r"
        _merge_pr 7 https://github.com/o/r deadbeef "$repo" "$slug" main >/dev/null 2>&1; rc=$?
        echo "$c|$rc|$WRAP_MERGE_PROJECT|$(paste -sd, "$LOG")"
      done`
    const out = bash(script, {...sb.env, LOG: `${sb.dir}/log`}, sb.dir)
    const rows = out.stdout.trim().split('\n')
    let agree = 0
    for (let i = 0; i < cases.length; i++) {
      const c = cases[i]
      const [, rc, flag, log] = (rows[i] ?? '').split('|')
      const real = {plain: log?.includes('ran:plain') ?? false, project: log?.includes('ran:project') ?? false,
        refuse: !(log?.includes('ran:') ?? false) && rc !== '0', projectFlag: flag === '1'}
      const read = c.rc === 0 ? 'set' : c.rc === 1 ? 'unset' : 'unreadable'
      const want = f.run({hasRepo: c.hasRepo, hasSlug: c.hasSlug, read})
      if (JSON.stringify(real) !== JSON.stringify(want)) return {agree, diverge: {case: c, bash: {rc, flag, log}, rule: want}}
      agree++
    }
    return {agree, diverge: null}
  } finally { sb.cleanup() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
