#!/usr/bin/env bash
# pitch.sh -- the assembly engine behind /kit:pitch (Design 4, SPEC-140).
#
# Turns a shipped change into an OUTWARD-facing buy-in doc: re-audiences artifacts a gated
# run ALREADY produced (the spec, the proof-of-done, the implementation-notes, the gate
# ledger's grill/DEBT records) for a third-party approver. Sibling to lib/explain.sh (the
# INWARD lens -- background -> diff -> diagram, for operator understanding, ending in a
# quiz); this is the OUTWARD lens -- outcome -> unknowns -> evidence -> cost -> ask, for
# buy-in. Same grounding discipline as explain.sh: every section traces to a file on disk or
# a ledger line; a missing source produces an EXPLICIT absence line, never invented content.
# This is the ONLY thing that makes "never fabricate" a property of the code rather than of
# instruction-following (SPEC-140 Design, approach #3).
#
# <rid> doubles as the spec/proof/implementation-notes slug, per this repo's own convention
# (SPEC-070: the branch slug IS the spec slug IS the implementation-notes filename).
#
# Usage:
#   pitch.sh outcome      <rid>            one-paragraph outcome from the spec (or absence line)
#   pitch.sh unknowns     <rid>            grill record + impl-notes deviations + proof NCs
#   pitch.sh evidence     <rid>            proof-of-done run-table/runs section verbatim + PR link
#   pitch.sh cost         <rid>            spec Out-of-scope/Not-changed + ponytail markers
#   pitch.sh ask          <rid>            the templated approval ask
#   pitch.sh render       <rid> [--out F]  the full 5-section assembled doc
#   pitch.sh team-shared                   exit 0 ("yes") if the repo's GitHub owner is an
#                                           Organization, exit 1 ("no") otherwise or on any
#                                           `gh` failure (fail-safe: never blocks, never nags
#                                           on uncertain data)
#
# Boundaries (SPEC-140 Out of Scope): this file NEVER shells out to `gh pr comment`, `gh
# issue comment`, a Discord/Slack webhook, or `curl`. Output is stdout or --out, full stop.

set -uo pipefail

PITCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_ROOT="$PITCH_DIR"  # this is a bare root-level module; the lib/ dir IS its own dir. Cross-subsystem siblings resolve as "$LIB_ROOT/<subsystem>/<file>"
GATE_LEDGER="$LIB_ROOT/gate/gate-ledger.sh"

# _safe_slug <slug> -- refuse a slug that could escape the intended docs/ subtree via the
# filesystem globs below (review finding, self spec-validate Reviewer 1: a crafted rid like
# "../../../etc/passwd" must not walk `_find_spec`/`_find_proof`/`_find_impl_notes` outside
# their directory). Real rids never contain "/" or ".." (gate-ledger.sh's own runid() already
# strips "/" before ever writing a ledger file); this is a cheap read-side mirror of that
# guard, not a new convention.
_safe_slug() {
  case "$1" in
    *[/\\]*|*..*) return 1 ;;
    "") return 1 ;;
    *) return 0 ;;
  esac
}

_find_spec() {
  local slug="$1" f
  _safe_slug "$slug" || return 1
  f="$(ls docs/specs/SPEC-*-"$slug".md 2>/dev/null | head -1)"
  [ -n "$f" ] && [ -f "$f" ] && printf '%s' "$f"
}

# _find_proof <slug> -- the two homes (docs/verification/README.md): flat, nested-canonical,
# nested-latest-run, in that order (SPEC-140 Decision Log DEC-003: the kit's own three real
# proof files disagree on shape today, so all three are tried).
_find_proof() {
  local slug="$1" latest
  _safe_slug "$slug" || return 1
  if [ -f "docs/verification/$slug.md" ]; then
    printf '%s' "docs/verification/$slug.md"; return 0
  fi
  if [ -f "docs/verification/$slug/proof-of-done.md" ]; then
    printf '%s' "docs/verification/$slug/proof-of-done.md"; return 0
  fi
  latest="$(ls -t "docs/verification/$slug"/runs/*.md 2>/dev/null | head -1)"
  [ -n "$latest" ] && printf '%s' "$latest"
}

_find_impl_notes() {
  local slug="$1" f
  _safe_slug "$slug" || return 1
  f="docs/implementation-notes/$slug.md"
  [ -f "$f" ] && printf '%s' "$f"
}

# _ledger_show <rid> -- read-only pass-through to gate-ledger.sh show; empty (never an error)
# when there is no ledger for this rid, so every caller below degrades the same way an
# absent file does.
_ledger_show() {
  bash "$GATE_LEDGER" show "$1" 2>/dev/null || true
}

_ledger_grill() {
  _ledger_show "$1" | grep '| GATE | grill |' | tail -1
}

