#!/usr/bin/env bash
# proof-ledger.sh -- the proof-of-done ship/merge gate (diff-keyed, spec-independent).
#
# Turns the proof-of-done convention (docs/verification/README.md) from advice into a
# wall: a load-bearing change cannot ship/merge without a matching proof-of-done entry.
# Unlike the lane gate (gate-ledger.sh), this keys off the BRANCH DIFF, not a spec, so it
# fires the same whether the work came through /kit:execute or a freeform /goal loop.
#
# A change's PROOF CLASS comes from its diff (consistent with lib/gate/proof-gate.sh):
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
LIB_ROOT="$(cd "$PROOF_LEDGER_DIR/.." && pwd)"  # the lib/ dir; cross-subsystem siblings resolve as "$LIB_ROOT/<subsystem>/<file>"
# Durable run-telemetry root (SPEC-097): resolve + one-time additive migration.
# shellcheck source=lib/telemetry/kit-log-dir.sh
source "$LIB_ROOT/telemetry/kit-log-dir.sh" || { echo "FATAL: lib/telemetry/kit-log-dir.sh missing or unreadable" >&2; exit 1; }
# The ONE append substrate (SPEC-182): the override write routes through ledger_append.
# shellcheck source=lib/ledger/ledger.sh
source "$LIB_ROOT/ledger/ledger.sh" || { echo "FATAL: lib/ledger/ledger.sh missing or unreadable" >&2; exit 1; }
kit_migrate_log_dir || true
LOG_DIR="$(kit_resolve_log_dir)" || exit 1
OVERRIDE_LOG="$LOG_DIR/proof-overrides.log"
OVERRIDE_STREAM="proof-overrides.log"

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

# deployable <root> <base>: prints yes|no by mapping classify()'s existing "stateful" class
# to "deployable" (SG-07: deployable-done, ADR-0028/ADR-0025). PURELY ADDITIVE -- a relabel
# of classify()'s output for readability at call sites, never a second classifier. Does not
# read or touch classify()'s logic, and classify()/check() are otherwise byte-unchanged.
deployable() {
  local root="${1:-}" base="${2:-}"
  [ -n "$root" ] && [ -n "$base" ] || { echo "usage: deployable <root> <base>" >&2; return 64; }
  [ "$(classify "$root" "$base")" = "stateful" ] && echo yes || echo no
}

# delivery-ratio <root> <base>: ADVISORY. Splits this branch's ADDED lines into
# "real deliverable" (code + user-facing docs) vs "proof/ceremony" (proof-of-done,
# verification, specs, impl-notes, ADRs, tests) and flags the hollow signature: a lot
# of proof wrapped around a near-zero real change. NEVER blocks -- it is a heuristic
# with real false positives (a legit docs/research sub-goal is proof-heavy by design;
# a 1-line regex fix can be load-bearing), so it only PRINTS a NOTICE/THIN-WARN/OK line
# for a reviewer or `mega status` to surface. Rationale: the proof-of-done gate checks
# that proof EXISTS, not that delivery is PROPORTIONATE, so a thin docs/reconcile
# sub-goal can pass by padding proof (2026-07-05 delivery audit; ADR "delivery ratio").
KIT_DELIVERY_RATIO_WARN="${KIT_DELIVERY_RATIO_WARN:-3}"    # proof >= N*real ...
KIT_DELIVERY_REAL_FLOOR="${KIT_DELIVERY_REAL_FLOOR:-40}"   # ... AND real < FLOOR => THIN-WARN
delivery_ratio() {
  local root="${1:-}" base="${2:-}"
  [ -n "$root" ] && [ -n "$base" ] || { echo "usage: delivery-ratio <root> <base>" >&2; return 64; }
  git -C "$root" rev-parse --verify -q "$base" >/dev/null 2>&1 \
    || { echo "real=0 proof=0 | SKIP: base '$base' is not a commit"; return 0; }
  local real=0 proof=0 add del path
  while IFS=$'\t' read -r add del path; do
    [ -n "$path" ] || continue
    [ "$add" = "-" ] && continue                            # binary file: no line count
    case "$path" in
      */proof-of-done.md|docs/proof/*|*/docs/proof/*|docs/verification/*|*/docs/verification/*|docs/specs/*|*/docs/specs/*|docs/implementation-notes/*|*/docs/implementation-notes/*|docs/runs/*|*/docs/runs/*|docs/decisions/*|*/docs/decisions/*|tests/*|*/tests/*)
        proof=$((proof+add)) ;;
      *.lock|*/uv.lock|*/package-lock.json|*/pnpm-lock.yaml|*/Cargo.lock|*/go.sum)
        : ;;                                                # generated lockfiles: ignore
      *)
        real=$((real+add)) ;;
    esac
  done < <(git -C "$root" diff --numstat "$base"..HEAD 2>/dev/null)

  local verdict
  if [ "$real" -eq 0 ]; then
    if [ "$proof" -gt 0 ]; then
      verdict="NOTICE: docs/proof-only branch -- expected for a docs/research sub-goal, SUSPECT for a build/rewrite/enforce claim"
    else
      verdict="OK: no added lines"
    fi
  elif [ "$proof" -ge $((KIT_DELIVERY_RATIO_WARN*real)) ] && [ "$real" -lt "$KIT_DELIVERY_REAL_FLOOR" ]; then
    verdict="THIN-WARN: proof >= ${KIT_DELIVERY_RATIO_WARN}x real and real < ${KIT_DELIVERY_REAL_FLOOR} -- confirm delivery matches the sub-goal's claim (advisory heuristic; false positives exist)"
  else
    verdict="OK"
  fi
  echo "real=$real proof=$proof | $verdict"
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
  ledger_append "$OVERRIDE_STREAM" "$(printf '%s | %s | OVERRIDE | %s' "$(now)" "$slug" "$reason")" || return 1
  echo "proof-of-done override logged for '$slug' (trace: $OVERRIDE_LOG)"
}

