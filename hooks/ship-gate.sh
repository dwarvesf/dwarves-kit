#!/bin/bash
# ship-gate.sh, PreToolUse hook, matcher: Bash
# Workflow-completeness gate at the ship/push boundary. When a feature
# branch is pushed or a PR is opened, refuse if the active spec's lane has a
# required (measure-twice) gate with no `ran`/`override` entry in its run ledger.
#
# This is a QUALITY gate, not a safety gate: it FAILS OPEN on any ambiguity (no
# repo, no spec, no lane, missing tooling) so a bug here can never block unrelated
# work. push-to-main and force-push stay safety-gate.sh's job. Exit 2 = block.
set -uo pipefail
# Preserve fail-open even on the pathological case (HOME unset under set -u): the lib
# fallback below uses $HOME, so default it to empty rather than error-exit.
HOME="${HOME:-}"
INPUT=$(cat)
# The tool's real cwd: the payload .cwd, else the cwd anchor-root.sh saved before it cd'd
# to the repo root, else $PWD (a direct invocation). A relative `cd` resolves against this.
REAL_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$REAL_CWD" ] || REAL_CWD="${DWARVES_KIT_INVOCATION_CWD:-}"
[ -n "$REAL_CWD" ] || REAL_CWD="$PWD"
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -z "$CMD" ] && exit 0

