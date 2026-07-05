#!/usr/bin/env bash
# coverage-delta.sh -- ADVISORY coverage-delta gate (SPEC-130).
#
# For a behavioral diff, asks "did the test surface move the right way?" and WARNS when a
# change moves source lines but not test lines. It is ADVISORY by hard contract: it prints one
# `[coverage-delta]` line and ALWAYS exits 0. It can never block a push. It runs at the REVIEW
# phase (the cycle table's advisory enforcer), NOT in the ship-gate push blocker.
#
# The signal is a language-agnostic diff-line heuristic (open-fork 3): changed non-test SOURCE
# lines vs added/changed TEST lines in the same diff, portable across the kit's polyglot
# targets, with a hook to a real coverage runner where one is configured (COVERAGE_DELTA_RUNNER).
#
# Verdicts:
#   exempt   -- only docs / test / generated files changed (no behavioral source): nothing to flag.
#   ok       -- source AND test lines both moved: well-tested (the false-positive is avoided here).
#   WARNING  -- source lines moved, test lines did not: under-tested; names the uncovered files.
#
# Usage:
#   coverage-delta.sh check <root> [base] [--rid <rid>]   -> advisory line; ALWAYS exit 0
#   coverage-delta.sh class <path>                         -> docs|generated|test|source
#   coverage-delta.sh classes                              -> the four class names
#
# REUSE: the changed-files union mirrors lib/proof-ledger.sh:_changed (base..HEAD + working
# tree + staged + untracked); the base resolver mirrors hooks/ship-gate.sh:_resolve_base; the
# test globs mirror lib/explain.sh:_rank (anchored, so `latest-value.js` is not a test).
set -uo pipefail

CD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# --- base resolution (mirrors hooks/ship-gate.sh:_resolve_base, extended for master-default) ---
_default_branch() {
  local root="$1"
  # prefer the remote's advertised default, then origin/main, main, origin/master, master.
  local ref
  ref="$(git -C "$root" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"
  if [ -n "$ref" ]; then echo "$ref"; return; fi
  for c in origin/main main origin/master master; do
    git -C "$root" rev-parse --verify -q "$c" >/dev/null 2>&1 && { echo "$c"; return; }
  done
  echo master
}

_resolve_base() {
  local root="$1" def
  def="$(_default_branch "$root")"
  git -C "$root" merge-base HEAD "$def" 2>/dev/null || git -C "$root" rev-parse HEAD 2>/dev/null || true
}

