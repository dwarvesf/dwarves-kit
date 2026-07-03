#!/usr/bin/env bash
# weekend-batch.sh -- the debt-paydown reader/closer (ADR-0031 §3, SPEC-126, understanding-gate SG-05).
#
# Flow B (the weekend batch): reads the EXISTING debt ledger (`| DEBT |` markers, SPEC-123's
# `gate-ledger.sh debt`) and surfaces the week's WAVED + DEFERRED items -- the conscious debt ADR-
# 0031's Refinement says is fine to postpone, as long as it eventually gets paid down. This is a
# READER + a single CLOSER, never a second ledger: it never writes anything except the same
# `gate-ledger.sh debt` marker SPEC-123 already writes, with the additive `response=engage` key.
#
# Disposition rules (read off the LAST `| DEBT |` line for a given rid; the ledger is append-only,
# so "last" == "current"):
#
#   verdict=not-significant                  -> never debt, never collected
#   response=engage (any verdict)            -> PAID, never re-collected
#   verdict=wave,   no response              -> WAVED  (SG-02's silent anti-fatigue path)  COLLECT
#   response=wave                            -> WAVED  (an explicit human wave, SG-04)     COLLECT
#   response=defer                           -> DEFERRED                                    COLLECT
#   verdict=tap,    no response              -> PENDING (an open (unresolved) tap; still Flow A's
#                                                to resolve -- the batch does not race it)  skip
#
# The kit does not reinvent pedagogy or a second dedup/batching engine here (ADR-0031,
# Alternatives): this lib is the dwarves-kit-generic collection half. The ORCHESTRATION into the
# operator's ops-toolkit learning skills (learning-day-process / learning-ledger / deep-understand
# / til) is a separate, operator-specific Claude Code skill in the dotfiles repo -- see SPEC-126.
#
# Usage:
#   weekend-batch.sh list    [--days N] [--since <ISO8601>] [--repo <name>] [--all-repos]
#     -> tab-separated: rid \t disposition \t significance \t worthiness \t recorded-ts
#   weekend-batch.sh collect [--days N] [--since <ISO8601>] [--repo <name>] [--all-repos] [--repo-root <path>]
#     -> a markdown digest: one `## <rid>` block per collectible item, with best-effort-resolved
#        impl-notes/explainer paths (relative to --repo-root; default: this cwd's repo root).
#   weekend-batch.sh mark-paid <rid> [--note "<text>"]
#     -> re-emits the rid's last significance/worthiness/verdict with response=engage (closes it).
#
# DWARVES_KIT_LOG_DIR overrides the durable log-dir resolver (see lib/kit-log-dir.sh); tests point
# it at a temp dir so the fixture ledger never touches the real machine corpus.

set -euo pipefail

WB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_LEDGER="$WB_DIR/gate-ledger.sh"

# shellcheck source=lib/kit-log-dir.sh
source "$WB_DIR/kit-log-dir.sh" || { echo "weekend-batch: lib/kit-log-dir.sh missing or unreadable" >&2; exit 1; }
kit_migrate_log_dir || true
LOG_DIR="$(kit_resolve_log_dir)"
RUNS_DIR="$LOG_DIR/runs"

# _cutoff_iso <days> -- "now minus <days> days" as an ISO8601 Z timestamp. Portable: BSD `date`
# (macOS) needs `-v-Nd`; GNU `date` (Linux/CI) needs `-d "-N days"`. ISO8601 Z timestamps sort
# correctly as PLAIN STRINGS (zero-padded, same zone), so every other comparison in this file is a
# string compare -- this is the only place date arithmetic happens at all.
_cutoff_iso() {
  local days="$1"
  if date -v-1d >/dev/null 2>&1; then
    date -u -v-"${days}"d +%Y-%m-%dT%H:%M:%SZ
  else
    date -u -d "-${days} days" +%Y-%m-%dT%H:%M:%SZ
  fi
}