# _ledger_pr <rid> -- the last numeric `pr=#N` recorded on a `ship` GATE line. A `pr=pending`
# line (recorded before the PR exists, commands/ship.md Step 8) never matches the digit
# class, so it is correctly skipped in favor of a later real PR number.
_ledger_pr() {
  _ledger_show "$1" | grep '| GATE | ship |' | grep -oE 'pr=#[0-9]+' | tail -1 | sed -E 's/^pr=#//'
}

_pr_url() {
  local num="$1" remote owner_repo
  [ -n "$num" ] || return 1
  remote="$(git remote get-url origin 2>/dev/null)" || return 1
  owner_repo="$(printf '%s' "$remote" | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')"
  [ -n "$owner_repo" ] || return 1
  printf 'https://github.com/%s/pull/%s' "$owner_repo" "$num"
}

# _first_para <heading> <file> -- the first CONTIGUOUS non-blank block under a "## <heading>"
# section (i.e. the section's first paragraph, stopping at the first blank line reached AFTER
# at least one non-blank line has printed), not an arbitrary line-count truncation -- a
# numbered-list Solution (common in this kit's specs) must not be sliced mid-list-item.
_first_para() {
  local heading="$1" file="$2"
  awk -v h="^## ${heading}\$" '
    $0 ~ h  { f=1; next }
    /^## /  { f=0 }
    f {
      if ($0 ~ /^[[:space:]]*$/) { if (started) exit; else next }
      started=1; print
    }
  ' "$file"
}

# --- section 1: Outcome -----------------------------------------------------------------
cmd_outcome() {
  local rid="$1" spec body pr
  spec="$(_find_spec "$rid")" || spec=""
  if [ -z "$spec" ]; then
    echo "[no spec found for '$rid'; outcome not assembled]"
    return 0
  fi
  echo "**$(head -1 "$spec" | sed -E 's/^# //')**"
  echo
  body="$(_first_para Solution "$spec")"
  if [ -z "$body" ]; then
    body="$(_first_para Problem "$spec")"
  fi
  [ -n "$body" ] && printf '%s\n' "$body"
  pr="$(_ledger_pr "$rid")"
  if [ -n "$pr" ]; then
    echo
    echo "Shipped as PR #${pr}."
  fi
}

# --- section 2: Unknowns we accounted for -----------------------------------------------
cmd_unknowns() {
  local rid="$1" g notes proof ncs
  echo "### Grill record"
  g="$(_ledger_grill "$rid")"
  if [ -z "$g" ]; then
    echo "- no grill record for this run"
  else
    echo "- $g"
  fi
  echo
  echo "### Implementation-notes deviations"
  notes="$(_find_impl_notes "$rid")" || notes=""
  if [ -z "$notes" ]; then
    echo "- no implementation-notes file for this run"
  elif grep -qE '^No deviations; matches .* verbatim' "$notes"; then
    grep -E '^No deviations; matches .* verbatim' "$notes" | sed 's/^/- /'
  else
    awk '/^## [0-9]{4}-[0-9]{2}-[0-9]{2}/{print; f=1; next} /^## /{f=0} f' "$notes"
  fi
  echo
  echo "### Negative controls (from the proof)"
  proof="$(_find_proof "$rid")" || proof=""
  if [ -z "$proof" ]; then
    echo "- no proof recorded, so no negative controls to report"
  else
    ncs="$(grep -iE 'negative control' "$proof" | sed -E 's/^[[:space:]#*_`-]*//; s/[[:space:]]*$//' | sort -u)"
    if [ -z "$ncs" ]; then
      echo "- no negative control recorded in the proof for this run"
    else
      printf '%s\n' "$ncs" | sed 's/^/- /'
    fi
  fi
}

# --- section 3: Evidence -----------------------------------------------------------------
cmd_evidence() {
  local rid="$1" proof table pr url
  proof="$(_find_proof "$rid")" || proof=""
  if [ -z "$proof" ]; then
    echo "[no proof-of-done file for this run]"
  else
    echo "Source: \`$proof\`"
    echo
    table="$(awk '/^## Acceptance criteria/{f=1;next} /^## /{f=0} f' "$proof")"
    if ! printf '%s' "$table" | grep -q '^|'; then
      table="$(awk '/^## Confirmation run/{f=1;next} /^## /{f=0} f' "$proof")"
    fi
    if [ -z "$(printf '%s' "$table" | sed '/^[[:space:]]*$/d')" ]; then
      table="$(awk '/^## Runs$/{f=1;next} /^## /{f=0} f' "$proof")"
    fi
    if [ -z "$(printf '%s' "$table" | sed '/^[[:space:]]*$/d')" ]; then
      echo "[no acceptance-criteria table, confirmation run, or Runs section found; showing the whole proof file]"
      cat "$proof"
    else
      printf '%s\n' "$table"
    fi
  fi
  echo
  pr="$(_ledger_pr "$rid")"
  if [ -n "$pr" ]; then
    url="$(_pr_url "$pr")" || url=""
    if [ -n "$url" ]; then echo "PR: $url"; else echo "PR: #$pr"; fi
  else
    echo "no PR reference recorded for this run"
  fi
}

