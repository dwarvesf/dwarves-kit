#!/usr/bin/env bash
# mutation-smoke.sh -- ADVISORY mutation smoke (SPEC-131, kit-run-integrity SG-04).
#
# The HONESTLY-PROVEN check that coverage-delta (SG-03) cannot be: coverage sees whether a
# changed line HAS a test near it; this asks whether that test actually BITES. It mutates a
# line in the CHANGED code and re-runs the suite. A biting suite (the mutation is caught ->
# the suite goes red) is quiet; a NON-biting suite (the mutation survives -> the suite stays
# green on broken code) is FLAGGED as a false proof. This is the check task-verifier is
# structurally unable to be (it trusts a green result; it cannot ask "would green survive a
# subtly-wrong line?").
#
# ADVISORY BY CONTRACT (gate-zero, warn-only): every terminal path exits 0. A flag is a stderr
# WARN + an additive `| MUTATION |` ledger marker. It sets no gate, blocks no push, and is wired
# OFF the push blocker. A block would need the operator's bless; the default is warn-only.
#
# CHEAP + BOUNDED (open-fork 4): a small FIXED operator set on the CHANGED HUNKS ONLY, first
# surviving mutation flags and stops, at most MUTATION_SMOKE_MAX (default 5) mutations attempted.
# NOT a full mutation-testing sweep.
#
# SAFE: the target file is mutated IN PLACE (the suite runs against the real tree), but its exact
# bytes are backed up first and restored after every run; an EXIT/INT/TERM trap restores an
# in-flight mutation, so an interrupt cannot leave mutated code behind. The tree is byte-identical
# after a run (proven by test).
#
# PORTABLE (macOS BSD + ubuntu GNU, bash 3.2): no `sed -i` (rewrite via a sed head/tail split +
# printf), no `stat -f`/`date -r`, no `\b`/`[[:<:]]` word-boundary regex (literal-substring
# operators only), no associative arrays.
#
# Usage:
#   mutation-smoke.sh run [<base-ref>]     -> run the smoke; always exits 0 (advisory)
#   mutation-smoke.sh candidates [<base>]  -> list mutation candidates (file<TAB>line<TAB>orig<TAB>mut)
#   mutation-smoke.sh detect-cmd           -> print the detected test command (or empty)
#   mutation-smoke.sh mutate-line "<line>" -> print the mutated form of one line (or empty if none)
#
# Env:
#   MUTATION_SMOKE_BASE      base git ref for the diff (default: merge-base w/ origin/master, else HEAD)
#   MUTATION_SMOKE_TEST_CMD  override the detected test command
#   MUTATION_SMOKE_MAX       cap on mutations attempted (default 5)
#   MUTATION_SMOKE_RID       run id for the ledger marker (default: gate-ledger.sh rid)

set -uo pipefail   # NB: no -e; the whole point is to run a suite that may fail and keep going.

MS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
MAX="${MUTATION_SMOKE_MAX:-5}"

# --- portability + safety helpers -------------------------------------------------------------

# Rewrite a single line (1-based) of a file, portably. No `sed -i`. n=1 and last-line safe:
# BSD sed rejects line address 0, so the head slice is skipped when n==1.
_replace_line() {  # <file> <lineno> <new-content>
  local f="$1" n="$2" new="$3" tmp
  tmp="$(mktemp)"
  {
    [ "$n" -gt 1 ] && sed -n "1,$((n-1))p" "$f"
    printf '%s\n' "$new"
    sed -n "$((n+1)),\$p" "$f"
  } > "$tmp"
  cp "$tmp" "$f"
  rm -f "$tmp"
}

# Restore an in-flight mutation on interrupt/exit, then clean up backups.
CUR_FILE=""; CUR_BK=""
_cleanup() {
  if [ -n "$CUR_BK" ] && [ -f "$CUR_BK" ] && [ -n "$CUR_FILE" ]; then
    cp "$CUR_BK" "$CUR_FILE" 2>/dev/null || true
  fi
  [ -n "$CUR_BK" ] && rm -f "$CUR_BK" 2>/dev/null || true
  CUR_FILE=""; CUR_BK=""
}