# _default_repo -- the basename of the cwd's repo root, matching the `repo=` value START() writes
# (gate-ledger.sh start(): `repo="$(basename "$(git rev-parse --show-toplevel ...)")"`). Empty if
# cwd is not inside a git repo (callers then skip repo filtering rather than filter on "").
_default_repo() {
  local top; top="$(git rev-parse --show-toplevel 2>/dev/null)" || { printf ''; return; }
  basename "$top"
}

# _repo_root -- the repo root impl-notes/explainer paths resolve against.
_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

DAYS=7; SINCE=""; REPO_FILTER=""; ALL_REPOS=0; REPO_ROOT=""

# _parse_common "$@" -- shared flag parsing for list/collect. Leaves nothing in REMAIN (these
# subcommands take no positional args); unrecognized flags are a hard error (fail loud, not silent).
_parse_common() {
  DAYS=7; SINCE=""; REPO_FILTER=""; ALL_REPOS=0; REPO_ROOT=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --days)      DAYS="$2"; shift 2 ;;
      --since)     SINCE="$2"; shift 2 ;;
      --repo)      REPO_FILTER="$2"; shift 2 ;;
      --all-repos) ALL_REPOS=1; shift ;;
      --repo-root) REPO_ROOT="$2"; shift 2 ;;
      *) echo "weekend-batch: unknown flag '$1'" >&2; return 64 ;;
    esac
  done
  [ -n "$SINCE" ] || SINCE="$(_cutoff_iso "$DAYS")"
  if [ "$ALL_REPOS" -eq 0 ] && [ -z "$REPO_FILTER" ]; then
    REPO_FILTER="$(_default_repo)"
  fi
  [ -n "$REPO_ROOT" ] || REPO_ROOT="$(_repo_root)"
  return 0
}

# _file_repo <ledger-file> -- the repo= value from the run's START line (last START-AMEND if one
# exists, else the first plain START -- SPEC-077's read rule). Empty if no START line at all.
#
# Every internal pipeline here is guarded with `|| true`: a "no match" (no START-AMEND line, no
# START line at all) is an EXPECTED, non-error outcome, not a script-ending failure -- and under
# `set -e`+`pipefail`, an unguarded `var=$(grep ... | tail -1)` with no match can abort the whole
# script depending on bash's nesting-depth-dependent errexit propagation into command
# substitutions (a well-known bash sharp edge). Guarding at the source, inside the helper, means
# every caller at any nesting depth is safe without having to know this.
_file_repo() {
  local f="$1" line
  line="$(grep '| START-AMEND |' "$f" 2>/dev/null | tail -n1)" || true
  [ -n "$line" ] || line="$(grep '| START |' "$f" 2>/dev/null | head -n1)" || true
  [ -n "$line" ] || { printf ''; return 0; }
  printf '%s' "$line" | grep -oE 'repo=[^ ]+' | head -n1 | cut -d= -f2- || true
}

# _last_debt_line <ledger-file> -- the LAST `| DEBT |` line (append-only ledger => most recent).
# A file with no debt lines at all is expected (most run ledgers never call gate-ledger.sh debt);
# `|| true` keeps that a clean empty result, never a script-aborting failure.
_last_debt_line() {
  grep '| DEBT |' "$1" 2>/dev/null | tail -n1 || true
}

# _kv <line> <key> -- extract KEY=value (no embedded spaces in the value) from a ledger line.
# Safe even when a later `reason=...` field embeds spaces, because the regex stops at the first
# space. `|| true`: a key that is not present (e.g. `response=` on a silent SG-02 wave) is an
# expected empty result, never a script-aborting failure.
_kv() {
  printf '%s' "$1" | grep -oE "$2=[^ ]+" | head -n1 | cut -d= -f2- || true
}