# Strip heredoc bodies BEFORE the engage check, so "git push" appearing in
# generated prose (PR bodies, test fixtures) never engages the gate. Same normalizer
# shape as safety-gate.sh.
CMD_CODE=$(printf '%s\n' "$CMD" | awk '
  BEGIN { inhd = 0 }
  {
    line = $0
    if (inhd) { t = line; gsub(/^[ \t]+/, "", t); if (t == marker) inhd = 0; next }
    if (match(line, /<<-?[ \t]*["'\'']?[A-Za-z_][A-Za-z0-9_]*["'\'']?/)) {
      m = substr(line, RSTART, RLENGTH)
      sub(/<<-?[ \t]*/, "", m); gsub(/["'\'']/, "", m)
      marker = m; inhd = 1
      line = substr(line, 1, RSTART - 1)
    }
    print line
  }')

# Engage only on a ship action: a git push or a gh pr create (in CODE, not prose). The push
# form allows global options before the verb: `git -C <dir> push`, `git -c k=v push`.
GITPUSH_RE='git([[:space:]]+(-C[[:space:]]+[^[:space:]]+|-c[[:space:]]+[^[:space:]]+|--[a-z][a-z-]*(=[^[:space:]]+)?))*[[:space:]]+push([[:space:]]|$)'
echo "$CMD_CODE" | grep -qE "$GITPUSH_RE|gh[[:space:]]+pr[[:space:]]+create" || exit 0
# The push segment: from `git ... push` to the next command separator.
PUSH_SEG=$(printf '%s' "$CMD_CODE" | grep -oE "${GITPUSH_RE}[^;&|]*" | tail -1 || true)
# Leave force-push to safety-gate. Match the flag exactly: --force-with-lease is a different flag.
case " $PUSH_SEG " in *" --force "*|*" -f "*) exit 0 ;; esac

# A command that cd's elsewhere ships THAT repo, not the session cwd (the
# cross-repo misfire: a `cd other-repo && git push` was gated against the SESSION
# repo's spec). Resolve the repo from a leading cd prefix when present.
# BSD-sed-portable: grab the cd arg with grep -o, then strip the prefix + quotes.
CDDIR=$(printf '%s' "$CMD_CODE" | grep -oE '^[[:space:]]*cd[[:space:]]+[^&;|]+' | head -1 \
  | sed -E 's/^[[:space:]]*cd[[:space:]]+//; s/[[:space:]]+$//; s/^"//; s/"$//' || true)
if [ -z "$CDDIR" ] && [ -n "$PUSH_SEG" ]; then   # `git -C <dir> push` ships that repo
  CDDIR=$(printf '%s' "$PUSH_SEG" | grep -oE '(^|[[:space:]])-C[[:space:]]+[^[:space:]]+' | head -1 | awk '{print $NF}' || true)
fi
case "$CDDIR" in *'$'*) CDDIR="" ;; esac   # variables cannot be resolved: fall back
CDDIR="${CDDIR/#\~/$HOME}"
case "$CDDIR" in ""|/*) ;; *) CDDIR="$REAL_CWD/$CDDIR" ;; esac
# Test affordance: print the resolved cd-target and exit (never set outside tests).
if [ "${DWARVES_KIT_PRINT_CDDIR:-0}" = "1" ]; then printf '%s\n' "$CDDIR"; exit 0; fi
if [ -n "$CDDIR" ] && [ -d "$CDDIR" ]; then
  ROOT=$(git -C "$CDDIR" rev-parse --show-toplevel 2>/dev/null || true)
else
  ROOT=$(git -C "$REAL_CWD" rev-parse --show-toplevel 2>/dev/null || true)
fi
[ -n "$ROOT" ] || exit 0
BRANCH=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
[ -n "$BRANCH" ] || exit 0
CURBRANCH="$BRANCH"
PHEAD=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)   # the commit being shipped
# Which ref does this push carry, and where does it land? A push whose TARGET is the default
# branch is safety-gate's business, so leave it alone. The word main or master elsewhere in the
# command (`gh pr create --base master`, a commit message) is not a target.
if [ -n "$PUSH_SEG" ]; then
  DEFNAME=$(git -C "$ROOT" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
  DEFNAME="${DEFNAME#origin/}"
  read -ra _TOK <<< "${PUSH_SEG#*push}"
  _POS=(); _skip=0
  for _t in ${_TOK[@]+"${_TOK[@]}"}; do
    if [ "$_skip" = 1 ]; then _skip=0; continue; fi
    case "$_t" in
      --repo|-o|--push-option|--receive-pack|--exec) _skip=1 ;;
      -*) ;;
      *) _POS+=("$_t") ;;
    esac
  done
  _SPECS=(${_POS[@]+"${_POS[@]:1}"})
  [ "${#_SPECS[@]}" -gt 0 ] || _SPECS=("$CURBRANCH")
  PUSH_SRC=""; PUSH_DST=""
  for _r in "${_SPECS[@]}"; do
    _r="${_r#+}"
    case "$_r" in *:*) _src="${_r%%:*}"; _dst="${_r#*:}" ;; *) _src="$_r"; _dst="$_r" ;; esac
    _src="${_src#refs/heads/}"; _dst="${_dst#refs/heads/}"
    [ "$_dst" = HEAD ] && _dst="$CURBRANCH"
    case "$_dst" in main|master) exit 0 ;; esac
    [ -n "$DEFNAME" ] && [ "$_dst" = "$DEFNAME" ] && exit 0
    [ -n "$PUSH_SRC" ] || { PUSH_SRC="$_src"; PUSH_DST="$_dst"; }
  done
  # Ship the ref being pushed, not whatever HEAD happens to be.
  if [ -n "$PUSH_SRC" ] && [ "$PUSH_SRC" != "$CURBRANCH" ]; then
    if [ "$PUSH_SRC" = HEAD ]; then BRANCH="$PUSH_DST"
    elif _pr=$(git -C "$ROOT" rev-parse --verify -q "refs/heads/$PUSH_SRC" 2>/dev/null); then BRANCH="$PUSH_SRC"; PHEAD="$_pr"
    fi
  fi
fi
SLUG="${BRANCH#*/}"   # strip the type/ prefix (feat/, docs/, ...)
SLUG_Q=$(printf '%q' "$SLUG")   # shell-safe form for the commands this hook prints

