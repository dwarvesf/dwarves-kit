#!/usr/bin/env bash
# proof-ledger.sh -- the proof-of-done ship/merge gate (diff-keyed, spec-independent).
#
# Turns the proof-of-done convention (docs/verification/README.md) from advice into a
# wall: a load-bearing change cannot ship/merge without a matching proof-of-done entry.
# Unlike the lane gate (gate-ledger.sh), this keys off the BRANCH DIFF, not a spec, so it
# fires the same whether the work came through /kit:execute or a freeform /goal loop.
#
# A change's PROOF CLASS comes from its diff (consistent with lib/proof-gate.sh):
#   stateful   -- deploy / migration / data / persistent-state paths or commit subjects.
#                 Pass = a fresh verification entry with a recorded run AND a rollback
#                 note (or [UNAVAILABLE: reason]).
#   behavioral -- changes behavior (code/lib/commands/agents/hooks/tests).
#                 Pass = a fresh verification entry with a green run AND a NEGATIVE CONTROL.
#   inert      -- docs / comments / cosmetic (markdown-only diff). Pass (no ritual).
#
# "Fresh" = the branch diff itself added/modified the docs/verification/*.md entry, so an
# old proof from unrelated work does not satisfy a new change.
#
# An explicit, LOGGED override always exists (never a silent bypass).
#
# FAILS OPEN on genuine ambiguity (no repo, empty diff, no base, missing tooling): a gate
# bug must never block unrelated work. Exit 1 from `check` = block.
#
# Subcommands:
#   classify <root> <base>            print inert|behavioral|stateful for the branch diff
#   check    <root> <base> [slug]     exit 0 if the proof requirement is met (or overridden
#                                     or inert); else exit 1 + what is missing
#   override <slug> <reason>          log a human override for this branch (leaves a trace)
#   is-overridden <slug>              exit 0 if an override is logged
set -uo pipefail

PROOF_LEDGER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"
OVERRIDE_LOG="$LOG_DIR/proof-overrides.log"

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
slugify() { printf '%s' "$1" | tr '/ ' '--' | tr -cd '[:alnum:]._-'; }

# changed files on the branch (base..HEAD), plus working-tree changes so a not-yet-
# committed proof still counts during an interactive build.
_changed() {
  local root="$1" base="$2"
  { git -C "$root" diff --name-only "$base"..HEAD 2>/dev/null
    git -C "$root" diff --name-only HEAD 2>/dev/null
    git -C "$root" diff --name-only --cached 2>/dev/null
    git -C "$root" ls-files --others --exclude-standard 2>/dev/null
  } | sort -u | sed '/^$/d'
}

_subjects() { git -C "$1" log "$2"..HEAD --format='%s' 2>/dev/null || true; }

classify() {
  local root="${1:-}" base="${2:-}"
  [ -n "$root" ] && [ -n "$base" ] || { echo "usage: classify <root> <base>" >&2; return 64; }
  local changed subjects blob
  changed="$(_changed "$root" "$base")"
  [ -n "$changed" ] || { echo inert; return 0; }   # empty diff: nothing to gate

  # inert FIRST: a markdown/txt-only diff is docs, never load-bearing, regardless of what the
  # commit subject says. Checking stateful keywords against the subject before this misread a
  # markdown-only "migrate" doc change as stateful (see SPEC-046, the classify-md-inert dogfood).
  if [ -z "$(printf '%s\n' "$changed" | grep -vE '\.(md|txt|markdown)$')" ]; then
    echo inert; return 0
  fi

  subjects="$(_subjects "$root" "$base")"
  blob="$(printf '%s\n%s' "$changed" "$subjects" | tr 'A-Z' 'a-z')"
  # stateful: deploy / migration / data / persistent-state signals (only reached when the diff
  # touches non-doc files, so a docs-only commit can no longer be misclassified by its subject).
  if printf '%s' "$blob" | grep -qE 'deploy|rollout|production|migrat|schema|data[ -]model|database|/db/|\bseed\b|backup|restore|persistent|drop .*(table|column)|alter table|data loss'; then
    echo stateful; return 0
  fi
  echo behavioral
}

# the verification-log files this branch added/modified (excludes the convention README).
# Two accepted shapes: the repo-root convention (docs/verification/<slug>.md) AND a proof
# co-located with its subject anywhere in the tree (any path ending /proof-of-done.md, e.g.
# a monorepo's tools/<name>/docs/proof-of-done.md). The content check in check() validates
# either the same way; location is just where the proof lives.
_fresh_proof_files() {
  local root="$1" base="$2"
  { git -C "$root" diff --name-only "$base"..HEAD 2>/dev/null
    git -C "$root" diff --name-only HEAD 2>/dev/null
    git -C "$root" diff --name-only --cached 2>/dev/null
    git -C "$root" ls-files --others --exclude-standard 2>/dev/null
  } | sort -u | grep -E '^docs/verification/.+\.md$|(^|/)proof-of-done\.md$' | grep -v '/README\.md$' || true
}

is_overridden() {
  local slug; slug="$(slugify "${1:-}")"
  [ -n "$slug" ] || return 1
  [ -f "$OVERRIDE_LOG" ] && grep -qF "| $slug |" "$OVERRIDE_LOG"
}