# _disposition <debt-line> -- prints "waved"|"deferred"|"pending"|"paid"|"not-significant" for the
# LAST debt line of a run (the exact matrix documented in the header + SPEC-126's Design table).
_disposition() {
  local line="$1" verdict response
  verdict="$(_kv "$line" verdict)"
  response="$(_kv "$line" response)"
  if [ "$verdict" = "not-significant" ]; then printf 'not-significant\n'; return; fi
  case "$response" in
    engage) printf 'paid\n'; return ;;
    wave)   printf 'waved\n'; return ;;
    defer)  printf 'deferred\n'; return ;;
  esac
  case "$verdict" in
    wave) printf 'waved\n' ;;
    tap)  printf 'pending\n' ;;
    *)    printf 'unknown\n' ;;
  esac
}

# _collectible_files -- ledger files (one per rid) whose LAST debt line is waved/deferred, within
# the [SINCE, now] window, and passing the repo filter. Prints "<file>\t<disposition>" per match.
_collectible_files() {
  local f rid ts repo disp last
  [ -d "$RUNS_DIR" ] || return 0
  for f in "$RUNS_DIR"/*.log; do
    [ -e "$f" ] || continue
    last="$(_last_debt_line "$f")"
    [ -n "$last" ] || continue
    disp="$(_disposition "$last")"
    case "$disp" in waved|deferred) ;; *) continue ;; esac
    ts="$(printf '%s' "$last" | awk -F' [|] ' '{print $1}')"
    [ -n "$ts" ] && [ "$ts" '>' "$SINCE" -o "$ts" = "$SINCE" ] || continue
    if [ "$ALL_REPOS" -eq 0 ] && [ -n "$REPO_FILTER" ]; then
      repo="$(_file_repo "$f")"
      [ "$repo" = "$REPO_FILTER" ] || continue
    fi
    printf '%s\t%s\n' "$f" "$disp"
  done
}

# _find_artifact <repo-root> <candidate...> -- first existing candidate path, else "". Always
# returns 0 (no candidate found is an expected "absent" outcome the caller reads off the empty
# string, never a script-aborting failure -- same discipline as the other helpers above).
_find_artifact() {
  local root="$1"; shift
  local c
  for c in "$@"; do
    if [ -f "$root/$c" ]; then printf '%s' "$c"; return 0; fi
  done
  printf ''
  return 0
}

# _strip_ug_prefix <rid> -- the understanding-gate mega-goal's rid convention is
# "ug-<NN>-<feature-slug>"; docs/implementation-notes/ + docs/verification/explain-command/ files
# for THAT convention are named by the shorter feature-slug (e.g. "explain-command.md", not
# "ug-03-explain-command.md" -- see SPEC-126 Problem). Other rids (e.g. "cc-hyg-04-stop-tax") have
# no such prefix and the rid IS the slug. Both are tried; this is the best-effort half of that.
_strip_ug_prefix() {
  printf '%s' "$1" | sed -E 's/^ug-[0-9]+-//'
}

cmd_list() {
  _parse_common "$@" || return $?
  local f disp rid last sig wor ts
  _collectible_files | while IFS=$'\t' read -r f disp; do
    [ -n "$f" ] || continue
    rid="$(basename "$f" .log)"
    last="$(_last_debt_line "$f")"
    sig="$(_kv "$last" significance)"
    wor="$(_kv "$last" worthiness)"
    ts="$(printf '%s' "$last" | awk -F' [|] ' '{print $1}')"
    printf '%s\t%s\t%s\t%s\t%s\n' "$rid" "$disp" "$sig" "$wor" "$ts"
  done
}

cmd_collect() {
  _parse_common "$@" || return $?
  local rows f disp rid last sig wor reason ts notes_slug notes_path explainer_path
  rows="$(_collectible_files)"
  local n_waved=0 n_deferred=0 n=0
  local body=""
  while IFS=$'\t' read -r f disp; do
    [ -n "$f" ] || continue
    n=$((n+1))
    [ "$disp" = waved ] && n_waved=$((n_waved+1))
    [ "$disp" = deferred ] && n_deferred=$((n_deferred+1))
    rid="$(basename "$f" .log)"
    last="$(_last_debt_line "$f")"
    sig="$(_kv "$last" significance)"
    wor="$(_kv "$last" worthiness)"
    reason="$(printf '%s' "$last" | grep -oE 'reason=.*' | cut -d= -f2- || true)"
    ts="$(printf '%s' "$last" | awk -F' [|] ' '{print $1}')"

    notes_slug="$(_strip_ug_prefix "$rid")"
    if [ "$ALL_REPOS" -eq 1 ]; then
      notes_path="(cross-repo, --all-repos: paths unresolved)"
      explainer_path="(cross-repo, --all-repos: paths unresolved)"
    else
      notes_path="$(_find_artifact "$REPO_ROOT" "docs/implementation-notes/${rid}.md" "docs/implementation-notes/${notes_slug}.md" || true)"
      if [ -n "$notes_path" ]; then notes_path="$notes_path (found)"; else notes_path="docs/implementation-notes/${rid}.md (absent)"; fi
      explainer_path="$(_find_artifact "$REPO_ROOT" "docs/verification/explain-command/${rid}-explainer.md" "docs/verification/explain-command/${notes_slug}-explainer.md" || true)"
      if [ -n "$explainer_path" ]; then explainer_path="$explainer_path (found)"; else explainer_path="docs/verification/explain-command/${rid}-explainer.md (absent)"; fi
    fi

    body="${body}
## ${rid}
- disposition: ${disp}
- significance: ${sig} / worthiness: ${wor}
- reason: ${reason:-(none recorded)}
- recorded: ${ts}
- impl-notes: ${notes_path}
- explainer: ${explainer_path}
"
  done <<< "$rows"

  echo "# Weekend batch: debt paydown"
  echo
  echo "Window: since ${SINCE}$( [ "$ALL_REPOS" -eq 1 ] && echo " (all repos)" || echo " (repo: ${REPO_FILTER:-unknown})" )"
  echo "Items: ${n} (${n_waved} waved, ${n_deferred} deferred)"
  printf '%s\n' "$body"
}

cmd_mark_paid() {
  local rid="${1:-}"; shift || true
  [ -n "$rid" ] || { echo "usage: mark-paid <rid> [--note \"<text>\"]" >&2; return 64; }
  local note=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --note) note="$2"; shift 2 ;;
      *) echo "weekend-batch: unknown flag '$1'" >&2; return 64 ;;
    esac
  done
  local f; f="$RUNS_DIR/$(printf '%s' "$rid" | tr '/ ' '--' | tr -cd '[:alnum:]._-').log"
  [ -f "$f" ] || { echo "mark-paid: no ledger file for rid '$rid' ($f)" >&2; return 1; }
  local last; last="$(_last_debt_line "$f")"
  [ -n "$last" ] || { echo "mark-paid: rid '$rid' has no debt-ledger entry -- nothing to close" >&2; return 1; }
  local sig wor verdict reason
  sig="$(_kv "$last" significance)"; wor="$(_kv "$last" worthiness)"; verdict="$(_kv "$last" verdict)"
  reason="paid via weekend batch $(date -u +%Y-%m-%d)"
  [ -n "$note" ] && reason="$reason: $note"
  bash "$GATE_LEDGER" debt "$rid" "significance=$sig" "worthiness=$wor" "verdict=$verdict" "response=engage" "reason=$reason"
}

usage() { sed -n '2,35p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    list)      cmd_list "$@" ;;
    collect)   cmd_collect "$@" ;;
    mark-paid) cmd_mark_paid "$@" ;;
    ""|-h|--help|help) usage ;;
    *) echo "weekend-batch.sh: unknown subcommand '$sub'" >&2; usage >&2; exit 64 ;;
  esac
}

main "$@"