# One copy of the three-way default-branch fallback (review: was duplicated per block).
# The base is the REMOTE default branch: origin/HEAD, else origin/main or origin/master. A local
# branch can carry unpushed commits and would hide them from the diff. Only a repo with no origin
# at all falls back to local main or master. An origin with no remote-tracking default gives no
# base, and the callers skip their checks.
_resolve_base() {
  local ref c
  ref=$(git -C "$ROOT" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
  [ -z "$ref" ] || { echo "$ref"; return 0; }
  if git -C "$ROOT" remote get-url origin >/dev/null 2>&1; then
    for c in origin/main origin/master; do
      git -C "$ROOT" rev-parse --verify -q "$c" >/dev/null 2>&1 && { echo "$c"; return 0; }
    done
    return 0
  fi
  git -C "$ROOT" rev-parse --verify -q main >/dev/null 2>&1 && echo main || echo master
}

# --- Proof-of-done gate (diff-keyed, SPEC-INDEPENDENT). This is the bridge: it fires on
# freeform /goal work too, because it classifies the branch DIFF instead of a spec. A
# load-bearing (behavioral/stateful) change cannot ship without a matching proof-of-done
# entry. Fails open on ambiguity (handled inside proof-ledger). Exit 2 = block. ---
# Resolve the lib from the kit's INSTALL location, not the repo being pushed:
# in bash-install mode CLAUDE_PLUGIN_ROOT is unset, and a consumer repo has no lib/, so a
# $ROOT fallback fails open in every consumer. The stable install path fixes that; plugin
# mode (CLAUDE_PLUGIN_ROOT set) is unchanged.
PROOF="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/dwarves-kit}/lib/gate/proof-ledger.sh"
# [gate] toggles. lib/gate/gate-policy.sh resolves them (project config wins, then the
# operator overlay, then the kit root); this hook never reads the config files itself.
# Only exit 1 from the reader means off. A missing or broken reader (any other exit) means
# ON: switching a gate off has to be explicit. A skip logs one line.
POLICY="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/dwarves-kit}/lib/gate/gate-policy.sh"
_gate_on() {  # $1 = [gate] key, $2 = log label
  [ -f "$POLICY" ] || return 0
  local rc=0; bash "$POLICY" enabled "$1" "$ROOT" || rc=$?
  [ "$rc" -eq 1 ] || return 0
  local LOG_DIR="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | OFF-BY-CONFIG | $2 | $SLUG" >> "$LOG_DIR/ship-gate.log" 2>/dev/null || true
  return 1
}
# Diff floor (hard paths). The path test lives in lib/classify/lane-classify.sh `floor`; this hook
# only calls it, as it calls gate-policy.sh, and fails open on a missing lib. A hit means the
# full lane's gates apply whatever the spec's Lane says.
LCLS="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/dwarves-kit}/lib/classify/lane-classify.sh"
_floor_hit() {  # prints "full <kind>: <path>" for the first hard-path hit, else nothing
  [ -f "$LCLS" ] || return 0
  local fb; fb=$(git -C "$ROOT" merge-base "$PHEAD" "$(_resolve_base)" 2>/dev/null || true)
  [ -n "$fb" ] || return 0
  [ "$fb" != "$(git -C "$ROOT" rev-parse "$PHEAD" 2>/dev/null || true)" ] || return 0
  bash "$LCLS" floor "$ROOT" "$fb" "$PHEAD" 2>/dev/null || true
}
# The floor follows [gate] lane_gates as of the MERGE BASE, never the PR head, so a PR cannot
# switch off its own floor. Only exit 1 from the reader means off.
_floor_on() {
  [ -f "$POLICY" ] || return 0
  local fb rc=0; fb=$(git -C "$ROOT" merge-base "$PHEAD" "$(_resolve_base)" 2>/dev/null || true)
  [ -n "$fb" ] || return 0
  bash "$POLICY" enabled lane_gates "$ROOT" --at "$fb" || rc=$?
  [ "$rc" -eq 1 ] || return 0
  local LOG_DIR="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | OFF-BY-CONFIG | floor | $SLUG" >> "$LOG_DIR/ship-gate.log" 2>/dev/null || true
  return 1
}
# _floor_check: block (exit 2) when the diff hits a hard path and the full lane's gates, read
# from the kit and operator layers only, have not all run. Needs the ledger script.
_floor_check() {
  local FH FGAPS LEDGERF="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/dwarves-kit}/lib/gate/gate-ledger.sh"
  [ -f "$LEDGERF" ] || return 0
  FH=$(_floor_hit); [ -n "$FH" ] || return 0
  _floor_on || return 0
  if ! FGAPS=$(KIT_PROJECT_ROOT="$ROOT" bash "$LEDGERF" check full "$SLUG" --kit-lanes 2>&1); then
    local LOG_DIR="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}" FK="${FH#full }"
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | BLOCKED | ship-gate | $SLUG (hard-path ${FK%%:*})" >> "$LOG_DIR/ship-gate.log" 2>/dev/null || true
    {
      echo "BLOCKED: ship-gate. This diff touches a hard path ($FK); the full lane's gates apply whatever the spec's Lane says:"
      [ -n "${SPEC:-}" ] || echo "(no spec found for '$SLUG'; a hard-path diff owes the full lane's gates with or without one)"
      printf '%s\n' "$FGAPS" | sed 's/^/  /'
      echo "Run the missing gate(s), or log an explicit override (recorded for audit):"
      echo "  bash \"$LEDGERF\" override $SLUG_Q <phase> \"<reason>\""
    } >&2
    exit 2
  fi
  return 0
}
# OPT-IN: engage only in a repo that adopted the proof-of-done convention. A repo with
# no docs/verification/README.md never gets gated (the gate is for kit-adopting repos,
# not every repo the user touches).
if [ -f "$PROOF" ] && [ -f "$ROOT/docs/verification/README.md" ] && _gate_on proof_of_done proof-gate; then
  DEFAULT=$(_resolve_base)
  BASE=$(git -C "$ROOT" merge-base "$PHEAD" "$DEFAULT" 2>/dev/null || true)
  HEADSHA="$PHEAD"
  if [ -n "$BASE" ] && [ "$BASE" != "$HEADSHA" ]; then
    if ! PMSG=$(bash "$PROOF" check "$ROOT" "$BASE" "$SLUG" 2>&1); then
      LOG_DIR="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"
      mkdir -p "$LOG_DIR" 2>/dev/null || true
      echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | BLOCKED | proof-gate | $SLUG" >> "$LOG_DIR/ship-gate.log" 2>/dev/null || true
      printf '%s\n' "$PMSG" >&2
      exit 2
    fi
  fi
  # delivery-ratio advisory (NEVER blocks): surface a proof-heavy
  # branch -- lots of proof-of-done/verification/spec lines wrapped around a near-zero real
  # change -- so a reviewer can spot-check delivery vs the sub-goal's claim. Heuristic with real
  # false positives (a docs sub-goal is proof-heavy by design; a 1-line fix can be load-bearing),
  # so it is a NUDGE, never a gate: fires only on THIN-WARN/NOTICE, silent on OK.
  if [ -n "${BASE:-}" ] && [ "${BASE:-}" != "${HEADSHA:-}" ]; then
    DR=$(bash "$PROOF" delivery-ratio "$ROOT" "$BASE" 2>/dev/null || true)
    case "$DR" in *THIN-WARN*|*NOTICE*) echo "[advisory] delivery-ratio: $DR" >&2 ;; esac
  fi
