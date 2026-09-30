#!/usr/bin/env bash
# lane-classify.sh -- deterministic task-type -> risk-lane classifier.
#
# Turns a one-line task description into one of the WORKFLOW.md risk lanes
# (tiny | normal | full | bug | backfill) so the intake path (/kit:assign) and the
# dispatch path (/kit:dispatch) can auto-choose the lane instead of relying on ad-hoc
# judgment. Pure bash + grep; no binary.
#
# Words never pick `full`. A hard-flag hit (or 4+ soft flags) returns the default lane
# ([lanes] default, normal) and prints one stderr `LANE-SUGGEST: full (<flags>)` line; with
# `--rid <rid>` it also writes a `lane-suggest` action to the run ledger. The operator assigns
# full. The floor for risk is the diff: `floor <root> [<base>]` returns `full` from changed
# file paths and added lines (migrations, auth, secrets, CI, kit config, data loss), and
# `--files` on classify applies the same path test.
#
# Flag-scoring model (absorbed from hoangnb24/repository-harness FEATURE_INTAKE, 2026-06-10;
# see this module's own flag-scoring design doc + docs/absorption/2026-06-10-repository-harness.md). Named risk flags
# are matched against the description:
#   - HARD-gate flags: any one hit -> a `full` SUGGESTION (mirrors the harness auto-escalate
#     list + the WORKFLOW full-lane triggers, PLUS a `kit-machinery` flag).
#   - SOFT flags: counted; 4+ -> a `full` suggestion, 2-3 -> `normal` (noted as near-full).
# `explain` prints which flags fired so a classification (and any override) is auditable, not a
# black box. This SUGGESTS a lane; it never blocks ("Detect, don't dictate").
#
# Precedence (first match wins): backfill > tiny > hard path in --files > bug > soft-count >
# default lane; hard-gate flags only add the suggestion. tiny stays above them so "a typo about
# auth" is still a typo; backfill stays first so a keyword inside a doc task (e.g. "write its
# AGENTS.md") does not escalate.
#
# The `check` subcommand adds the floor guard: given the lane actually CHOSEN
# plus the task text, it warns (advisory, exit 0) when the choice is lighter than the
# suggestion, so an under-sized full/bug task does not slip through /kit:assign unnoticed.
#
# Usage:
#   lane-classify.sh classify [--files "<paths>"] [--rid <rid>] "<desc>"  -> prints the lane, exit 0
#   lane-classify.sh explain  [--files ...] [--rid <rid>] "<desc>"   -> lane + reason + fired flags (+ suggest:)
#   lane-classify.sh check [--files ...] [--rid <rid>] <chosen-lane> "<desc>"  -> warn+log if chosen < floor, exit 0
#   lane-classify.sh escalate <current-lane> <spec-file>  -> up-only spec->build re-classify
#                                                            (ESCALATE <cur> -> <heavier> | HOLD <cur>), exit 0
#   lane-classify.sh floor <root> [<base>]              -> `full <kind>: <path>` for the first hard-path hit
#                                                            in the base..HEAD diff, else nothing, exit 0
#   lane-classify.sh deescalate <chosen-lane> [--rid <rid>] [--root <path>] [--base <ref>] [--floor <N>]
#                                                        -> down-only SHIP-time size nudge:
#                                                           advisory line + ledger action, never blocks, exit 0
#   lane-classify.sh lanes                              -> prints the 5 lane names
#   lane-classify.sh flags                              -> prints the flag names

set -euo pipefail

# Durable run-telemetry root: the LANE-CHECK downgrade writer below must land
# in the same durable dir lane-telemetry.sh reads from, or downgrades go split-brain
# (written to the legacy path, invisible to the migrated reader).
LC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_ROOT="$(cd "$LC_DIR/.." && pwd)"  # the lib/ dir; cross-subsystem siblings resolve as "$LIB_ROOT/<subsystem>/<file>"
# shellcheck source=lib/telemetry/kit-log-dir.sh
source "$LIB_ROOT/telemetry/kit-log-dir.sh" || { echo "FATAL: lib/telemetry/kit-log-dir.sh missing or unreadable" >&2; exit 1; }
# deescalate()'s ledger write only; no other verb in this file touches gate-ledger.
GATE_LEDGER="$LIB_ROOT/gate/gate-ledger.sh"
# The default lane and the extra hard paths come from kit.toml through the one lane-data reader.
# shellcheck source=lib/gate/lane-data.sh
source "$LIB_ROOT/gate/lane-data.sh" || { echo "FATAL: lib/gate/lane-data.sh missing or unreadable" >&2; exit 1; }