# --- mutation operator set (small, fixed, literal-substring, portable) -------------------------
# Exactly one operator applied to the first matching occurrence on a line. Order: most-specific
# relational first, then logical, then arithmetic, then status. All literal (no word-boundary
# regex) so BSD and GNU sed agree byte-for-byte.
mutate_line() {  # <line> -> mutated line on stdout (empty if no operator applies)
  local l="$1"
  case "$l" in
    *"=="*)       printf '%s' "$l" | sed 's/==/!=/'      ; return 0 ;;
    *"!="*)       printf '%s' "$l" | sed 's/!=/==/'      ; return 0 ;;
    *">="*)       printf '%s' "$l" | sed 's/>=/</'       ; return 0 ;;
    *"<="*)       printf '%s' "$l" | sed 's/<=/>/'       ; return 0 ;;
    *" && "*)     printf '%s' "$l" | sed 's/ && / || /'  ; return 0 ;;
    *" || "*)     printf '%s' "$l" | sed 's/ || / \&\& /'; return 0 ;;
    *"return 0"*) printf '%s' "$l" | sed 's/return 0/return 1/' ; return 0 ;;
    *"return 1"*) printf '%s' "$l" | sed 's/return 1/return 0/' ; return 0 ;;
    *"exit 0"*)   printf '%s' "$l" | sed 's/exit 0/exit 1/'     ; return 0 ;;
    *" + "*)      printf '%s' "$l" | sed 's/ + / - /'    ; return 0 ;;
    *" - "*)      printf '%s' "$l" | sed 's/ - / + /'    ; return 0 ;;
  esac
  return 0   # no operator: empty output
}

# A comment-only line is a semantic no-op under mutation -> it would always survive -> a false
# flag. Skip lines whose first non-blank char starts a comment (#, //, *). Documented noise:
# mutations inside strings/comments mid-line remain possible (accepted for an advisory smoke).
_is_comment() {  # <line> -> 0 if comment-only
  local t; t="$(printf '%s' "$1" | sed 's/^[[:space:]]*//')"
  case "$t" in ''|'#'*|'//'*|'*'*) return 0 ;; *) return 1 ;; esac
}