fi

# Board-registration advisory (never blocks), relocated ABOVE the spec check:
# spec-less freeform pushes are exactly the work most likely to be un-boarded, and the
# old placement exited before the nudge could fire.
if [ -f "$ROOT/_meta/BACKLOG.md" ] && ! grep -E '^\|' "$ROOT/_meta/BACKLOG.md" 2>/dev/null | grep -qF -- "$SLUG"; then
  echo "[advisory] branch slug '$SLUG' appears nowhere in _meta/BACKLOG.md; if this is real work, give it a board row" >&2
fi

# Doc-projection gate (kit repo only): the drift class that shipped twice
# is an agent/command landing without its MANUAL/architecture
# rows. When THIS push touches a projection surface, run the fast grep subset
# (lib/gate/doc-projection-check.sh, ~0.1s; the slow FEATURES regen stays in
# the full suite). Kit repo only by the file-existence scoping (a consumer repo
# has neither file). Escape hatch: DWARVES_KIT_SKIP_DOC_PROJECTION=1.
if [ -f "$ROOT/lib/gate/doc-projection-check.sh" ] && [ -f "$ROOT/tests/test-meta.sh" ] \
   && [ "${DWARVES_KIT_SKIP_DOC_PROJECTION:-0}" != "1" ]; then
  DPBASE=$(git -C "$ROOT" merge-base "$PHEAD" "$(_resolve_base)" 2>/dev/null || true)
  if [ -n "$DPBASE" ] && git -C "$ROOT" diff --name-only "$DPBASE" "$PHEAD" 2>/dev/null \
       | grep -qE '^(agents/|commands/|AGENTS\.md$|docs/(MANUAL|architecture|WORKFLOW)\.md$)'; then
    if ! DPMSG=$(bash "$ROOT/lib/gate/doc-projection-check.sh" "$ROOT" 2>&1); then
      echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | BLOCKED | doc-projection | $SLUG" >> "${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}/ship-gate.log" 2>/dev/null || true
      {
        echo "BLOCKED: doc-projection drift. This push touches a projection surface and the derived doc rows are out of sync:"
        printf '%s\n' "$DPMSG"
        echo "Fix the named rows (or run 'bash tests/test-meta.sh' for the full picture). Escape: DWARVES_KIT_SKIP_DOC_PROJECTION=1."
      } >&2
      exit 2
    fi
  fi