# Hard-gate flags (any hit -> full). name <-> regex, index-aligned.
_hard_name=(auth data-model audit-security external-provider public-contract weaken-validation kit-machinery)
_hard_re=(
  'auth[a-z]*|login|logout|password|jwt|\bsessions? (token|cookie|id|hijack|fixation|store|management|expiry)|(login|auth|user) sessions?\b|refresh token|permission|role[s]? (check|permission|grant|assignment)|role-based|rbac|tenant'
  'migrat|schema|data[ -]model|uniqueness|retention|data loss|delete[s]? .*data|drop (table|column)'
  'audit|privacy|sensitive data|access log|secret|(auth|access|refresh|api|bearer|session) token|token (leak|rotation|storage|refresh)|crypto|encrypt|\bsecurity\b|harden|vulnerab|exploit|injection|\bxss\b|\bcsrf\b|rate.?limit'
  'external (api|provider|service)|payment|billing|webhook (signature|secret|verif[a-z]*|auth[a-z]*|endpoint|handler)|provider sdk|email send'
  'api contract|response envelope|public (api|contract)|client[ -]visible|breaking change'
  'weaken[s]? .*validation|remove[s]? .*validation|disabl[a-z]* .*(check|guard|validation)'
  'hooks/|hooks\.json|\bhook(s)?\b.{0,30}(kit|machinery|enforcement|gate-ledger|ship-gate|lane-classify)|the kit.{0,30}\bhook(s)?\b|(disable|bypass|turn off|skip|remove)[a-z]*\b.{0,20}\bhook(s)?\b|\bhook(s)?\b.{0,20}(disable|bypass|turn off|skip|remove)|\bsafety\b.{0,15}\bhook(s)?\b|\bguard\b.{0,15}\bhook(s)?\b|gate-ledger|ship-gate|lane-classify|lane-telemetry|mega-merge|stack-merge|proof-ledger|kit-log-dir|orchestrate\.sh|role-classify|goal-drafts|proof-gate|task-type-classify|backlog\.sh|goal-registry|dispatch-gate|install\.sh|adopt\.sh|workflow\.md|adopt @|/?kit:adopt|adopt(s|ed|ing)? .{0,30}(agents?\.md|contract|kit|loader|marker|workflow|gate)|gate machinery|the kit.{0,12}(lane|gate|machinery|classifier)'
)
# Soft flags (counted; 4+ -> full, 2-3 -> normal-noted). name <-> regex, index-aligned.
_soft_name=(cross-platform existing-behavior weak-proof multi-domain concurrency)
_soft_re=(
  'cross[ -]platform|desktop.*mobile|native shell|deep link'
  'existing behavio|already (implemented|test-covered|shipped)|change[s]? .*(existing|current) behavio'
  'no tests?|missing tests?|untested|unclear test|weak (proof|coverage)'
  'multi[ -]domain|more than one .*domain|two domains'
  'concurren|race condition|\bparallel\b|locking|index\.lock'
)

# A name array out of sync with its regex array would mislabel `explain` output silently
# (review: parallel-array footgun). Fail loud at load instead.
[ "${#_hard_name[@]}" -eq "${#_hard_re[@]}" ] && [ "${#_soft_name[@]}" -eq "${#_soft_re[@]}" ] \
  || { echo "lane-classify: flag name/regex arrays are misaligned (bug)" >&2; exit 70; }

LANE=""; REASON=""; FIRED=""; SUGGEST=""; RID=""

# Edit-vs-mention signal. FILES = the change's touched files (space-
# separated); FILES_SET = 1 when the caller passed --files (even empty). Default: no files
# supplied -> the kit-machinery hard-gate keeps its legacy text-only behavior (a mention
# escalates), so nothing regresses for callers that pass none. Set per-invocation by
# _extract_files below; a fresh CLI process starts at the defaults.
FILES=""; FILES_SET=0; REMAIN=()

