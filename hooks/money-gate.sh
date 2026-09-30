#!/bin/bash
# money-gate.sh -- PreToolUse(Edit|Write|MultiEdit) hook, function-named port of
# ops-toolkit's cc-money-gate (kit-foldin). Asks for confirmation when an edit inside
# a consumer-named financial repo (MONEY_GATE_REPOS) touches money/auth terms in the
# path or ANY string in the tool payload (the scan is recursive, so old_string and
# MultiEdit edits[] count: deleting a money line trips the gate as readily as adding
# one). Contract: lib/money-gate/SPEC.md; behavior pinned byte-for-byte against the
# Python original by tests/test-money-gate-parity.sh.
#
# Env:
#   MONEY_GATE_REPOS=a:b    sensitive repo names. CONSUMER CONFIG, no default: unset
#                           means the gate is inert (adapter-default invariant; the
#                           kit ships no tenant repo names)
#   MONEY_GATE_STRICT       ask-to-confirm instead of log-only. Any truthy spelling
#                           arms it (1/true/yes/on, trimmed, case-insensitive);
#                           0/false/no/off/empty stay log-only.
#   MONEY_GATE_LOG=FILE     log destination (default ~/.claude/logs/money-gate.log)
# Exit 0 always (the decision travels in the JSON, never the exit code).

set -euo pipefail
# Bytes, not locale characters: Claude Code passes the user's UTF-8 locale, under which
# the stock awk dies on a non-ASCII byte and gawk rejects byte ranges. The Python gate
# scanned codepoints; a non-ASCII byte pair is a separator under either reading.
export LC_ALL=C

[ -n "${MONEY_GATE_REPOS:-}" ] || exit 0
command -v jq >/dev/null 2>&1 || { echo "money-gate: jq not found; gate is off" >&2; exit 0; }

INPUT=$(cat) || exit 0

# Python truthiness, as the original's `or` chains used it: null, false, 0, "", [],
# and {} are falsy; every other value is truthy.
TRUTHY='def truthy: . != null and . != false and . != 0 and . != "" and . != [] and . != {};'