fi

# Feature-registry freshness gate (kit repo only): docs/FEATURES.md is a
# generated projection whose inputs are the whole feature surface, including
# tests/test-*.sh and docs/specs/SPEC-*.md (the Tests and Specs columns are
# token greps). An author adding a test file has no reason to think about a docs
# projection, so the drift lands, the suite's pin goes red on master, and every
# later merge commit inherits it (2026-09, fixed by hand a PR later). Regenerate
# and byte-diff via the registry's own check verb, so the gate and the pin can
# never disagree about what fresh means.
#
# The regen costs ~20s, so it runs only on the shape of that incident: an input
# moved and docs/FEATURES.md did NOT. A push that carries the regenerated file
# skips it; whether that regeneration was CORRECT is what tests/test-meta.sh
# pins in CI. Escape hatch: DWARVES_KIT_SKIP_REGISTRY_FRESHNESS=1.
if [ -f "$ROOT/lib/registry/feature-registry.sh" ] && [ -f "$ROOT/docs/FEATURES.md" ] \
   && [ "${DWARVES_KIT_SKIP_REGISTRY_FRESHNESS:-0}" != "1" ]; then
  FRBASE=$(git -C "$ROOT" merge-base "$PHEAD" "$(_resolve_base)" 2>/dev/null || true)
  FRDIFF=""
  [ -n "$FRBASE" ] && FRDIFF=$(git -C "$ROOT" diff --name-only "$FRBASE" "$PHEAD" 2>/dev/null || true)
  if [ -n "$FRDIFF" ] && ! printf '%s\n' "$FRDIFF" | grep -qx 'docs/FEATURES\.md' \
     && printf '%s\n' "$FRDIFF" | grep -qE '^(commands/[^/]+\.md|agents/[^/]+\.md|skills/[^/]+/SKILL\.md|hooks/[^/]+\.sh|hooks/hooks\.json|settings\.json|tests/test-[^/]+\.sh|docs/specs/SPEC-[^/]+\.md)$'; then
    if ! FRMSG=$(bash "$ROOT/lib/registry/feature-registry.sh" check "$ROOT/docs/FEATURES.md" 2>&1); then
      echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | BLOCKED | registry-freshness | $SLUG" >> "${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}/ship-gate.log" 2>/dev/null || true
      {
        echo "BLOCKED: registry freshness. This push edits an input of docs/FEATURES.md and the generated projection has drifted:"
        printf '%s\n' "$FRMSG" | head -40
        echo "Regenerate and commit it:"
        echo "  bash lib/registry/feature-registry.sh generate docs/FEATURES.md"
        echo "Escape: DWARVES_KIT_SKIP_REGISTRY_FRESHNESS=1."
      } >&2
      exit 2
    fi
  fi
fi