# Built-in hard paths (case-insensitive ERE over changed paths). Constants on purpose: no
# config file can remove one. `[lanes] extra_hard_paths` only adds.
_HP_migration='(^|/)(migrations?|migrate)/|(^|/)alembic/versions/|(^|/)drizzle/|(^|/)schema\.(sql|rb|prisma)$|(^|/)[^/]*changelog[^/]*\.(xml|ya?ml|json|sql)$'
_HP_auth='(^|/)(auth(entication|orization|orisation|n|z|[_-][a-z_-]*)?|oauth|rbac|permissions?|sessions?)(/|\.[a-z]+$)|(^|/)[^/]*(login|password|passwd|jwt)[^/]*$'
_HP_secret='(^|/)\.env(\.(local|dev|development|prod|production|staging|test))?$|(^|/)secrets?/|\.(pem|key|p12|pfx)$|(^|/)[^/]*credentials?[^/]*$'
_HP_ci='(^|/)\.github/'
_HP_infra='(^|/)Dockerfile[^/]*$|(^|/)[^/]*(iam|role|polic)[^/]*\.tf$|(^|/)(iam|policies)/[^/]*\.tf$'
_HP_kitconfig='(^|/)\.kit\.toml$'
# Added-line signatures for data loss, checked only in non-doc files. `truncate` counts as SQL:
# any use in a .sql file, or a statement-shaped `truncate <name>;` elsewhere.
_HL_common='drop[[:space:]]+(table|column|database|schema)|deletemany\([[:space:]]*\{[[:space:]]*\}[[:space:]]*\)'
_HL_truncate_code='(truncate[[:space:]]+(table[[:space:]]+)?[a-z_."]+[[:space:]]*;|["'"'"'`][[:space:]]*truncate[[:space:]]+(table[[:space:]]+)?[a-z_."]+)'
_HL_truncate_sql='(.*[^a-z_])?truncate[[:space:]]+(table[[:space:]]+)?[a-z_."]+'

# _hp_re <kind> -- the built-in ERE for a hard-path kind.
_HP_KINDS="migration auth secret ci infra kit-config"
_hp_re() {
  case "$1" in
    migration) printf '%s' "$_HP_migration" ;; auth) printf '%s' "$_HP_auth" ;;
    secret) printf '%s' "$_HP_secret" ;; ci) printf '%s' "$_HP_ci" ;;
    infra) printf '%s' "$_HP_infra" ;;
    kit-config) printf '%s' "$_HP_kitconfig" ;;
  esac
}
# The extra_hard_paths union, loaded once per process (each load reads config and shells out).
_EXTRA_LOADED=0; _EXTRA_LIST=""
_load_extras() {
  [ "$_EXTRA_LOADED" = 1 ] && return 0
  _EXTRA_LIST="$(lane_extra_hard_paths)"; _EXTRA_LOADED=1
}

# _path_kind <path> -- print the hard-path kind a changed path hits (first match), else nothing.
_path_kind() {
  local f="$1" k extra
  for k in $_HP_KINDS; do
    if printf '%s\n' "$f" | grep -Eiq -- "$(_hp_re "$k")"; then printf '%s' "$k"; return 0; fi
  done
  _load_extras
  while IFS= read -r extra; do
    [ -n "$extra" ] || continue
    if printf '%s\n' "$f" | grep -Eiq -- "$extra"; then printf 'extra'; return 0; fi
  done <<< "$_EXTRA_LIST"
  return 0
}

# _files_hard_hit -- first `<kind>: <path>` among the --files paths, else nothing.
_files_hard_hit() {
  local f k _files=()
  IFS=' ' read -ra _files <<< "$FILES"
  for f in ${_files[@]+"${_files[@]}"}; do
    k="$(_path_kind "$f")"
    [ -n "$k" ] && { printf '%s: %s' "$k" "$f"; return 0; }
  done
  return 1
}