# --- section 4: Cost / not shipped -------------------------------------------------------
cmd_cost() {
  local rid="$1" spec notes scope hits
  spec="$(_find_spec "$rid")" || spec=""
  if [ -z "$spec" ]; then
    echo "[no spec found for this run]"
  else
    scope="$(awk '/^## Out of [Ss]cope$/{f=1;next} /^## /{f=0} f' "$spec" | sed '/^[[:space:]]*$/d')"
    if [ -z "$scope" ]; then
      scope="$(grep -iE 'not changed:|out of scope' "$spec" | sed -E 's/^[[:space:]]*//')"
    fi
    if [ -z "$scope" ]; then
      echo "- no explicit exclusions recorded for this run"
    else
      printf '%s\n' "$scope"
    fi
  fi
  echo
  echo "### Ponytail markers (deliberate known ceilings)"
  notes="$(_find_impl_notes "$rid")" || notes=""
  hits=""
  [ -n "$spec" ] && hits="${hits}$(grep -in 'ponytail' "$spec" 2>/dev/null || true)"$'\n'
  [ -n "$notes" ] && hits="${hits}$(grep -in 'ponytail' "$notes" 2>/dev/null || true)"$'\n'
  hits="$(printf '%s' "$hits" | sed '/^[[:space:]]*$/d')"
  if [ -z "$hits" ]; then
    echo "- no ponytail markers referenced in the spec/impl-notes for this run"
  else
    printf '%s\n' "$hits" | sed 's/^/- /'
  fi
}

# --- section 5: The ask ------------------------------------------------------------------
cmd_ask() {
  local rid="$1" pr url spec
  pr="$(_ledger_pr "$rid")"
  if [ -n "$pr" ]; then
    url="$(_pr_url "$pr")" || url=""
    if [ -n "$url" ]; then
      echo "Approve and merge ${url} (rid \`$rid\`)."
    else
      echo "Approve and merge PR #$pr (rid \`$rid\`)."
    fi
    return 0
  fi
  spec="$(_find_spec "$rid")" || spec=""
  if [ -n "$spec" ]; then
    echo "Review \`$spec\` and confirm ship-readiness for \`$rid\` (no PR reference recorded yet)."
  else
    echo "Confirm ship-readiness for \`$rid\` (no spec or PR reference found)."
  fi
}

# --- team-shared: the ship-time predicate (SPEC-140 Decision Log DEC-002) ----------------
cmd_team_shared() {
  local t
  t="$(gh api repos/'{owner}'/'{repo}' --jq '.owner.type' 2>/dev/null)" || { echo "no"; return 1; }
  if [ "$t" = "Organization" ]; then echo "yes"; return 0; else echo "no"; return 1; fi
}

# --- render: the full 5-section assembled doc --------------------------------------------
cmd_render() {
  local rid="$1"; shift
  local out=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --out) out="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  _render_body() {
    echo "# Pitch: \`${rid}\`"
    echo
    echo "> Outward buy-in doc, assembled from artifacts a gated run already produced (the"
    echo "> spec, the proof-of-done, the implementation-notes, the gate ledger's grill/DEBT"
    echo "> records). Never new analysis; a missing source is reported honestly, never"
    echo "> invented. The inward twin is \`/kit:explain\` (operator understanding); this is"
    echo "> the outward lens (third-party buy-in)."
    echo
    echo "## 1. Outcome"
    echo
    cmd_outcome "$rid"
    echo
    echo "## 2. Unknowns we accounted for"
    echo
    cmd_unknowns "$rid"
    echo
    echo "## 3. Evidence"
    echo
    cmd_evidence "$rid"
    echo
    echo "## 4. Cost / not shipped"
    echo
    cmd_cost "$rid"
    echo
    echo "## 5. The ask"
    echo
    cmd_ask "$rid"
  }

  if [ -n "$out" ]; then
    _render_body > "$out"
    echo "wrote $out"
  else
    _render_body
  fi
}

usage() {
  sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    outcome)      cmd_outcome "$@" ;;
    unknowns)     cmd_unknowns "$@" ;;
    evidence)     cmd_evidence "$@" ;;
    cost)         cmd_cost "$@" ;;
    ask)          cmd_ask "$@" ;;
    render)       cmd_render "$@" ;;
    team-shared)  cmd_team_shared "$@" ;;
    ""|-h|--help|help) usage ;;
    *) echo "pitch.sh: unknown subcommand '$sub'" >&2; usage >&2; exit 2 ;;
  esac
}

main "$@"
