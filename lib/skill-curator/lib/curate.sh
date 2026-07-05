#!/usr/bin/env bash
# curate.sh: the skill-library curator. A no-write `claude -p` pure function returns a consolidation
# PLAN; the trusted wrapper writes a human-readable report and (only with --apply) archives skills
# via `git mv` to skills/_archive/ , NEVER `rm`. Propose-only by default. Sourced by bin/cc-improve.
#
# Test seam: CC_SI_CURATOR_CMD overrides the claude call (emits a claude -p envelope whose .result
# is the plan JSON), so the inventory/plan/report/archive/restore logic tests with no live model.

HERE_CURATE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE_CURATE/common.sh"

_curate_reserved() { case "$1" in _archive|_rejected|_replaced) return 0;; *) return 1;; esac; }

# curate_inventory: JSON array [{name, description, first_para, mtime, pinned}] over skills/.
curate_inventory() {
  local arr="[]" d name desc para pinned mt
  [ -d "$CC_SI_SKILLS_DIR" ] || { printf '[]'; return 0; }
  for d in "$CC_SI_SKILLS_DIR"/*/; do
    [ -d "$d" ] || continue; name="$(basename "$d")"; _curate_reserved "$name" && continue
    [ -f "$d/SKILL.md" ] || continue
    desc="$(sed -n 's/^description:[[:space:]]*//p' "$d/SKILL.md" | head -1)"
    pinned=false
    grep -qiE '^(pinned|cc-si-protected):[[:space:]]*true' "$d/SKILL.md" && pinned=true
    # first non-frontmatter, non-heading paragraph
    para="$(awk 'BEGIN{fm=0} /^---[[:space:]]*$/{fm++; next} fm>=2 && NF && $0 !~ /^#/ {print; exit}' "$d/SKILL.md")"
    mt="$(stat -f %m "$d/SKILL.md" 2>/dev/null || stat -c %Y "$d/SKILL.md" 2>/dev/null || echo 0)"
    arr="$(jq -c --arg n "$name" --arg de "$desc" --arg p "$para" --argjson mt "${mt:-0}" --argjson pin "$pinned" \
      '. + [{name:$n, description:$de, first_para:$p, mtime:$mt, pinned:$pin}]' <<<"$arr")"
  done
  printf '%s' "$arr"
}

run_curator() {  # stdin = prompt+inventory; stdout = claude -p envelope
  if [ -n "${CC_SI_CURATOR_CMD:-}" ]; then CLAUDE_REVIEWING=1 bash -c "$CC_SI_CURATOR_CMD"
  else CLAUDE_REVIEWING=1 claude -p --bare --no-session-persistence --allowedTools "" \
    --model "$(cfg curator_model "$(cfg model haiku)")" --max-turns "$(cfg max_turns 2)" --output-format json 2>>"$CC_SI_LOG"; fi
}

# _archive_one <name> <absorbed_into>: git mv to _archive/ (never rm); non-git -> mv + manifest + warn.
_archive_one() {
  local name="$1" absorbed="${2:-null}" src="$CC_SI_SKILLS_DIR/$1" arc="$CC_SI_SKILLS_DIR/_archive"
  [ -d "$src" ] || { si_log "curate: archive skip, no skill '$name'"; return 1; }
  # Wrapper guard: never archive a pinned/protected skill even if a (mis)plan names it.
  if grep -qiE '^(pinned|cc-si-protected):[[:space:]]*true' "$src/SKILL.md" 2>/dev/null; then
    si_log "curate: REFUSED archive of pinned/protected skill '$name'"; return 1
  fi
  mkdir -p "$arc" 2>/dev/null || return 1
  local ts; ts="$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || echo '?')"
  if git -C "$CC_SI_SKILLS_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$CC_SI_SKILLS_DIR" mv "$name" "_archive/$name" 2>/dev/null \
      || mv "$src" "$arc/$name" 2>/dev/null || return 1
  else
    mv "$src" "$arc/$name" 2>/dev/null || return 1
    si_log "curate: WARN skills/ is not a git repo; archived '$name' by mv (git-restore unavailable)"
  fi
  printf '%s\t%s\t%s\n' "$name" "$ts" "$absorbed" >> "$arc/manifest.tsv" 2>/dev/null || true
  si_log "curate: archived '$name' -> _archive/ (absorbed_into=$absorbed)"
}