# _has_committed_image <proof-file> <root>: 0 iff the file embeds an image whose target
# actually EXISTS in the tree (resolved relative to the proof file's dir, then the repo root).
# Closes the fabrication hole: a bare `![x](missing.gif)` string must not count as "it ran" ,
# the picture has to really be there. A committed proof image satisfies this at push time; a
# dangling or typo'd reference does not.
_has_committed_image() {
  local pf="$1" root="$2" path
  [ -f "$pf" ] || return 1
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    path="${path%%[#?]*}"          # strip #anchor / ?query
    path="${path#./}"
    [ -f "$(dirname "$pf")/$path" ] && return 0
    [ -f "$root/$path" ] && return 0
  done < <(grep -oiE '!\[[^]]*\]\([^)]*\.(png|gif|jpe?g|svg|webp)\)' "$pf" 2>/dev/null \
            | sed -E 's/^.*\(([^)]*)\)$/\1/')
  return 1
}

check() {
  local root="${1:-}" base="${2:-}" slug="${3:-}"
  [ -n "$root" ] && [ -n "$base" ] || { echo "usage: check <root> <base> [slug]" >&2; return 64; }
  # fail open: base must resolve to a real commit.
  git -C "$root" rev-parse --verify -q "$base" >/dev/null 2>&1 || return 0

  local class last_v; class="$(classify "$root" "$base")"
  [ "$class" = "inert" ] && return 0          # docs/cosmetic: no ritual.

  if [ -n "$slug" ] && is_overridden "$slug"; then
    # cc-hyg-04: an override excuses docs / deploy-inert work, NOT application source
    # code. A blanket override that silently passes an unproven SOURCE change is the
    # rtk-611 hole (2026-07-01: an overridden branch shipped a broken source change,
    # reverted 9h later). Deploy scripts under a deploy/ path stay override-able (they
    # are verified via deploy-proof/UAT per SPEC-095); source code elsewhere is not.
    # Build the source-code remainder. A file counts as source if it has a code
    # extension OR is an extensionless shebang script (e.g. the kit's own
    # lib/goal/handoff-gen); deploy scripts at a SANCTIONED location (repo-root deploy/
    # or a per-tool tools/<name>/deploy/) are exempt -- but a `deploy` dir nested
    # anywhere else (src/deploy/, lib/deploy/) is NOT, or it would reopen the hole.
    local src_remainder="" f
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$f" in deploy/*|tools/*/deploy/*) continue ;; esac   # sanctioned deploy: override-able
      if printf '%s' "$f" | grep -qE '\.(sh|bash|zsh|py|js|jsx|mjs|cjs|ts|tsx|go|rs|rb|c|h|cc|cpp|hpp|java|php|swift|kt|kts|scala|clj|cljs|ex|exs|lua|pl|pm|r|m|mm|sql)$'; then
        src_remainder="${src_remainder}${f}"$'\n'; continue
      fi
      # extensionless file (no dot in basename): treat as source if it is a shebang script.
      case "$(basename "$f")" in
        *.*) : ;;
        *) [ -f "$root/$f" ] && [ "$(head -c2 "$root/$f" 2>/dev/null)" = '#!' ] && src_remainder="${src_remainder}${f}"$'\n' ;;
      esac
    done < <(_changed "$root" "$base")
    if [ -n "$src_remainder" ]; then
      echo "proof-of-done: override for '$slug' REJECTED -- the branch changes source files with no proof of done:" >&2
      printf '%s' "$src_remainder" | sed 's/^/    - /' >&2
      echo "  An override excuses docs / deploy-inert work only. Provide a proof of done for the source change (run /kit:verify), or split it out." >&2
      return 1
    fi
    echo "proof-of-done: OVERRIDDEN for '$slug' (docs/deploy-inert remainder; logged, see $OVERRIDE_LOG)" >&2
    return 0
  fi

  local files f ok=1
  # A committed screenshot/GIF embed counts as captured run-evidence too (visual/demo work
  # proves "it actually ran" with a picture, not only a text run-table). The semantic marker
  # (NEGATIVE CONTROL / rollback) is still required, and the image must actually EXIST , see
  # _has_committed_image, so a dangling `![x](missing.gif)` reference does not count.
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
        grep -qi 'NEGATIVE CONTROL' "$p" && { grep -qE 'Exit:[[:space:]]*0|VERDICT: PASS|Verdict: PASS|PASS' "$p" || _has_committed_image "$p" "$root"; } \
          && ! printf '%s' "$last_v" | grep -qiE 'Verdict:[[:space:]]*INCONCLUSIVE' && ok=0 && break
      else # stateful
        grep -qiE 'rollback|\[UNAVAILABLE' "$p" && { grep -qE 'Command:|Exit:' "$p" || _has_committed_image "$p" "$root"; } && ok=0 && break
      fi
    done <<< "$files"
  fi
  # set-wise (directory layout): under docs/verification/<slug>/ the green run and the
  # negative control may live in different runs/ files. Group by the <slug>/ prefix and
  # satisfy when the UNION of a group's files carries both markers.
  if [ "$ok" -ne 0 ] && [ -n "$files" ]; then
    local groups g content grp_img
    groups="$(printf '%s\n' "$files" | sed -nE 's#^(docs/verification/[^/]+/).*#\1#p' | sort -u)"
    while IFS= read -r g; do
      [ -n "$g" ] || continue
      content=""; grp_img=1     # grp_img=0 iff some file in the group embeds a REAL image
      while IFS= read -r f; do
        case "$f" in
          "$g"*) [ -f "$root/$f" ] && { content+="$(cat "$root/$f")"$'\n'; _has_committed_image "$root/$f" "$root" && grp_img=0; } ;;
        esac
      done <<< "$(printf '%s\n' "$files" | sort)"
      if [ "$class" = "behavioral" ]; then
        # SPEC-080 last-verdict-wins, set-wise: files concatenate in sorted (= chronological)
        # order, so the union's final Verdict: line is the latest run's.
        last_v="$(printf '%s' "$content" | grep -iE '^[[:space:]]*Verdict:' | tail -1)"
        printf '%s' "$content" | grep -qi 'NEGATIVE CONTROL' \
          && { printf '%s' "$content" | grep -qE 'Exit:[[:space:]]*0|VERDICT: PASS|Verdict: PASS|PASS' || [ "$grp_img" -eq 0 ]; } \
          && ! printf '%s' "$last_v" | grep -qiE 'Verdict:[[:space:]]*INCONCLUSIVE' \
          && ok=0 && break
      else # stateful
        printf '%s' "$content" | grep -qiE 'rollback|\[UNAVAILABLE' \
          && { printf '%s' "$content" | grep -qE 'Command:|Exit:' || [ "$grp_img" -eq 0 ]; } \
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
      echo "        ('green run' = a text run-table (Command:/Exit:/Verdict: PASS) OR a committed screenshot/GIF embed for visual/demo work.)"
    else
      echo "  Need: a docs/verification/<slug>.md added by this branch with a recorded run AND a rollback note, or [UNAVAILABLE: reason] if no such flow exists here."
      echo "        ('recorded run' = Command:/Exit: text OR a committed screenshot/GIF embed for visual/demo work.)"
    fi
    echo "  Type-specific shape (SPEC-044): run 'bash lib/gate/proof-gate.sh contract \"<your task>\"' for the exact artifact this work-type owes + the skill that owns it (e.g. a data/CLI tool owes a recorded live run; an eval owes a TEST-REPORT)."
    echo "  Produce it via /kit:verify (or record it), or log an explicit override (audited):"
    echo "    bash lib/gate/proof-ledger.sh override '${slug:-<branch-slug>}' \"<reason>\""
  } >&2
  return 1
}

cmd="${1:-}"; shift 2>/dev/null || true
case "$cmd" in
  classify)      classify "$@" ;;
  check)         check "$@" ;;
  override)      override "$@" ;;
  is-overridden) is_overridden "$@" ;;
  deployable)    deployable "$@" ;;
  delivery-ratio) delivery_ratio "$@" ;;
  *) echo "usage: proof-ledger.sh {classify|check|override|is-overridden|deployable|delivery-ratio} ..." >&2; exit 64 ;;
esac