# A code file worth mutating? Exclude tests, docs, and generated/meta paths so the smoke mutates
# the CODE under test, never the tests themselves (a mutated test proves nothing about bite).
_is_code_file() {  # <path> -> 0 if mutable code
  case "$1" in
    */tests/*|tests/*|*/test-*|test-*|*_test.*|*.test.*|*-test.*) return 1 ;;
    *docs/*|*.md|*.markdown|*.txt) return 1 ;;
    */fixtures/*|fixtures/*|*/specs/*|specs/*) return 1 ;;
    *) return 0 ;;
  esac
}

# --- base ref + changed hunks ------------------------------------------------------------------

_base_ref() {
  if [ -n "${MUTATION_SMOKE_BASE:-}" ]; then printf '%s' "$MUTATION_SMOKE_BASE"; return 0; fi
  local mb
  mb="$(git merge-base HEAD origin/master 2>/dev/null || true)"
  [ -n "$mb" ] && { printf '%s' "$mb"; return 0; }
  printf '%s' HEAD   # no upstream: diff the working tree
}

_changed_code_files() {  # <base>
  git diff --name-only "$1" -- . 2>/dev/null | while IFS= read -r f; do
    [ -f "$f" ] || continue
    _is_code_file "$f" && printf '%s\n' "$f"
  done
}

# Emit "file<TAB>newlineno<TAB>content" for each ADDED line in the changed hunks of a code file.
# New-file line numbers are tracked off the `@@ -a,b +c,d @@` header: added (+) and context ( )
# lines advance the new counter, deleted (-) lines do not.
_added_lines() {  # <base> <file>
  git diff --unified=0 "$1" -- "$2" 2>/dev/null | awk -v f="$2" '
    /^@@/ { if (match($0, /\+[0-9]+/)) { n = substr($0, RSTART+1, RLENGTH-1) + 0 } ; next }
    /^\+\+\+/ { next }
    /^\+/ { print f "\t" n "\t" substr($0, 2); n++ ; next }
    /^-/  { next }
    /^ /  { n++ ; next }
  '
}

# Build the candidate list: (file, lineno, orig, mutated) for added, non-comment, mutable lines.
candidates() {  # [<base>]
  local base; base="$(_base_ref)"
  local file
  _changed_code_files "$base" | while IFS= read -r file; do
    _added_lines "$base" "$file" | while IFS="$(printf '\t')" read -r fpath lineno content; do
      _is_comment "$content" && continue
      local mut; mut="$(mutate_line "$content")"
      [ -n "$mut" ] || continue
      [ "$mut" = "$content" ] && continue
      printf '%s\t%s\t%s\t%s\n' "$fpath" "$lineno" "$content" "$mut"
    done
  done
}

# --- test runner detection (reuse the verifier's approach; do not invent a runner) -------------

detect_cmd() {
  if [ -n "${MUTATION_SMOKE_TEST_CMD:-}" ]; then printf '%s' "$MUTATION_SMOKE_TEST_CMD"; return 0; fi
  if [ -f package.json ] && grep -q '"test"[[:space:]]*:' package.json 2>/dev/null; then
    printf '%s' 'npm test'; return 0; fi
  if [ -f go.mod ]; then printf '%s' 'go test ./...'; return 0; fi
  if [ -f pyproject.toml ] || [ -f setup.py ] || [ -f pytest.ini ]; then printf '%s' 'pytest'; return 0; fi
  if [ -f Cargo.toml ]; then printf '%s' 'cargo test'; return 0; fi
  if [ -f Makefile ] && grep -q '^test:' Makefile 2>/dev/null; then printf '%s' 'make test'; return 0; fi
  if [ -d tests ] && ls tests/test-*.sh >/dev/null 2>&1; then
    printf '%s' 'for t in tests/test-*.sh; do bash "$t" || exit 1; done'; return 0; fi
  printf '%s' ''   # no runner
}

_run_suite() {  # <cmd> -> exit code of the suite (0 = green)
  ( eval "$1" ) >/dev/null 2>&1
}

# --- ledger marker (best-effort; additive | MUTATION | line) ----------------------------------

_record() {  # <verdict> [k=v ...]
  local rid; rid="${MUTATION_SMOKE_RID:-$(bash "$MS_DIR/gate-ledger.sh" rid 2>/dev/null || echo mutation-smoke)}"
  bash "$MS_DIR/gate-ledger.sh" mutation "$rid" "verdict=$1" "${@:2}" 2>/dev/null || true
}

# --- the smoke ---------------------------------------------------------------------------------

run() {  # [<base>]
  [ -n "${1:-}" ] && MUTATION_SMOKE_BASE="$1"
  trap '_cleanup' EXIT INT TERM

  local cmd; cmd="$(detect_cmd)"
  if [ -z "$cmd" ]; then
    echo "[MUTATION-SMOKE] SKIP: no test runner detected (advisory, nothing to prove)" >&2
    _record skip reason=no-runner
    return 0
  fi

  # Collect candidates first: if there is nothing to mutate, skip before paying for a suite run.
  local cand_file; cand_file="$(mktemp)"
  candidates > "$cand_file"
  if [ ! -s "$cand_file" ]; then
    echo "[MUTATION-SMOKE] SKIP: no mutable changed code lines (only tests/docs, or no operator match)" >&2
    _record skip reason=no-candidates
    rm -f "$cand_file"; return 0
  fi

  # Baseline: the suite must be green, or bite is unanswerable (red could be pre-existing).
  if ! _run_suite "$cmd"; then
    echo "[MUTATION-SMOKE] SKIP: baseline suite is not green; cannot distinguish bite from pre-existing red" >&2
    _record skip reason=baseline-red
    rm -f "$cand_file"; return 0
  fi

  local attempts=0 file lineno orig mut rc
  while IFS="$(printf '\t')" read -r file lineno orig mut; do
    [ "$attempts" -ge "$MAX" ] && break
    [ -f "$file" ] || continue
    [ -L "$file" ] && continue   # SPEC-134: never mutate through a symlink (defense-in-depth)
    attempts=$((attempts+1))

    CUR_FILE="$file"; CUR_BK="$(mktemp)"; cp "$file" "$CUR_BK"
    _replace_line "$file" "$lineno" "$mut"
    if _run_suite "$cmd"; then rc=0; else rc=1; fi   # 0 = suite stayed GREEN (mutation SURVIVED)
    cp "$CUR_BK" "$file"; rm -f "$CUR_BK"; CUR_FILE=""; CUR_BK=""

    if [ "$rc" -eq 0 ]; then
      # SURVIVOR: the suite stayed green on mutated code -> it does not bite here. Flag + stop.
      echo "[MUTATION-SMOKE] WARN: suite did NOT bite -- a mutation survived (a possible false proof)." >&2
      echo "[MUTATION-SMOKE]   file: $file:$lineno" >&2
      echo "[MUTATION-SMOKE]   was:  $orig" >&2
      echo "[MUTATION-SMOKE]   mut:  $mut" >&2
      echo "[MUTATION-SMOKE]   (advisory: exit 0, nothing blocked. The suite runs this line but asserts nothing the mutation breaks.)" >&2
      _record flag "file=$(printf '%s' "$file" | tr ' ' '_')" "line=$lineno" "attempts=$attempts"
      rm -f "$cand_file"; return 0
    fi
    # CAUGHT: the suite went red -> it bit this mutation. Good; keep probing up to the cap.
  done < "$cand_file"

  echo "[MUTATION-SMOKE] OK: suite bit every attempted mutation ($attempts tried, cap $MAX) -- it appears to bite." >&2
  _record clean "attempts=$attempts"
  rm -f "$cand_file"; return 0
}

main() {
  local sub="${1:-}"; shift 2>/dev/null || true
  case "$sub" in
    run)         run "$@" ;;
    candidates)  candidates "$@" ;;
    detect-cmd)  detect_cmd ;;
    mutate-line) mutate_line "${1:-}" ;;
    *) echo "usage: mutation-smoke.sh {run [base]|candidates [base]|detect-cmd|mutate-line \"<line>\"}" >&2; return 64 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