# Build-ran advisory (never blocks): a run that recorded real build work but
# ships no committable verification record dies with the session (the run ledger is
# gitignored by design). The proof-gate BLOCKS behavioral diffs in adopted repos; this
# covers its deliberate fail-open seams (non-adopted repo, tests/CI-only diff). Lane
# comes from the ledger's own START line, never the spec; base is computed locally.
# Placed deliberately AFTER the proof block: in adopted repos a behavioral diff already
# hard-BLOCKS above; this covers only the proof-gate's fail-open seams.
LEDGER62="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/dwarves-kit}/lib/gate/gate-ledger.sh"
if [ -f "$LEDGER62" ]; then
  RLED=$(bash "$LEDGER62" show "$SLUG" 2>/dev/null || true)
  # RLANE derived from START unconditionally (review: descent must not depend on the
  # build-ran gate; a run can violate order without ever recording build).
  RLANE=$( { printf '%s' "$RLED" | grep '| START-AMEND |' | tail -1; printf '%s' "$RLED" | grep '| START |' | head -1; } | head -1 | sed -nE 's/.*\| lane=([a-z-]+).*/\1/p')
  if printf '%s' "$RLED" | grep -q '| GATE | build | ran'; then
    case "$RLANE" in
      normal|full|bug)
        DEF62=$(_resolve_base)
        BASE62=$(git -C "$ROOT" merge-base "$PHEAD" "$DEF62" 2>/dev/null || true)
        if [ -n "$BASE62" ] && ! git -C "$ROOT" diff --name-only "$BASE62" "$PHEAD" 2>/dev/null \
            | grep -E '^docs/verification/.+\.md$|(^|/)proof-of-done\.md$' \
            | grep -vq '/README\.md$'; then
          echo "[advisory] run '$SLUG' (lane $RLANE) recorded a build but this branch ships no docs/verification/ record; the session ledger is not committable evidence" >&2
        fi ;;
    esac
  fi
fi

# V-model descent advisory (never blocks): phases recorded out of the
# lane's plan order. Lane from the ledger START line (same source as the build-ran warn).
if [ -f "$LEDGER62" ] && [ -n "${RLANE:-}" ]; then
  DOUT=$(bash "$LEDGER62" descent "$SLUG" "$RLANE" 2>/dev/null || true)
  DN=$(printf '%s' "$DOUT" | grep -c '^DESCENT:' || true)
  if [ "${DN:-0}" -gt 0 ] 2>/dev/null; then
    echo "[advisory] run '$SLUG': $DN descent violation(s), phases recorded before an earlier plan phase disposed; see: bash <kit>/lib/gate/gate-ledger.sh descent $SLUG $RLANE" >&2
  fi
fi

# Resolve the spec for this slug; fail open if there is no spec-driven run.
SPEC=$(ls "$ROOT"/docs/specs/SPEC-*-"$SLUG".md 2>/dev/null | head -1 || true)
if [ -z "$SPEC" ]; then
  # No spec means no lane to compare, but the floor needs no lane: a hard-path diff still owes the
  # full lane's gates (or an audited override) for this slug. Renaming a branch must not dodge it.
  _floor_check
  exit 0
fi