override() {
  local slug raw reason
  raw="${1:-}"; shift 2>/dev/null || { echo "usage: override <slug> <reason>" >&2; return 64; }
  reason="${*:-}"; slug="$(slugify "$raw")"
  [ -n "$slug" ] && [ -n "$reason" ] || { echo "usage: override <slug> <reason>" >&2; return 64; }
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  printf '%s | %s | OVERRIDE | %s\n' "$(now)" "$slug" "$reason" >> "$OVERRIDE_LOG"
  echo "proof-of-done override logged for '$slug' (trace: $OVERRIDE_LOG)"
}

check() {
  local root="${1:-}" base="${2:-}" slug="${3:-}"
  [ -n "$root" ] && [ -n "$base" ] || { echo "usage: check <root> <base> [slug]" >&2; return 64; }
  # fail open: base must resolve to a real commit.
  git -C "$root" rev-parse --verify -q "$base" >/dev/null 2>&1 || return 0

  local class last_v; class="$(classify "$root" "$base")"
  [ "$class" = "inert" ] && return 0          # docs/cosmetic: no ritual.

  if [ -n "$slug" ] && is_overridden "$slug"; then
    echo "proof-of-done: OVERRIDDEN for '$slug' (logged, see $OVERRIDE_LOG)" >&2
    return 0
  fi

  local files f ok=1
  files="$(_fresh_proof_files "$root" "$base")"
  # per-file (back-compat): a flat docs/verification/<slug>.md or a co-located
  # proof-of-done.md carries both markers in one file.
  if [ -n "$files" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      local p="$root/$f"; [ -f "$p" ] || continue
      if [ "$class" = "behavioral" ]; then
        # SPEC-080: an INCONCLUSIVE verdict never satisfies the gate, even with Exit: 0.
        # LAST-verdict-wins (review lens 2): the documented append shape retries after a
        # noisy run, so only the most recent Verdict: line in the file decides.
        last_v="$(grep -iE '^[[:space:]]*Verdict:' "$p" | tail -1)"
        grep -qi 'NEGATIVE CONTROL' "$p" && grep -qE 'Exit:[[:space:]]*0|VERDICT: PASS|Verdict: PASS|PASS' "$p" \
          && ! printf '%s' "$last_v" | grep -qiE 'Verdict:[[:space:]]*INCONCLUSIVE' && ok=0 && break
      else # stateful
        grep -qiE 'rollback|\[UNAVAILABLE' "$p" && grep -qE 'Command:|Exit:' "$p" && ok=0 && break
      fi
    done <<< "$files"
  fi
  # set-wise (directory layout): under docs/verification/<slug>/ the green run and the
  # negative control may live in different runs/ files. Group by the <slug>/ prefix and
  # satisfy when the UNION of a group's files carries both markers.
  if [ "$ok" -ne 0 ] && [ -n "$files" ]; then
    local groups g content
    groups="$(printf '%s\n' "$files" | sed -nE 's#^(docs/verification/[^/]+/).*#\1#p' | sort -u)"
    while IFS= read -r g; do
      [ -n "$g" ] || continue
      content=""
      while IFS= read -r f; do
        case "$f" in
          "$g"*) [ -f "$root/$f" ] && content+="$(cat "$root/$f")"$'\n' ;;
        esac
      done <<< "$(printf '%s\n' "$files" | sort)"
      if [ "$class" = "behavioral" ]; then
        # SPEC-080 last-verdict-wins, set-wise: files concatenate in sorted (= chronological)
        # order, so the union's final Verdict: line is the latest run's.
        last_v="$(printf '%s' "$content" | grep -iE '^[[:space:]]*Verdict:' | tail -1)"
        printf '%s' "$content" | grep -qi 'NEGATIVE CONTROL' \
          && printf '%s' "$content" | grep -qE 'Exit:[[:space:]]*0|VERDICT: PASS|Verdict: PASS|PASS' \
          && ! printf '%s' "$last_v" | grep -qiE 'Verdict:[[:space:]]*INCONCLUSIVE' \
          && ok=0 && break
      else # stateful
        printf '%s' "$content" | grep -qiE 'rollback|\[UNAVAILABLE' \
          && printf '%s' "$content" | grep -qE 'Command:|Exit:' \
          && ok=0 && break
      fi
    done <<< "$groups"
  fi
  [ "$ok" -eq 0 ] && return 0

  # blocked: name exactly what is missing.
  {
    echo "BLOCKED: proof of done. This is a '$class' change; it cannot ship/merge without a matching proof-of-done entry in docs/verification/."
    if [ "$class" = "behavioral" ]; then
      echo "  Need: a docs/verification/<slug>.md added by this branch with a green run AND a NEGATIVE CONTROL (revert -> RED -> restore)."
    else
      echo "  Need: a docs/verification/<slug>.md added by this branch with a recorded run AND a rollback note, or [UNAVAILABLE: reason] if no such flow exists here."
    fi
    echo "  Type-specific shape (SPEC-044): run 'bash lib/proof-gate.sh contract \"<your task>\"' for the exact artifact this work-type owes + the skill that owns it (e.g. a data/CLI tool owes a recorded live run; an eval owes a TEST-REPORT)."
    echo "  Produce it via /kit:verify (or record it), or log an explicit override (audited):"
    echo "    bash lib/proof-ledger.sh override '${slug:-<branch-slug>}' \"<reason>\""
  } >&2
  return 1
}

cmd="${1:-}"; shift 2>/dev/null || true
case "$cmd" in
  classify)      classify "$@" ;;
  check)         check "$@" ;;
  override)      override "$@" ;;
  is-overridden) is_overridden "$@" ;;
  *) echo "usage: proof-ledger.sh {classify|check|override|is-overridden} ..." >&2; exit 64 ;;
esac