# _files_touch_machinery -- true if any touched file is under lib/ or hooks/ (the kit's
# enforcement layer). A FILE fact that separates an EDIT to a machinery lib from a mere
# textual MENTION of its basename; it feeds the kit-machinery SUGGESTION, not the lane.
_files_touch_machinery() {
  local f _files=()
  IFS=' ' read -ra _files <<< "$FILES"
  for f in ${_files[@]+"${_files[@]}"}; do
    case "$f" in
      lib/*|hooks/*|*/lib/*|*/hooks/*) return 0 ;;
    esac
  done
  return 1
}

# _extract_files "$@" -- pull optional `--files <list>` / `--files=<list>` and `--rid <rid>` /
# `--rid=<rid>` out of the args, set FILES + FILES_SET + RID, and leave the remaining
# (description) args in REMAIN. Anywhere in the arg list; each value is one shell word.
_extract_files() {
  FILES=""; FILES_SET=0; REMAIN=(); RID=""
  local a skip=""
  for a in "$@"; do
    if [ -n "$skip" ]; then
      case "$skip" in files) FILES="$a" ;; rid) RID="$a" ;; esac
      skip=""; continue
    fi
    case "$a" in
      --files)   FILES_SET=1; skip=files ;;
      --files=*) FILES_SET=1; FILES="${a#--files=}" ;;
      --rid)     skip=rid ;;
      --rid=*)   RID="${a#--rid=}" ;;
      *)         REMAIN+=("$a") ;;
    esac
  done
}

# _emit_suggest -- print the one-line LANE-SUGGEST (stderr) when classify_core set SUGGEST, and
# record it as a ledger action when a rid was given. Best effort: never fails the verb.
_emit_suggest() {
  [ -n "$SUGGEST" ] || return 0
  echo "LANE-SUGGEST: full ($SUGGEST); default stays $LANE; the operator assigns full with: gate-ledger.sh start --amend ${RID:-<rid>} full ..." >&2
  if [ -n "$RID" ]; then
    bash "$GATE_LEDGER" action "$RID" "lane-suggest full flags=$SUGGEST" >/dev/null 2>&1 || true
  fi
  return 0
}

# classify_core "<desc>" -- sets LANE, REASON, FIRED. The single source of truth both
# `classify` and `explain` read. Reads the FILES/FILES_SET globals for the edit-vs-mention
# discriminator; callers that don't set them get the legacy text-only path.
classify_core() {
  local lc def; lc="$(printf '%s' "$*" | tr '[:upper:]' '[:lower:]')"
  LANE=""; REASON=""; FIRED=""; SUGGEST=""
  def="$(lane_default)"

  # 1. backfill: brownfield operating-layer documentation (first, so an in-doc keyword like
  #    "write its AGENTS.md" does not pull the task into the kit-machinery hard-gate).
  if printf '%s' "$lc" | grep -qE 'backfill|operating[ -]layer|brownfield|document the existing|writes?\b.{0,12}(agents|claude)\.md'; then
    # A backfill phrase that ALSO carries a hard-gate subject ("write its AGENTS.md and disable
    # the safety hooks") must not be down-laned to backfill: it takes the default lane and
    # carries the full suggestion. The pure doc case carries no hard keyword and stays backfill.
    local j hb=""
    for j in "${!_hard_re[@]}"; do
      if printf '%s' "$lc" | grep -qE "${_hard_re[$j]}"; then hb="${hb:+$hb,}${_hard_name[$j]}"; fi
    done
    if [ -n "$hb" ]; then
      LANE="$def"; SUGGEST="$hb"; REASON="backfill phrase + hard-gate subject ($hb)"; FIRED="$hb"; return 0
    fi
    LANE=backfill; REASON="brownfield operating-layer docs"; FIRED=backfill; return 0
  fi

  # 2. tiny: pure cosmetic, regardless of subject (a typo about auth is still a typo).
  if printf '%s' "$lc" | grep -qE 'typo|whitespace|re-?word|copy[ -]?edit|comment|rename|formatting|one[ -]liner?|wording|doc(s)? fix|fix .*(typo|wording|comment)'; then
    LANE=tiny; REASON="pure cosmetic"; FIRED=tiny; return 0
  fi

  # 3. hard-gate flags -> a full SUGGESTION (never the lane). kit-machinery is a proxy for
  #    "touches the enforcement surface", a FILE fact: with --files the touched paths decide,
  #    not a description that merely names a basename; without --files a mention counts.
  #    A hard PATH in --files (migration, auth, secret, CI, kit config, extra) is a file fact
  #    too, and it is the one route to `full` from classify.
  local i hard=""
  if [ "$FILES_SET" = 1 ]; then
    local hit; hit="$(_files_hard_hit || true)"
    if [ -n "$hit" ]; then
      LANE=full; REASON="hard path in --files (${hit})"; FIRED="hard-path"; return 0
    fi
  fi
  for i in "${!_hard_re[@]}"; do
    if [ "${_hard_name[$i]}" = kit-machinery ] && [ "$FILES_SET" = 1 ]; then
      _files_touch_machinery && hard="${hard:+$hard,}kit-machinery"
      continue
    fi
    if printf '%s' "$lc" | grep -qE "${_hard_re[$i]}"; then hard="${hard:+$hard,}${_hard_name[$i]}"; fi
  done
  SUGGEST="$hard"

  # 3b. doc-bootstrap, deliberately AFTER the hard-gate pass:
  # markdown-only or doc-tree bootstrap work is tiny, but these anchors describe the
  # SUBJECT of the work, not a cosmetic surface, so a README about auth tokens or
  # gate machinery must let the hard-gate win first (review HIGH).
  if [ -z "$hard" ] && printf '%s' "$lc" | grep -qE 'markdown[ -]only|bootstrap .{0,40}(readme|notes|reading list|learning track)'; then
    LANE=tiny; REASON="doc bootstrap (markdown-only / doc-tree), no hard-gate subject"; FIRED=doc-bootstrap; return 0
  fi

  # 4. bug: a defect, not a new feature.
  if printf '%s' "$lc" | grep -qE '\bbug\b|regression|failing test|broken|crash|defect|hotfix|stack ?trace|exception|fix the|fix a |repro'; then
    LANE=bug; REASON="defect / regression${SUGGEST:+; hard-gate flag(s): $SUGGEST}"; FIRED="bug${SUGGEST:+ $SUGGEST}"; return 0
  fi

  # 5. soft-flag count: 4+ -> full, 2-3 -> normal (near-full), else default normal.
  local soft="" n=0
  for i in "${!_soft_re[@]}"; do
    if printf '%s' "$lc" | grep -qE "${_soft_re[$i]}"; then soft="$soft ${_soft_name[$i]}"; n=$((n + 1)); fi
  done
  local sl; sl="$(printf '%s' "${soft# }" | tr ' ' ',')"
  if [ "$n" -ge 4 ]; then
    LANE="$def"; SUGGEST="${SUGGEST:-$sl}"; REASON="$n soft flags (>=4):$soft"; FIRED="${soft# }"; return 0
  fi
  if [ "$n" -ge 2 ]; then LANE=normal; REASON="$n soft flags (2-3, near full):$soft"; FIRED="${soft# }"; [ -z "$hard" ] || FIRED="$hard ${soft# }"; return 0; fi
  if [ -n "$hard" ]; then LANE="$def"; REASON="hard-gate flag(s): $hard; default lane"; FIRED="${hard//,/ }"; return 0; fi
  LANE="$def"; REASON="bounded feature/fix (default)"; FIRED="${soft# }"; FIRED="${FIRED:-none}"; return 0
}

# Risk rank for the check verb and escalate. normal/bug/backfill share rank 2 (same ceremony
# weight); full is rank 3 and comes only from a hard path in the diff or from the operator
# assigning it, never from task words. An unrecognized lane returns -1 so lane_check can flag
# it distinctly.
lane_rank() {
  case "$1" in
    tiny)                echo 1;;
    normal|bug|backfill) echo 2;;
    full)                echo 3;;
    *)                   echo -1;;
  esac
}

# Advisory floor check: compare the lane a human/LLM CHOSE against the deterministic
# suggestion for the same text. Warn (stderr) + log (completeness.log) ONLY when the
# chosen lane is lighter than the floor. Never blocks; always exits 0 ("Detect, don't
# dictate"). This is the guard the classify-then-route audit found missing: classify
# suggests, but nothing caught an under-sized choice.
lane_check() {
  local chosen desc suggested cr sr log_dir desc_trunc
  chosen="${1:-}"; shift 2>/dev/null || true
  desc="$*"
  [ -n "$chosen" ] || { echo "usage: lane-classify.sh check <chosen-lane> \"<description>\"" >&2; return 64; }

  cr="$(lane_rank "$chosen")"
  if [ "$cr" -lt 0 ]; then
    echo "LANE-UNKNOWN: '$chosen' is not a lane (tiny|normal|full|bug|backfill); not checked" >&2
    return 0
  fi

  classify_core "$desc"
  suggested="$LANE"
  sr="$(lane_rank "$suggested")"
  _emit_suggest

  if [ "$cr" -lt "$sr" ]; then
    echo "LANE-DOWNGRADE: chosen=$chosen suggested=$suggested -- the task text matches a heavier lane; size up or say why" >&2
    desc_trunc="$(printf '%s' "$desc" | tr '\n' ' ' | cut -c1-100)"
    # NB (arch review): unlike the other 5 corpus libs (which migrate at load), lane-classify
    # migrates HERE, at the downgrade-write path -- classify/explain run far more often WITHOUT
    # a downgrade, so deferring the mkdir/stat to the actual write is a small deliberate win.
    kit_migrate_log_dir || true
    log_dir="$(kit_resolve_log_dir)"
    mkdir -p "$log_dir" 2>/dev/null || true
    printf '%s | LANE-CHECK | downgrade | chosen=%s suggested=%s | %s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$chosen" "$suggested" "$desc_trunc" \
      >> "$log_dir/completeness.log" 2>/dev/null || true
  fi
  return 0
}

# Spec->build-boundary re-classification (refinement point 4, kit-hardening).
# `check` above compares the CHOSEN lane against the original
# task TEXT at intake; `escalate` compares the lane RECORDED at intake against the
# SPEC's own text at the point the spec is validated and build is about to start --
# the first point emergent scope (auth / data-model / migration the one-line task
# description never carried) is concrete. Up-only: a heavier spec-implied lane
# escalates; a same-or-lighter one HOLDS (the downgrade guard -- reuses lane_rank,
# same as lane_check, so a lighter re-class can never win). Advisory: prints the
# decision and exits 0 always ("Detect, don't dictate"; mid-flight never
# hard-blocks). It does NOT mutate the gate-ledger or the spec file itself -- the
# caller (commands/execute.md Prerequisites) does the recording on ESCALATE.
escalate() {
  local current="${1:-}" spec_file="${2:-}" cr spec_lane sr
  if [ -z "$current" ] || [ -z "$spec_file" ]; then
    echo "usage: lane-classify.sh escalate <current-lane> <spec-file>" >&2; return 64
  fi
  [ -f "$spec_file" ] || { echo "escalate: spec file '$spec_file' not found" >&2; return 64; }

  cr="$(lane_rank "$current")"
  if [ "$cr" -lt 0 ]; then
    echo "LANE-UNKNOWN: '$current' is not a lane (tiny|normal|full|bug|backfill); not checked" >&2
    return 0
  fi

  classify_core "$(cat "$spec_file")"
  spec_lane="$LANE"
  sr="$(lane_rank "$spec_lane")"

  if [ "$sr" -gt "$cr" ]; then
    printf 'ESCALATE %s -> %s\n' "$current" "$spec_lane"
  else
    printf 'HOLD %s\n' "$current"
    LANE="$current"
  fi
  _emit_suggest
  return 0
}

# --- ship-time de-escalation: the size-floor sibling of escalate() above. ---
# escalate() is TEXT-based and up-only, at the spec->build boundary. deescalate() is
# DIFF-SIZE-based and down-only, at the SHIP boundary: when the lane actually SHIPPED was
# normal/full but the final diff stayed under a changed-lines floor, this is a NUDGE for next
# time's classification habit, never a re-classification of the run that already shipped
# (mirrors quiz-gate.sh's always-exit-0, never-block posture). Only an escalated lane
# (normal/full) can ever be found "too heavy after all" -- tiny/bug/backfill never fire,
# mirroring lane_rank's "over-sizing is always safe" stance (nothing here ever calls a bug or
# backfill run oversized).
#
# Base resolution mirrors hooks/ship-gate.sh / lib/gate/coverage-delta.sh's _resolve_base
# (origin/HEAD symref -> origin/main -> main -> origin/master -> master).
_deesc_default_branch() {
  local root="$1" ref
  ref="$(git -C "$root" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"
  if [ -n "$ref" ]; then printf '%s\n' "$ref"; return; fi
  local c
  for c in origin/main main origin/master master; do
    git -C "$root" rev-parse --verify -q "$c" >/dev/null 2>&1 && { printf '%s\n' "$c"; return; }
  done
  printf '%s\n' master
}
_deesc_resolve_base() {
  local root="$1" def
  def="$(_deesc_default_branch "$root")"
  git -C "$root" merge-base HEAD "$def" 2>/dev/null || git -C "$root" rev-parse HEAD 2>/dev/null || true
}

# Total added+deleted lines: committed base..HEAD + any uncommitted working-tree delta.
# DELIBERATELY a 2-source sum, NOT the 3-way union coverage-delta.sh/proof-ledger.sh use
# (base..HEAD + working-tree + --cached): `git diff HEAD` (working tree vs HEAD) already
# folds in the staged delta, so adding `--cached` again would double-count every staged line.
# That double-count is harmless for those two gates (it biases them toward MORE warnings,
# their safe direction); it would bias THIS gate the wrong way (under-nudging a genuinely
# small diff). See this module's own design doc for the full note.
_deesc_changed_lines() {
  local root="$1" base="$2" total=0 a d
  while IFS=$'\t' read -r a d _rest; do
    [ "$a" = "-" ] && a=0; [ "$d" = "-" ] && d=0
    total=$((total + a + d))
  done < <(
    { git -C "$root" diff --numstat "$base"..HEAD -- . 2>/dev/null
      git -C "$root" diff --numstat HEAD -- . 2>/dev/null
    } 2>/dev/null
  )
  printf '%s' "$total"
}

# Usage: deescalate <chosen-lane> [--rid <rid>] [--root <path>] [--base <ref>] [--floor <N>]
# ALWAYS exits 0. Prints nothing and writes nothing unless the lane is normal/full AND the
# diff is under the floor (LANE_DEESCALATE_FLOOR env var, default 20 -- see WORKFLOW.md
# "Lane x phase depth matrix" for the rationale). The --rid ledger write is best-effort
# (`|| true`): a write failure can never affect this command's own exit code.
deescalate() {
  local chosen="${1:-}"; shift 2>/dev/null || true
  [ -n "$chosen" ] || {
    echo "usage: lane-classify.sh deescalate <chosen-lane> [--rid <rid>] [--root <path>] [--base <ref>] [--floor <N>]" >&2
    return 64
  }
  local rid="" root="" base="" floor="${LANE_DEESCALATE_FLOOR:-20}"
  local a skip=""
  for a in "$@"; do
    if [ -n "$skip" ]; then
      case "$skip" in rid) rid="$a";; root) root="$a";; base) base="$a";; floor) floor="$a";; esac
      skip=""; continue
    fi
    case "$a" in
      --rid)     skip=rid ;;
      --rid=*)   rid="${a#--rid=}" ;;
      --root)    skip=root ;;
      --root=*)  root="${a#--root=}" ;;
      --base)    skip=base ;;
      --base=*)  base="${a#--base=}" ;;
      --floor)   skip=floor ;;
      --floor=*) floor="${a#--floor=}" ;;
    esac
  done

  # Lane guard: only normal/full can ever be found oversized for a small diff.
  case "$chosen" in normal|full) ;; *) return 0 ;; esac

  [ -n "$root" ] || root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  [ -n "$base" ] || base="$(_deesc_resolve_base "$root")"
  [ -n "$base" ] || return 0   # no resolvable base (e.g. no commits yet) -- nothing to measure

  [[ "$floor" =~ ^[0-9]+$ ]] || floor=20

  local lines; lines="$(_deesc_changed_lines "$root" "$base")"
  [[ "$lines" =~ ^[0-9]+$ ]] || return 0

  if [ "$lines" -lt "$floor" ]; then
    printf 'LANE-DEESCALATE: shipped as %s but the diff stayed tiny-sized (%s changed line(s) < floor=%s); consider `tiny` lane next time\n' \
      "$chosen" "$lines" "$floor"
    if [ -n "$rid" ]; then
      bash "$GATE_LEDGER" action "$rid" "lane-deescalate chosen=$chosen lines=$lines floor=$floor verdict=misroute-tiny" >/dev/null 2>&1 || true
    fi
  fi
  return 0
}

# floor <root> [<base> [<head>]] -- the diff floor. Prints `full <kind>: <path>` for the first hit
# among the base..head changed paths and the ADDED lines (data loss), else nothing. Always exits 0.
# Paths come from `diff -z` with core.quotePath=false, so a non-ASCII name is matched as written and
# never as a quoted octal string. Renames are listed with --no-renames, so both sides count
# (as in lib/gate/proof-ledger.sh). Every kind is matched in ONE grep pass over the whole path
# list and the added lines are scanned in ONE pass, so the cost stays flat as the diff grows (the
# hook has a short timeout that fails open). The project's lane data is read from <root>.
_DOC_AWK='cur ~ /\.(md|markdown|txt|rst|adoc)$/ || cur ~ /(^|\/)docs\//'
floor() {
  local root="${1:-}" base="${2:-}" head="${3:-HEAD}"
  [ -n "$root" ] || { echo "usage: lane-classify.sh floor <root> [<base> [<head>]]" >&2; return 64; }
  export KIT_PROJECT_ROOT="$root"
  [ -n "$base" ] || base="$(_deesc_resolve_base "$root")"
  [ -n "$base" ] || return 0
  local tmp; tmp="$(mktemp -d)" || return 0
  # Both kinds of scan read from $tmp; the trap removes only what this call created.
  trap 'rm -rf "$tmp"' RETURN
  git -C "$root" -c core.quotePath=false diff -z --raw --no-renames "$base" "$head" > "$tmp/raw" 2>/dev/null || true
  local meta path n=0 paths="" links=""
  while IFS= read -r -d '' meta; do
    IFS= read -r -d '' path || break
    n=$((n + 1)); path="${path//$'\n'/?}"
    paths="$paths$path"$'\n'
    set -- $meta
    if [ "${1:-}" = ":160000" ] || [ "${2:-}" = "160000" ]; then links="${links:+$links }$n"; fi
  done < "$tmp/raw"
  printf '%s' "$paths" > "$tmp/paths"
  local best=0 bestkind="" k re hit num
  for k in $_HP_KINDS; do
    re="$(_hp_re "$k")"
    hit="$(grep -Ein -m1 -e "$re" "$tmp/paths" 2>/dev/null | head -1)" || hit=""
    num="${hit%%:*}"
    if [ -n "$hit" ] && { [ "$best" = 0 ] || [ "$num" -lt "$best" ]; }; then best="$num"; bestkind="$k"; fi
  done
  _load_extras
  if [ -n "$_EXTRA_LIST" ]; then
    printf '%s\n' "$_EXTRA_LIST" > "$tmp/extra"
    hit="$(grep -Ein -m1 -f "$tmp/extra" "$tmp/paths" 2>/dev/null | head -1)" || hit=""
    num="${hit%%:*}"
    if [ -n "$hit" ] && { [ "$best" = 0 ] || [ "$num" -lt "$best" ]; }; then best="$num"; bestkind="extra"; fi
  fi
  if [ -n "$links" ]; then
    num="${links%% *}"
    if [ "$best" = 0 ] || [ "$num" -lt "$best" ]; then best="$num"; bestkind="submodule"; fi
  fi
  if [ "$best" != 0 ]; then
    printf 'full %s: %s\n' "$bestkind" "$(sed -n "${best}p" "$tmp/paths")"
    return 0
  fi
  # Data loss: an ADDED line in a non-doc file. One diff, one awk pass emits "path<TAB>line"
  # records; a quoted header (`+++ "b/..."`, used for tabs, quotes, backslashes) is unquoted.
  git -C "$root" -c core.quotePath=false diff --no-renames -U0 "$base" "$head" 2>/dev/null | awk '
    /^\+\+\+ / { p = substr($0, 5); sub(/\t$/, "", p)
      if (p == "/dev/null") { cur = ""; skip = 1; next }
      if (p ~ /^"/) { sub(/^"/, "", p); sub(/"$/, "", p); gsub(/\\"/, "\"", p); gsub(/\\t/, "\t", p); gsub(/\\\\/, "\\", p) }
      sub(/^b\//, "", p); cur = p
      skip = ('"$_DOC_AWK"'); next }
    /^--- / { next }
    /^\+/ { if (cur != "" && !skip) print cur "\t" substr($0, 2) }
  ' > "$tmp/added"
  [ -s "$tmp/added" ] || return 0
  local T=$'\t' rec=""
  rec="$(grep -Ei -m1 -e "${T}.*(${_HL_common})" "$tmp/added" | head -1)" || rec=""
  [ -n "$rec" ] || rec="$(grep -Ei -e "${T}.*delete[[:space:]]+from" "$tmp/added" | grep -Eiv -e 'where' | head -1)" || true
  [ -n "$rec" ] || rec="$(grep -Ei -e "${T}.*delete[[:space:]]+from.*where[[:space:]]+(1[[:space:]]*=[[:space:]]*1|true)([^a-z0-9_]|\$)" "$tmp/added" | head -1)" || true
  [ -n "$rec" ] || rec="$(grep -Ei -m1 -e "^[^${T}]*\.sql${T}${_HL_truncate_sql}" "$tmp/added" | head -1)" || true
  [ -n "$rec" ] || rec="$(grep -Ei -m1 -e "${T}.*${_HL_truncate_code}" "$tmp/added" | head -1)" || true
  [ -z "$rec" ] || printf 'full data-loss: %s\n' "${rec%%$T*}"
  return 0
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    classify) _extract_files "$@"; classify_core ${REMAIN[@]+"${REMAIN[@]}"}; _emit_suggest; printf '%s\n' "$LANE";;
    explain)  _extract_files "$@"; classify_core ${REMAIN[@]+"${REMAIN[@]}"}; _emit_suggest
              printf '%s\nreason: %s\nflags: %s\n' "$LANE" "$REASON" "${FIRED:-none}"
              [ -z "$SUGGEST" ] || printf 'suggest: full (%s)\n' "$SUGGEST";;
    check)    _extract_files "$@"; lane_check ${REMAIN[@]+"${REMAIN[@]}"};;
    escalate)   escalate "$@";;
    floor)      floor "$@";;
    deescalate) deescalate "$@";;
    lanes)    printf 'tiny\nnormal\nfull\nbug\nbackfill\n';;
    flags)    printf '%s\n' "${_hard_name[@]}" "${_soft_name[@]}";;
    *) echo "usage: lane-classify.sh {classify [--files \"<paths>\"] \"<desc>\"|explain [--files ...] \"<desc>\"|check [--files ...] <chosen-lane> \"<desc>\"|escalate <current-lane> <spec-file>|floor <root> [<base>]|deescalate <chosen-lane> [--rid <rid>] [--root <path>] [--base <ref>] [--floor <N>]|lanes|flags}" >&2; return 64;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