# stdin must be exactly one JSON object. The Python hook returned on a JSON error and
# crashed (its shim swallowing the crash) on a non-dict payload, a truthy non-dict
# tool_input, or a truthy non-string file_path; all of those exit 0 silently here,
# the same observable the shim produced. jq error() stands in for the Python crash.
# The output is file_path + \001 + cwd + "x": the sentinel byte survives command
# substitution so a payload carrying a trailing newline keeps it byte for byte.
raw=$(printf '%s' "$INPUT" | jq -rnj "$TRUTHY"'
  (input) as $o
  | if ([inputs] | length) > 0 then error          # a second JSON value: inert
    elif ($o | type) != "object" then error
    elif ($o.tool_input | truthy) and ($o.tool_input | type != "object") then error
    else (($o.tool_input | objects) // {}) as $ti
         | (if ($ti.file_path | truthy) then $ti.file_path
            elif ($ti.path | truthy) then $ti.path
            else "" end) as $f
         | if ($f | type) != "string" then error
           else $f, "\u0001", ($o.cwd | if type == "string" then . else "" end), "x" end
    end' 2>/dev/null) || exit 0
raw=${raw%x}
file_path=${raw%%$'\001'*}
cwd=${raw#*$'\001'}

haystack=$file_path$'\n'$cwd
IFS=':' read -r -a repos <<< "$MONEY_GATE_REPOS" || true
match=0
# ${a[@]+...}: bash 3.2 treats an empty array as unbound under set -u
for r in ${repos[@]+"${repos[@]}"}; do
  [ -n "$r" ] || continue
  # literal substring: quoting inside the pattern pins r down, so glob and regex
  # metacharacters in a repo name are data, never wildcards
  case "$haystack" in *"/$r/"*|*"/$r") match=1; break ;; esac
done
[ "$match" = 1 ] || exit 0

# Scanned text: file_path, then every string value under tool_input (recursive over
# objects and arrays, document order), joined by newlines. The scan works on bytes:
# lowercased, NUL mapped to \003 (awk truncates a record at NUL; both bytes are
# separators anyway). Two streams:
#   words: folding every non-[a-z0-9] run into \n leaves each candidate term on its
#          own line, boundaries built in, so the 24 one-word terms (including the
#          no-separator variants like apikey) are a hash lookup; the regex's greedy
#          "s?" is the word-minus-s still being a term.
#   variants: the 8 [_-]-joined terms (api_key, net-worth, ...) hide inside bigger
#          words, so they get a per-term split() gap walk, but only on lines that
#          contain [_-] at all. An index()+substr(rest) loop per match would copy
#          the tail once per hit: quadratic on a dense 1 MB line.
norm=$(printf '%s' "$INPUT" \
  | jq -rj --arg fp "$file_path" '$fp, (.tool_input | objects | .. | strings | "\n" + .)' 2>/dev/null \
  | tr 'A-Z\000' 'a-z\003') || exit 0

hits=$({
  printf '%s' "$norm" | tr -cs 'a-z0-9' '\n' | awk '
    BEGIN {
      nt = split("amount balance transfer payout payment payroll invoice wallet secret password token iban routing ledger cashflow pnl deposit withdraw usd vnd privatekey apikey accountnumber networth", T, " ")
      for (i = 1; i <= nt; i++) S[T[i]] = 1
    }
    $0 in S { print; next }
    {
      l = length($0)
      if (substr($0, l, 1) == "s" && substr($0, 1, l - 1) in S) print
    }'
  printf '%s' "$norm" | awk '
    function alnum(c) { return (c >= "0" && c <= "9") || (c >= "a" && c <= "z") }
    BEGIN {
      nv = split("api_key api-key private_key private-key account_number account-number net_worth net-worth", V, " ")
    }
    index($0, "_") == 0 && index($0, "-") == 0 { next }
    {
      line = $0
      for (k = 1; k <= nv; k++) {
        v = V[k]; vl = length(v)
        if (index(line, v) == 0) continue
        n = split(line, P, v)   # P[i] is the text between occurrence i-1 and i
        pos = 1
        for (i = 1; i < n; i++) {
          plen = length(P[i])
          ms = pos + plen          # 1-based start of this occurrence
          # left boundary: line start, or the gap ends on a non-alphanumeric byte.
          # An empty gap means the previous occurrence ends right before (alnum).
          ok = (ms == 1)
          if (!ok && plen > 0) ok = !alnum(substr(P[i], plen, 1))
          if (ok) {
            rest = P[i + 1]; rl = length(rest)
            # right boundary with the greedy "s?": "api_keys" reports api_keys.
            # An empty last gap means the variant ends the line.
            if (rl == 0) { if (i + 1 == n) print v }
            else {
              c = substr(rest, 1, 1)
              if (c == "s") {
                if (rl == 1) { if (i + 1 == n) print v "s" }
                else if (!alnum(substr(rest, 2, 1))) print v "s"
              } else if (!alnum(c)) print v
            }
          }
          pos = ms + vl
        }
      }
    }'
} | sort -u) || exit 0
[ -n "$hits" ] || exit 0

hits_csv=$(printf '%s\n' "$hits" | paste -sd, -)

# Log one line per fire, in both modes. MONEY_GATE_LOG is used verbatim when SET,
# even when empty; the default applies only when it is unset. An empty or slashless
# path has no directory part (makedirs("") fails in the original) and an unwritable
# directory never blocks the edit, so both cases write nothing anywhere.
# ~ falls back to the password database when HOME is unset (launchd, env -i), as
# Python's expanduser does; $HOME would trip set -u and lose the ask.
if [ "${MONEY_GATE_LOG+x}" = "x" ]; then logp=$MONEY_GATE_LOG; else logp=~/.claude/logs/money-gate.log; fi
dir=
case "$logp" in */*) dir=${logp%/*} ;; esac
if [ -n "$dir" ] && mkdir -p "$dir" 2>/dev/null; then
  # the group's 2>/dev/null covers the >> redirection failing too (a trailing-slash
  # or read-only logp): Python swallowed IsADirectoryError/PermissionError silently
  { printf '%s\t%s\t%s\n' "$(date +%s)" "$file_path" "$hits_csv" >> "$logp"; } 2>/dev/null || true
fi

# Any truthy spelling arms strict; the trim is str.strip()'s ([[:space:]] under
# LC_ALL=C: space, tab, newline, CR, VT, FF), then lowercase. The ask still prints
# when the log could not be written. The JSON is printed by hand, not via jq, so the
# ": " separator matches what the original's json.dumps emitted.
s=${MONEY_GATE_STRICT:-}
shopt -s extglob
s=${s##+([[:space:]])}
s=${s%%+([[:space:]])}
s=$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')
case "$s" in
  1|true|yes|on)
    first6=$(printf '%s\n' "$hits" | head -6 | paste -sd, -)
    printf '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": "money-gate: edit in a financial repo touches %s: confirm before applying."}}\n' "${first6//,/, }"
    ;;
esac
exit 0
