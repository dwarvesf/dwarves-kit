#!/usr/bin/env python3
"""SPEC-405 negative controls: one named mutation of lib/wrap/wrap-merge.sh (run from the repo root)."""
import re
import sys

P = "lib/wrap/wrap-merge.sh"
M = {
    "AC-1": [('_pr_head_resync "$repo" "$url" "$conflict_n" "$c_head" "$c_oid" "$REMERGE_OID"; local rsc=$?', 'local rsc=1')],
    "AC-2": [('  if [ "$tip" != "$pushed" ]; then', '  if false; then')],
    "AC-3": [('      elif .isDraft != false then "isDraft is not false"\n', '')],
    "AC-4": [('      elif .state != "OPEN" then\n        "state " + ((.state // "") as $s | if $s == "CLOSED" or $s == "MERGED" then $s else "unreadable" end)\n', '')],
    "AC-5": [('      elif .state != "OPEN" then', '      elif (.state // "OPEN") != "OPEN" then')],
    "AC-6": [('if gh pr reopen "$n" --repo "$url" >/dev/null 2>&1; then rc=0; _RS_REOPENED=1; break; fi', 'gh pr reopen "$n" --repo "$url" >/dev/null 2>&1; rc=0; _RS_REOPENED=1; break')],
    "AC-7": [('  while [ "$tries" -lt 2 ]; do', '  while [ "$tries" -lt 1 ]; do')],
    "AC-8": [('[ "$rsc" -eq 0 ] && resynced=1', ':')],
    "AC-9": [('  gh pr close "$n" --repo "$url" >/dev/null 2>&1; rc=$?', '  gh pr close "$n" --repo "$url" --delete-branch >/dev/null 2>&1; rc=$?')],
    "AC-10": [("""'$3 == h && $1 != n { found = 1 } END { exit !found }' "$cache"; then
            echo "     no resync for #${conflict_n}: dependents open\"""", """'$3 == h && $1 != n { found = 1 } END { exit !found }' "$cache" && false; then
            echo "     no resync for #${conflict_n}: dependents open\"""")],
    "AC-11": [('  if [ "$rc" -ne 0 ]; then\n    # A close that errors', '  if false; then\n    # A close that errors')],
    "AC-15": [('    echo "     #${n} caught up on its own; no resync needed"\n    return 3', '    echo "     #${n} caught up on its own; no resync needed"\n    return 1')],
    "AC-16": [('      elif (has("autoMergeRequest") | not) or .autoMergeRequest != null then "auto-merge armed or unreadable"\n', '')],
    "AC-17": [("""awk -F'\\t' -v r="refs/heads/${branch}" '$2 == r { print $1 }'""", """awk -F'\\t' -v r="refs/heads/${branch}" 'NR == 1 { print $1 }'""")],
    "AC-18": [("  trap '_resync_trap' INT TERM HUP\n", '')],
    "AC-19": [('        echo "FAILED merge #${n}: close #${n} errored and its state is unreadable; if it is closed: gh pr reopen ${n} --repo ${_RS_PUB}" >&2\n        return 2 ;;', '        return 1 ;;')],
    "AC-20": [('      elif .isDraft != false then', '      elif (.isDraft // false) != false then')],
    "AC-21": [('(has("autoMergeRequest") | not) or .autoMergeRequest != null', '.autoMergeRequest != null')],
    "AC-22": [('  # The flag before the close\'s exit code: a handler that already ran owns the outcome.\n  [ -z "$_RS_HIT" ] || return 130\n', '')],
    "AC-23": [('      [ "$tries" -lt 3 ] || break', '      [ "$tries" -lt 1 ] || break')],
    # The three flag checks that stand before the close, all at once.
    "AC-24": [("RE", r'\n *\[ -z "\$_RS_HIT" \] \|\| return 130  # pre-close check:[^\n]*', '', 3)],
    "AC-25": [('  if [ -n "$_RS_HIT" ] && [ -n "$_RS_CLOSING" ] && [ -z "$_RS_REOPENED" ] \\\n', '  if false \\\n')],
    "AC-26": [('      elif .isCrossRepository != false then "a fork PR or unreadable"\n', '')],
    "AC-27": [('  if [ -z "$reason" ] && [ "$head" != "$prior" ]; then', '  if false; then')],
    "AC-28": [('    OPEN) echo "#${_RS_N} is still open after the interrupt; nothing to undo" >&2 ;;', '    OPEN) _resync_reopen_after_interrupt ;;')],
    "AC-29": [("_url_public() { printf '%s' \"$1\" | sed -E 's#^([A-Za-z][A-Za-z0-9+.-]*://)[^/]*@#\\1#'; }", "_url_public() { printf '%s' \"$1\"; }")],
    "AC-30": [('  _RS_HIT=""; _RS_CLOSING=""; _RS_REOPENED=""; _RS_COMMENT=""', '  _RS_CLOSING=""; _RS_REOPENED=""; _RS_COMMENT=""')],
    "AC-31": [('  if [ -n "$tt" ]; then eval "$tt"; else trap - TERM; fi\n', '')],
    "AC-32": [('      || echo "     comment on #${3} failed; the resync itself is unaffected"', '      || :')],
}

name = sys.argv[1]
s = open(P).read()
for edit in M[name]:
    if edit[0] == "RE":
        _, pat, new, want = edit
        s, n = re.subn(pat, new, s)
        if n != want:
            sys.exit(f"mutation {name}: expected {want} regex matches, found {n}")
        continue
    old, new = edit
    n = s.count(old)
    if n != 1:
        sys.exit(f"mutation {name}: expected 1 match, found {n}")
    s = s.replace(old, new)
open(P, "w").write(s)
