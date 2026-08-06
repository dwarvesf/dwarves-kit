#!/usr/bin/env bash
# tests/lib/contract-lint.sh -- shared no-orphan sweep primitive (grep-diff-against-manifest).
#
# Generalizes the pattern already proven by tests/test-docs-wiring.sh /
# tests/test-kri-wiring.sh / tests/test-command-emit-sweep.sh: a "site" (a call that OWES a
# paired call) must have its pair somewhere in the same file, or the site is an orphan. This
# file is a LIBRARY (sourced with `. tests/lib/contract-lint.sh`), no main, no side effects on
# source. SPEC-193 is its first caller (`tests/test-outcome-emit-sweep.sh`); the kit-hardening
# SG-08 registry lint is expected to reuse it (per the harness-loop goal file), so the
# interface is parameterized rather than baked to the OUTCOME-bracket case specifically.
#
# Portability: POSIX-ish sed -E (BSD sed on macOS, GNU sed on ubuntu). No -P (Perl regex,
# GNU-only), no `date -d`/`stat -f`. Every function is pure (reads files, writes stdout only).

# _site_phases <file> <site_regex>: print one phase-per-line for every match of <site_regex>
# in <file>. <site_regex> is a sed -E pattern whose LAST capture group is the phase token
# (bare word, or a double-quoted phrase kept WITH its quotes -- callers strip quotes via
# _unquote). No match in a file prints nothing (not an error; the caller decides what an
# empty phase set means).
_site_phases() {
  local file="$1" pattern="$2"
  sed -E -n "$pattern" "$file" 2>/dev/null
}

# _unquote <token>: strip one leading+trailing double-quote pair, if present. "UI design" ->
# UI design; build -> build (unchanged).
_unquote() {
  local t="$1"
  case "$t" in
    \"*\") t="${t#\"}"; t="${t%\"}" ;;
  esac
  printf '%s' "$t"
}

# _regex_escape <phase>: escape ERE metacharacters in a phase string so it can be spliced
# into a coverage regex literally. Phases in this repo are alnum/space/hyphen only, but this
# is defensive (a future phase name with a metachar must not corrupt the coverage check into
# a false pass).
_regex_escape() {
  printf '%s' "$1" | sed -E 's/[][(){}.*+?^$|\\]/\\&/g'
}

# manifest_diff_by_phase <dir> <glob> <site_sed_pattern> <coverage_regex_tmpl> <exempt_list>
#   <dir> <glob>            files to sweep, e.g. "commands" "*.md"
#   <site_sed_pattern>      a sed -E -n '...p' pattern; last capture group = phase token
#                            (quoted phrases keep their quotes; see _site_phases)
#   <coverage_regex_tmpl>   a grep -E pattern with a literal %PHASE% placeholder, substituted
#                            per phase (regex-escaped, optional surrounding quotes handled by
#                            the caller's own template, e.g. '\"?%PHASE%\"?')
#   <exempt_list>            newline-separated bare basenames (no extension); a file in this
#                            list is skipped entirely (no site or coverage check)
#
# For each swept file with >=1 site phase, checks EACH DISTINCT phase found also has >=1
# coverage-regex match in the SAME file. Prints one "ORPHAN: <file> (<phase>)" line per gap.
# Returns the orphan count (0 = clean). Coarseness, by design: this checks "does phase P have
# a coverage line ANYWHERE in the file", not "does the Nth site of P have its Nth coverage
# line" -- catching a totally-unbracketed phase (the bug class this exists for) without
# requiring a full per-occurrence pairing parser (that already lives in
# lib/stats/src/stats/adapters.py::read_kit_gates for the real FIFO pairing).
manifest_diff_by_phase() {
  local dir="$1" glob="$2" site_pattern="$3" cov_tmpl="$4" exempt="$5"
  local f base phase phase_bare cov_re orphans=0
  for f in "$dir"/$glob; do
    [ -f "$f" ] || continue
    base="$(basename "$f" .md)"
    printf '%s\n' "$exempt" | grep -qxF "$base" && continue
    local phases; phases="$(_site_phases "$f" "$site_pattern" | sort -u)"
    [ -n "$phases" ] || continue
    while IFS= read -r phase; do
      [ -n "$phase" ] || continue
      phase_bare="$(_unquote "$phase")"
      cov_re="${cov_tmpl//%PHASE%/$(_regex_escape "$phase_bare")}"
      if ! grep -qE "$cov_re" "$f"; then
        echo "  ORPHAN: $(basename "$f") ($phase_bare)"
        orphans=$((orphans + 1))
      fi
    done <<< "$phases"
  done
  return "$orphans"
}

# manifest_diff_flat <sweep_dirs> <extract_regex> <manifest_file> <allow_regex>
#   <sweep_dirs>      space-separated list of paths, e.g. "lib hooks bin" (word-split
#                     deliberately, so multiple roots pass through one `grep -r`)
#   <extract_regex>   a `grep -ohE` pattern swept recursively over <sweep_dirs>
#   <manifest_file>   the checked-in file each hit must appear in (word-bounded, not a bare
#                     substring match, so a short hit like "KIT" cannot be spuriously "covered"
#                     by a longer registered token like "KIT_LEDGER_DIR")
#   <allow_regex>     a `grep -E` pattern (matched against the normalized token alone); a hit
#                     matching this is treated as covered without needing a manifest row
#                     (SG-08's internal/test-fixture allowlist)
#
# The flat-SET sibling of manifest_diff_by_phase: that function pairs a site with its coverage
# IN THE SAME FILE (per-file phase pairing, e.g. commands/*.md's record/outcome brackets); this
# one diffs a SET of tokens swept from MANY files against ONE external manifest (SG-08: an env
# var can be read from any of lib/hooks/bin, but is registered exactly once in
# lib/config/module-registry.md, a different file entirely, so no per-file pairing applies).
# Prints one "ORPHAN: <token>" per uncovered hit. Returns the orphan count (0 = clean).
manifest_diff_flat() {
  local dirs="$1" extract_re="$2" manifest="$3" allow_re="$4"
  local hits token orphans=0 cov_re
  # shellcheck disable=SC2086  # deliberate word-split: dirs is a space-separated path list
  # -I skips binary files: without it grep emits "Binary file <x> matches" INTO the token
  # stream and a stray .pyc becomes a phantom ORPHAN (bit twice locally, 2026-07-12).
  hits="$(grep -rohEI --exclude-dir=__pycache__ --exclude='*.pyc' "$extract_re" $dirs 2>/dev/null | sed -E 's/^\$\{?//' | sort -u)"
  [ -n "$hits" ] || return 0
  while IFS= read -r token; do
    [ -n "$token" ] || continue
    if [ -n "$allow_re" ] && printf '%s' "$token" | grep -qE "$allow_re"; then continue; fi
    cov_re="(^|[^A-Za-z0-9_])$(_regex_escape "$token")([^A-Za-z0-9_]|\$)"
    if grep -qE "$cov_re" "$manifest" 2>/dev/null; then continue; fi
    echo "ORPHAN: $token"
    orphans=$((orphans + 1))
  done <<< "$hits"
  return "$orphans"
}
