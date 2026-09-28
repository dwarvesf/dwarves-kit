#!/usr/bin/env bash
# spec-task-done.sh -- mark one verified task done in a spec and, optionally, log its run.
#
# /kit:execute step 2e checks a task off after each PASS verdict and appends a
# verification-log entry. Done by hand (sed, python heredocs) per task, both edits drift
# from the documented shape. This makes the two edits and nothing else: it NEVER commits.
# The caller commits the spec and the log together.
#
# Usage:
#   spec-task-done.sh <spec-path> <TASK-ID> --commit <sha>
#       [--verify-log <path> --command <cmd> --exit <n> --excerpt <text> --verdict <text>
#        [--reaudit <text>]]
#
# The flip:   `- [ ] TASK-3: title`  ->  `- [x] TASK-3 (DONE, commit <sha>, verified): title`
# It fails with a named error, changing nothing, when the ID has no unchecked line, is
# already checked, or has more than one unchecked line. TASK-1 never matches TASK-10.
#
# --verify-log appends this entry (the file is created with a `# Verification log` header
# when absent); --command, --exit, --excerpt and --verdict are then required:
#   ## TASK-3 title
#   - Command: `<cmd>`
#   - Exit: <n>
#   - Output (excerpt):
#     ```
#     <excerpt, each line indented two spaces>
#     ```
#   - Verdict: <text>
#   - Re-audit: <text>          (only with --reaudit)
set -euo pipefail

die()   { echo "spec-task-done: $*" >&2; exit 1; }
usage() { echo "usage: spec-task-done.sh <spec-path> <TASK-ID> --commit <sha> [--verify-log <path> --command <cmd> --exit <n> --excerpt <text> --verdict <text> [--reaudit <text>]]  (edits only, never commits: the caller commits both paths)" >&2; exit 64; }

[ $# -ge 2 ] || usage
spec="$1" id="$2"; shift 2
sha="" log="" cmd="" code="" excerpt="" verdict="" reaudit=""
have_cmd=0 have_code=0 have_excerpt=0 have_verdict=0 have_reaudit=0
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || { echo "spec-task-done: $1 needs a value" >&2; usage; }
  case "$1" in
    --commit)     sha="$2" ;;
    --verify-log) log="$2" ;;
    --command)    cmd="$2";     have_cmd=1 ;;
    --exit)       code="$2";    have_code=1 ;;
    --excerpt)    excerpt="$2"; have_excerpt=1 ;;
    --verdict)    verdict="$2"; have_verdict=1 ;;
    --reaudit)    reaudit="$2"; have_reaudit=1 ;;
    *) echo "spec-task-done: unknown option '$1'" >&2; usage ;;
  esac
  shift 2
done

# Validate everything before either file is touched, so a bad call leaves both unchanged.
[ -f "$spec" ] || die "spec not found: $spec"
case "$id" in ''|-*) usage ;; esac
case "$sha" in ''|*[!0-9a-f]*) die "--commit needs a hex commit sha (got '$sha')" ;; esac
[ "${#sha}" -ge 7 ] || die "--commit sha too short: '$sha' (want 7+ hex chars)"
if [ -n "$log" ]; then
  [ "$have_cmd" = 1 ] && [ "$have_code" = 1 ] && [ "$have_excerpt" = 1 ] && [ "$have_verdict" = 1 ] \
    || die "--verify-log needs --command, --exit, --excerpt and --verdict"
  case "$code" in ''|*[!0-9]*) die "--exit needs an integer exit code (got '$code')" ;; esac
elif [ $((have_cmd + have_code + have_excerpt + have_verdict + have_reaudit)) -gt 0 ]; then
  die "--command/--exit/--excerpt/--verdict/--reaudit only apply with --verify-log"
fi

# The temp file sits beside the spec so the final `mv` is an atomic rename; `cp -p` gives it
# the spec's mode first, and awk's `print > out` truncates it without resetting that mode.
tmp="$(mktemp "$spec.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
cp -p "$spec" "$tmp"

# One pass: count unchecked and checked lines for the ID, flip the single unchecked one
# into $tmp, and print its title. Prefix compare with substr, never a regex, so an ID
# needs no escaping; the char after the ID must end it, so TASK-1 never hits TASK-10.
rc=0
title="$(awk -v id="$id" -v sha="$sha" -v out="$tmp" '
  function has(line, box,   s, p, c) {
    s = line; sub(/^[ \t]*/, "", s)
    p = "- [" box "] " id
    if (substr(s, 1, length(p)) != p) return 0
    c = substr(s, length(p) + 1, 1)
    return c == "" || c == ":" || c == " " || c == "("
  }
  { lines[NR] = $0
    if (has($0, " ")) { open++; at = NR }
    else if (has($0, "x") || has($0, "X")) done++ }
  END {
    if (open == 0) exit (done ? 4 : 3)
    if (open > 1) exit 5
    for (i = 1; i <= NR; i++) {
      if (i == at) {
        p = "- [ ] " id; k = index(lines[i], p)
        tail = substr(lines[i], k + length(p))
        lines[i] = substr(lines[i], 1, k - 1) "- [x] " id " (DONE, commit " sha ", verified)" tail
        t = tail
        if (index(t, ":")) sub(/^[^:]*:/, "", t)
        gsub(/^[ \t]+|[ \t]+$/, "", t)
      }
      print lines[i] > out
    }
    print t
  }' "$spec")" || rc=$?
case "$rc" in
  0) ;;
  3) die "$id not found in $spec" ;;
  4) die "$id is already checked in $spec" ;;
  5) die "$id has more than one unchecked line in $spec" ;;
  *) die "awk failed ($rc) reading $spec" ;;
esac

mv -f "$tmp" "$spec"
echo "spec-task-done: checked $id in $spec"

[ -n "$log" ] || exit 0
mkdir -p "$(dirname "$log")"
[ -f "$log" ] || printf '# Verification log\n' > "$log"
# Captured output can itself hold a ``` line; a longer fence keeps it from closing early.
fence='```'; case "$excerpt" in *'```'*) fence='````' ;; esac
{
  printf '\n## %s %s\n' "$id" "$title"
  printf -- '- Command: `%s`\n' "$cmd"
  printf -- '- Exit: %s\n' "$code"
  printf -- '- Output (excerpt):\n  %s\n' "$fence"
  printf '%s\n' "$excerpt" | sed 's/^/  /'
  printf '  %s\n' "$fence"
  printf -- '- Verdict: %s\n' "$verdict"
  [ "$have_reaudit" = 0 ] || printf -- '- Re-audit: %s\n' "$reaudit"
} >> "$log"
echo "spec-task-done: logged $id to $log (not committed: commit both paths)"