# Test-plan coverage advisory (never blocks): the spec carries a ## Test plan, so the proof-of-done owes
# a ## Test plan coverage map -- each matrix row mapped to the run that exercised it, or an
# explicit skip reason (shape: docs/verification/README.md "Test plan coverage map"). WARNS
# on a missing map or unmapped rows; no test plan in the spec = no new requirement.
PGATE="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/dwarves-kit}/lib/gate/proof-gate.sh"
if [ -f "$PGATE" ] && grep -qE '^## Test plan[[:space:]]*$' "$SPEC" 2>/dev/null; then
  # repo-root proof homes for this slug (flat file, dir layout, runs/); co-located
  # tools/*/docs/proof-of-done.md has no slug linkage, deliberately not scanned.
  PFILES=$(ls "$ROOT/docs/verification/$SLUG.md" "$ROOT/docs/verification/$SLUG"/*.md \
              "$ROOT/docs/verification/$SLUG"/runs/*.md 2>/dev/null || true)
  # shellcheck disable=SC2086  # PFILES is a newline list of repo paths, splitting intended
  COV=$(bash "$PGATE" coverage "$SPEC" $PFILES 2>/dev/null || true)
  case "$COV" in
    NO-MAP*)   echo "[advisory] test-plan coverage: spec '$SLUG' has a ## Test plan ($COV) but no proof doc for the slug carries a '## Test plan coverage' map; map each matrix row to its run or an explicit skip reason (docs/verification/README.md)" >&2 ;;
    UNMAPPED*) echo "[advisory] test-plan coverage: proof map for '$SLUG' leaves test-plan matrix rows unmapped ($COV); map each row to a run or an explicit skip reason" >&2 ;;
  esac
fi

# `Lane: full` is the canonical header. Markdown-bold variants (`**Lane**: full`,
# `**Lane:** full`) parse the same, because a spec author reaching for the bold form
# used elsewhere in the header block should not get a BLOCKED push. A leading `- `
# list marker is deliberately NOT accepted: specs use `- **Lane:** ...` for prose
# bullets, and accepting it would parse a sentence as the lane.
LANE=$(grep -m1 -iE '^(\*\*)?Lane(\*\*)?:' "$SPEC" 2>/dev/null | sed -E 's/^(\*\*)?[Ll]ane(\*\*)?:(\*\*)?[[:space:]]*//; s/[[:space:]].*$//' || true)
if [ -z "$LANE" ]; then
  # Spec exists but declares no lane. In an ADOPTED repo (proof marker present) this is a gap,
  # not a pass: fail CLOSED so a spec-driven change cannot ship lane-less (the growatt-tui hole).
  # Everywhere else (no marker) stay fail-open: the gate never blocks unrelated work.
  if [ -f "$ROOT/docs/verification/README.md" ] && _gate_on lane_gates lane-gate; then
    LOG_DIR="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | BLOCKED | ship-gate | $SLUG (no-lane)" >> "$LOG_DIR/ship-gate.log" 2>/dev/null || true
    {
      echo "BLOCKED: ship-gate. Spec '$SLUG' has no 'Lane:' header, so its required gates cannot be checked."
      echo "Add a lane to $SPEC (e.g. 'Lane: full'). Classify with:"
      echo "  bash \"${CLAUDE_PLUGIN_ROOT:-\$HOME/.claude/dwarves-kit}/lib/classify/lane-classify.sh\" classify \"<task>\""
      echo "Or switch the lane gates off for this repo: [gate] lane_gates = false in the committed project kit config (lib/gate/README.md, 'Switching a gate off')."
    } >&2
    exit 2
  fi
  _floor_check
  exit 0
fi

LEDGER="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/dwarves-kit}/lib/gate/gate-ledger.sh"
[ -f "$LEDGER" ] || exit 0

# Bracket the ship gate with an OUTCOME emit (caught= + START/END timing). This is
# the live invocation path for the additive OUTCOME marker. It is BEST-EFFORT and writes ONLY
# to the rid ledger, so it can never change this hook's fail-open contract, exit code, or
# operator output. caught=true when the check BLOCKS (it caught a missing-gate defect),
# caught=false on a clean pass. The `outcome` marker keys on $2=="OUTCOME"; check()/_rows()/
# the ship-gate's own read all ignore it (they key on $2=="GATE").
# The floor reads the switch at the merge base, so it still runs when the head switched the gate off.
if ! _gate_on lane_gates lane-gate; then _floor_check; exit 0; fi
bash "$LEDGER" outcome "$SLUG" ship start >/dev/null 2>&1 || true

if ! GAPS=$(KIT_PROJECT_ROOT="$ROOT" bash "$LEDGER" check "$LANE" "$SLUG" 2>&1); then
  bash "$LEDGER" outcome "$SLUG" ship end caught=true >/dev/null 2>&1 || true
  LOG_DIR="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | BLOCKED | ship-gate | $SLUG ($LANE)" >> "$LOG_DIR/ship-gate.log" 2>/dev/null || true
  {
    echo "BLOCKED: ship-gate. The '$LANE' lane requires gates that have not run for spec '$SLUG':"
    printf '%s\n' "$GAPS" | sed 's/^/  /'
    echo "Run the missing gate(s), or log an explicit override (recorded for audit):"
    echo "  bash \"$LEDGER\" override $SLUG_Q <phase> \"<reason>\""
    echo "Or switch the lane gates off for this repo: [gate] lane_gates = false in the committed project kit config (lib/gate/README.md, 'Switching a gate off')."
  } >&2
  exit 2
fi
# Hard-path floor: full-lane gates, project lane data ignored (--kit-lanes). Exits 2 on a gap.
_floor_check
bash "$LEDGER" outcome "$SLUG" ship end caught=false >/dev/null 2>&1 || true
# Suggestion not taken: the ledger holds a lane-suggest full action and the run ships lighter.
if [ "$LANE" != "full" ] && printf '%s' "${RLED:-}" | grep -q '| ACTION | lane-suggest full'; then
  SUGF=$(printf '%s' "$RLED" | sed -nE 's/.*lane-suggest full flags=([^ ]*).*/\1/p' | tail -1)
  echo "[advisory] run '$SLUG': the classifier suggested full (${SUGF:-unknown}) and the run ships as $LANE" >&2
fi
exit 0
