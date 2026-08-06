#!/usr/bin/env bash
# sweep-spec-status.sh (cc-hygiene sub-goal 06)
#
# Reconciles ops-toolkit spec Status fields against merged git history so the
# planning inventory tells the truth. Dry-run by default; --apply flips ONLY the
# specs it can prove shipped. Nothing is deleted. Each flip cites its evidence.
#
# Scope of AUTO-FLIP: central `docs/specs/SPEC-NNN-*.md` ONLY. There SPEC-NNN is
# globally unique in ops-toolkit, so a merged commit referencing it is real
# evidence. Per-tool specs reuse SPEC-001.. across tools, so `git log --grep` is
# ambiguous (found in dry-run: it cross-matched 129 specs); those are NEVER
# auto-flipped -- they go to the residue table for Han. Status-less files
# (CONTEXT/README/proof-of-done adjacents) are counted, not tabled.
#
# Usage:  sweep-spec-status.sh [--apply]
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BASE="${SWEEP_BASE:-origin/main}"
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1

TERMINAL='shipped|parked|dropped|moved|complete|completed|done|merged|abandoned|superseded|reserved|rule'
NONTERM='draft|validated|accepted|approved|implemented|implementing|in.progress|in-progress|proposed|wip|pending|speccing|executing|claimed|deferred|backlog|design.approved'

flip_n=0; residue_n=0; term_n=0; nonec=0
FLIP_ROWS=""; RESIDUE_ROWS=""

# id boundary-safe evidence in a merged commit SUBJECT on BASE.
_evidence() { git -C "$ROOT" log "$BASE" -E --grep "(^|[^0-9A-Za-z])$1([^0-9]|\$)" --oneline 2>/dev/null | head -1; }

_status_of() { grep -m1 -iE '^Status:' "$ROOT/$1" 2>/dev/null | sed -E 's/^[Ss]tatus:[[:space:]]*//' ; }

# ---- central docs/specs: the only AUTO-FLIP scope ----
for f in $(cd "$ROOT" && ls docs/specs/SPEC-*.md 2>/dev/null | sort); do
  [ -f "$ROOT/$f" ] || continue
  id="$(basename "$f" .md | grep -oiE '^SPEC-[0-9]+' | head -1)"
  raw="$(_status_of "$f")"; val="$(printf '%s' "$raw" | tr 'A-Z' 'a-z')"
  short="$(printf '%s' "${val:-<none>}" | cut -c1-30)"
  if [ -z "$val" ]; then nonec=$((nonec+1)); continue; fi
  if printf '%s' "$val" | grep -qiE "^($TERMINAL)"; then term_n=$((term_n+1)); continue; fi
  ev="$(_evidence "$id")"
  if printf '%s' "$val" | grep -qiE "^($NONTERM)" && [ -n "$ev" ]; then
    pr="$(printf '%s' "$ev" | grep -oE '\(#[0-9]+\)' | head -1)"; sha="$(printf '%s' "$ev" | awk '{print $1}')"
    FLIP_ROWS="${FLIP_ROWS}| ${id} | ${short} | shipped | ${sha} ${pr} |"$'\n'; flip_n=$((flip_n+1))
    if [ "$APPLY" = "1" ]; then
      line="$(grep -m1 -iE '^Status:' "$ROOT/$f")"; esc="$(printf '%s' "$line" | sed 's/[.[\*^$/]/\\&/g')"
      sed -i.bak "s/^${esc}\$/Status: SHIPPED (swept 2026-07-02 cc-hyg-06; evidence ${sha} ${pr})/" "$ROOT/$f" && rm -f "$ROOT/$f.bak"
    fi
  else
    reason="no merged commit references ${id}"
    RESIDUE_ROWS="${RESIDUE_ROWS}| ${f} | ${short} | (propose) | ${reason} |"$'\n'; residue_n=$((residue_n+1))
  fi
done

# ---- per-tool specs: residue only, and only the genuinely non-terminal ones ----
for f in $(cd "$ROOT" && find tools -path '*/docs/specs/*.md' 2>/dev/null | sort); do
  [ -f "$ROOT/$f" ] || continue
  raw="$(_status_of "$f")"; val="$(printf '%s' "$raw" | tr 'A-Z' 'a-z')"
  [ -z "$val" ] && { nonec=$((nonec+1)); continue; }
  if printf '%s' "$val" | grep -qiE "^($TERMINAL)"; then term_n=$((term_n+1)); continue; fi
  short="$(printf '%s' "$val" | cut -c1-30)"
  RESIDUE_ROWS="${RESIDUE_ROWS}| ${f} | ${short} | (propose) | per-tool spec id not globally unique; Han decides |"$'\n'; residue_n=$((residue_n+1))
done

echo "### FLIP (central docs/specs, evidenced by a merged commit)"
echo "| spec id | old status | new status | evidence |"; echo "|---|---|---|---|"; printf '%s' "$FLIP_ROWS"
echo ""
echo "### RESIDUE (propose park/drop/documentation, Han decides)"
echo "| spec | status | proposed | reason |"; echo "|---|---|---|---|"; printf '%s' "$RESIDUE_ROWS"
echo ""
echo "summary: flips=$flip_n residue=$residue_n already-terminal=$term_n status-less(skipped)=$nonec apply=$APPLY base=$BASE"
