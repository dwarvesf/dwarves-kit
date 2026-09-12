#!/usr/bin/env bash
# boundary-lint.sh -- the engine never names a consumer, by path or by
# skill (learning-boundary). Two checks, both read-only, both grep-with-an-allowlist.
#
# PATH: all of lib/ and hooks/ (minus four modules named below), commands/, tests/, kit.toml
# for a hardcoded dotfiles or ops-toolkit path -- the shape behind the PR #554 regression (a
# kit test reached into the operator's dotfiles by absolute path); tests/test-weekend-batch.sh
# already pins the same `dotfiles/home` pattern as its own precedent. Excluded:
# lib/{plugin-check,webcheck,sync,stats}/ -- each carries real, unrelated "graduated/migrated
# from ops-toolkit/tools/X" provenance prose in its own README/SPEC/docs (verified: measured
# 20+ such hits, zero of them a live path any code reads), which this lint has no mandate to
# rewrite. A hit in any OTHER module is real; see the engine-learn-seam spec for the
# full rationale and why a wider net there would break green on introduction.
#
# NAME: an explicit, small file list (the seam-adjacent surfaces this repo owns) for a
# hardcoded consumer-skill name that should route through a config seam instead. NOT a
# directory-wide scan: `narrate-log`/`deep-understand`/etc. have real, unrelated, legitimate
# hits elsewhere (commands/pitch.md composes narrate-log for an unrelated feature;
# tests/test-wrap.sh uses "learning-ledger" as generic fixture text). See
# the engine-learn-seam spec.
#
# name_files/name_re are a hand-maintained list, not derived from lib/config/module-
# registry.md's "## Seams" table: that table's Filled-by column is free-text prose ("the
# operator, for a skill that must read...") naming who fills a seam, not the compact retired-
# skill names this check greps for, so deriving one from the other would not be meaningful.
set -euo pipefail
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ROOT is resolved to an absolute realpath (`cd ... && pwd`) even when passed relative (e.g.
# `boundary-lint.sh .`): the self-exclusion below matches grep hits by "$SELF/boundary-
# lint.sh:" prefix, which only lines up when ROOT and SELF share the same absolute form --
# a relative ROOT made grep emit "./lib/gate/boundary-lint.sh:" lines that never matched,
# so the lint flagged its own PATH-check example lines.
ROOT="$(cd "${1:-$SELF/../..}" && pwd)"
fail=0
flag() { printf 'boundary-lint: %s\n' "$1" >&2; fail=1; }

path_re='dotfiles/home|ops-toolkit/(tools|_meta)/'
path_excl=(--exclude-dir=plugin-check --exclude-dir=webcheck --exclude-dir=sync --exclude-dir=stats)
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  flag "consumer path hardcoded: $hit"
done < <(grep -rnE "${path_excl[@]}" "$path_re" \
  "$ROOT/lib" "$ROOT/hooks" "$ROOT/commands" "$ROOT/tests" "$ROOT/kit.toml" 2>/dev/null \
  | grep -v "^$SELF/boundary-lint.sh:" || true)

# Retired/pedagogy skill names (ROADMAP.md "Retired words" + the two names that migration moved
# behind the seam), checked only where this repo could plausibly still hardcode one.
name_re='narrate-log|svg-knowledge-diagram|deep-understand|dev-learner|session-closeout|session-distill|learning-ledger'
# Every commands/*.md file, not the three that existed when this list was written: a NEW
# command file hardcoding a retired name previously stayed green (the finding this closes).
# pitch.md is the one documented exception: it composes `narrate-log` for an unrelated
# feature (a real, legitimate hit, not a boundary violation), so it is excluded by name
# rather than silently dropped by a narrower glob.
name_files=("$ROOT/kit.toml" "$ROOT/lib/gate/quiz-gate.sh" "$ROOT/lib/gate/README.md")
while IFS= read -r -d '' f; do
  [ "$(basename "$f")" = "pitch.md" ] && continue
  name_files+=("$f")
done < <(find "$ROOT/commands" -maxdepth 1 -name '*.md' -print0 2>/dev/null)
while IFS= read -r -d '' f; do name_files+=("$f"); done \
  < <(find "$ROOT/lib/reflect" -type f -print0 2>/dev/null)

while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  flag "consumer skill named directly: ${hit#"$ROOT/"}"
done < <(grep -nE "$name_re" "${name_files[@]}" 2>/dev/null || true)

[ "$fail" = 0 ] && echo "boundary-lint: PASS"
exit "$fail"