# --- per-file classification (docs -> generated -> test -> source; first match wins) ---
classify_path() {
  local p="$1" lc bn
  lc="$(printf '%s' "$p" | tr 'A-Z' 'a-z')"
  bn="${lc##*/}"

  # docs: pure text/markup, never load-bearing behavior.
  case "$bn" in
    *.md|*.markdown|*.txt|*.rst|*.adoc) echo docs; return;;
  esac

  # generated: lockfiles, minified, protobuf output, vendored/third-party trees.
  case "$bn" in
    package-lock.json|pnpm-lock.yaml|yarn.lock|go.sum|cargo.lock|composer.lock|poetry.lock|gemfile.lock) echo generated; return;;
    *.min.js|*.min.css|*.pb.go|*.pb2.go|*_pb2.py|*.pb.py) echo generated; return;;
    *.generated.*) echo generated; return;;
  esac
  case "$lc" in
    vendor/*|*/vendor/*|node_modules/*|*/node_modules/*|*/dist/*|dist/*) echo generated; return;;
  esac

  # test: anchored globs (mirrors explain.sh:_rank rank-3; avoids `latest-value.js` false hits).
  case "$lc" in
    tests/*|*/tests/*|test/*|*/test/*|spec/*|*/spec/*|__tests__/*|*/__tests__/*) echo test; return;;
  esac
  case "$bn" in
    test-*|test_*|*_test.go|*_test.py|*_test.rb|*_test.js|*_test.ts) echo test; return;;
    *.test.js|*.test.jsx|*.test.ts|*.test.tsx|*.spec.js|*.spec.jsx|*.spec.ts|*.spec.tsx) echo test; return;;
    *_spec.rb|*test.java|*tests.cs|*tests.swift|*.t.sol) echo test; return;;
  esac

  # source: everything else that is a changed file (the behavioral surface).
  echo source
}

# --- changed files (mirrors proof-ledger.sh:_changed: base..HEAD + worktree + staged + untracked) ---
_changed_files() {
  local root="$1" base="$2"
  { git -C "$root" diff --name-only "$base"..HEAD 2>/dev/null
    git -C "$root" diff --name-only HEAD 2>/dev/null
    git -C "$root" diff --name-only --cached 2>/dev/null
    git -C "$root" ls-files --others --exclude-standard 2>/dev/null
  } | sort -u | sed '/^$/d'
}

# added+deleted line count for one path, across the same diff sources (numstat; binary = 0).
_lines_for() {
  local root="$1" base="$2" path="$3" n=0 a d
  # committed on the branch + working tree (untracked shows as all-added via /dev/null diff).
  while IFS=$'\t' read -r a d _rest; do
    [ "$a" = "-" ] && a=0; [ "$d" = "-" ] && d=0
    n=$((n + a + d))
  done < <(
    { git -C "$root" diff --numstat "$base"..HEAD -- "$path" 2>/dev/null
      git -C "$root" diff --numstat HEAD -- "$path" 2>/dev/null
      git -C "$root" diff --numstat --cached -- "$path" 2>/dev/null
    } 2>/dev/null
  )
  # untracked file: not in any diff above; count its non-empty lines as added.
  if [ "$n" -eq 0 ] && git -C "$root" ls-files --others --exclude-standard -- "$path" 2>/dev/null | grep -qxF "$path"; then
    n="$(grep -cvE '^[[:space:]]*$' "$root/$path" 2>/dev/null || echo 0)"
  fi
  printf '%s' "$n"
}

# --- the real-runner hook: defer to a configured coverage runner when present ---
# COVERAGE_DELTA_RUNNER, if set + executable, is called with the changed SOURCE files; its
# stdout verdict line is used in place of the heuristic. Its exit code is captured + reported
# but NEVER propagated (advisory is preserved regardless of the hook).
_run_runner() {
  local runner="$1"; shift
  local out rc
  out="$("$runner" "$@" 2>/dev/null)"; rc=$?
  printf '%s\n' "$out"
  return "$rc"   # captured by caller; never propagated to the gate's own exit
}

check() {
  local root="" base="" rid=""
  # parse: check <root> [base] [--rid <rid>]
  while [ $# -gt 0 ]; do
    case "$1" in
      --rid) rid="${2:-}"; shift 2;;
      *) if [ -z "$root" ]; then root="$1"; elif [ -z "$base" ]; then base="$1"; fi; shift;;
    esac
  done
  [ -n "$root" ] || { echo "usage: coverage-delta.sh check <root> [base] [--rid <rid>]" >&2; return 64; }
  [ -d "$root/.git" ] || root="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null || echo "$root")"
  [ -n "$base" ] || base="$(_resolve_base "$root")"

  local files f cls src_lines=0 test_lines=0 src_files="" ln
  files="$(_changed_files "$root" "$base")"

  # real-runner hook: only when configured AND executable.
  local runner="${COVERAGE_DELTA_RUNNER:-}"
  if [ -n "$runner" ] && [ -x "$runner" ]; then
    # gather changed source files for the runner.
    local src_for_runner=()
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      [ "$(classify_path "$f")" = source ] && src_for_runner+=("$f")
    done <<EOF
$files
EOF
    local rout rrc verdict
    rout="$(_run_runner "$runner" ${src_for_runner[@]+"${src_for_runner[@]}"})"; rrc=$?
    verdict="$(printf '%s' "$rout" | head -1)"
    echo "[coverage-delta] runner ${runner##*/}: ${verdict:-<no output>} (runner exit=$rrc; advisory, gate exit 0)"
    _record "$rid" "$root" "runner rc=$rrc"
    return 0
  fi

  # heuristic: sum source vs test lines.
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    cls="$(classify_path "$f")"
    case "$cls" in
      source)
        ln="$(_lines_for "$root" "$base" "$f")"
        if [ "${ln:-0}" -gt 0 ]; then
          src_lines=$((src_lines + ln))
          src_files="$src_files $f"
        fi
        ;;
      test)
        ln="$(_lines_for "$root" "$base" "$f")"
        test_lines=$((test_lines + ${ln:-0}))
        ;;
    esac
  done <<EOF
$files
EOF

  local verdict
  if [ "$src_lines" -eq 0 ]; then
    echo "[coverage-delta] exempt: no source change (docs/test/generated only)"
    verdict="exempt"
  elif [ "$test_lines" -eq 0 ]; then
    echo "[coverage-delta] WARNING under-tested: $src_lines source line(s) changed with no matching test change"
    echo "[coverage-delta]   uncovered:$src_files"
    verdict="warning"
  else
    echo "[coverage-delta] ok: source + test moved together (src=$src_lines test=$test_lines lines)"
    verdict="ok"
  fi
  _record "$rid" "$root" "$verdict src=$src_lines test=$test_lines"
  return 0
}

# record the advisory decision on the gate-ledger (only when a rid is given). Uses the existing
# `record` verb: an additive `| GATE | coverage-delta | ran |` line readers keying on known
# phases ignore. Best-effort; a record failure never affects the gate's exit.
_record() {
  local rid="$1" root="$2" note="$3"
  [ -n "$rid" ] || return 0
  bash "$CD_DIR/gate-ledger.sh" record "$rid" coverage-delta ran "$note" >/dev/null 2>&1 || true
}

main() {
  local sub="${1:-}"; shift 2>/dev/null || true
  case "$sub" in
    check)   check "$@";;
    class)   [ -n "${1:-}" ] || { echo "usage: coverage-delta.sh class <path>" >&2; return 64; }; classify_path "$1";;
    classes) printf 'docs\ngenerated\ntest\nsource\n';;
    *) echo "usage: coverage-delta.sh {check <root> [base] [--rid <rid>]|class <path>|classes}" >&2; return 64;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