# curate_run [--apply]: propose-only report by default; --apply executes the archive moves.
curate_run() {
  local apply=0; [ "${1:-}" = "--apply" ] && apply=1
  local inv; inv="$(curate_inventory)"
  mkdir -p "$CC_SI_STATE_DIR" 2>/dev/null || true
  # Heartbeat for vps-mon liveness (scheduled job). Must come AFTER the state dir exists.
  printf '%s' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || echo now)" > "$CC_SI_STATE_DIR/curator.heartbeat" 2>/dev/null || true
  if [ "$inv" = "[]" ]; then echo "curate: no skills under $CC_SI_SKILLS_DIR , nothing to consolidate"; return 0; fi

  local input envelope result plan
  input="$(cat "$HERE_CURATE/../prompts/curator.md"; printf '\n\n=== SKILL INVENTORY ===\n%s\n' "$inv")"
  envelope="$(printf '%s' "$input" | run_curator)"
  result="$(jq -r '.result // empty' <<<"$envelope" 2>/dev/null)"
  plan="$(printf '%s' "$result" | grep -vE '^[[:space:]]*(```([a-z]*)?|🐱 Neko-san)[[:space:]]*$')"
  if ! jq -e . >/dev/null 2>&1 <<<"$plan"; then
    si_log "curate: curator returned no valid plan (logged, not fatal)"; echo "curate: no plan (curator unavailable / bad JSON); nothing changed" >&2; return 0
  fi

  local report
  report="$CC_SI_STATE_DIR/curator-report-$(date +%Y%m%d-%H%M%S).md"
  { echo "# cc-improve curate report"
    if [ "$apply" = 1 ]; then echo "## APPLY MODE , archives were executed (git mv, never rm)."
    else echo "## REPORT ONLY , nothing was changed. Re-run with --apply to execute the archives below."; fi
    echo; jq -r '.report // "(no narrative)"' <<<"$plan"
    echo; echo "## Proposed archives"
    jq -r '(.archive // []) | if length==0 then "(none)" else (.[] | "- \(.name) , \(.reason) , absorbed_into=\(.absorbed_into // "null")") end' <<<"$plan"
    echo; echo "## Proposed clusters"
    jq -r '(.clusters // []) | if length==0 then "(none)" else (.[] | "- \(.move) \(.umbrella): \(.members|join(", ")) , \(.rationale)") end' <<<"$plan"
  } > "$report" 2>/dev/null
  echo "curate: report -> $report"

  if [ "$apply" = 1 ]; then
    local name absorbed n=0
    while IFS=$'\t' read -r name absorbed; do
      [ -n "$name" ] || continue
      _archive_one "$name" "$absorbed" && n=$((n+1))
    done < <(jq -r '(.archive // [])[] | "\(.name)\t\(.absorbed_into // "null")"' <<<"$plan")
    echo "curate --apply: archived $n skill(s) via git mv to _archive/ (none deleted)"
  else
    local cnt; cnt="$(jq -r '(.archive // []) | length' <<<"$plan")"
    echo "curate: propose-only , $cnt archive candidate(s); nothing changed. Review $report, then --apply."
  fi
}

# curate_restore <name>: reverse an archive (git mv back, or mv on a non-git host).
curate_restore() {
  local name="${1:-}"; [ -n "$name" ] || { echo "restore: need a skill name" >&2; return 2; }
  local arc="$CC_SI_SKILLS_DIR/_archive/$name"
  [ -d "$arc" ] || { echo "restore: '$name' is not in _archive/" >&2; return 2; }
  if git -C "$CC_SI_SKILLS_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$CC_SI_SKILLS_DIR" mv "_archive/$name" "$name" 2>/dev/null || mv "$arc" "$CC_SI_SKILLS_DIR/$name" 2>/dev/null || { echo "restore: move failed" >&2; return 5; }
  else
    mv "$arc" "$CC_SI_SKILLS_DIR/$name" 2>/dev/null || { echo "restore: move failed" >&2; return 5; }
  fi
  echo "restore: '$name' <- _archive/"; si_log "curate: restored '$name' from _archive/"
}
