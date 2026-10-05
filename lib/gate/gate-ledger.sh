#!/usr/bin/env bash
# gate-ledger.sh -- lane-aware gate ledger + action log + ship-completeness check.
#
# The single source for "which gates a lane requires" is the [lane.<name>] data in
# kit.toml, read through lib/gate/lane-data.sh (kit root, operator overlay, and a committed
# project .kit.toml). A phase in `phases` and not in `light` => the gate is REQUIRED for
# that lane; docs/WORKFLOW.md carries the human view. Records are append-only,
# operator-readable, and redacted (no command bodies). See docs/decisions/0024-gate-ledger-and-ship-enforcement.md.
#
# Subcommands:
#   required <lane>                     print the lane's required gate keys
#   start    <rid> <chosen-lane> <classified-lane> <chosen-type> [classified-type] [repo]   record routing facts
#   start --amend <same args>           sanctioned correction; readers take the last AMEND
#   record   <rid> <phase> <ran|skipped> [reason]   append a gate decision (a `grill`+`skipped`
#                                       reason MUST start with reason=<home-turf|density-low|
#                                       operator-wave>; every other phase/state is free text)
#   action   <rid> <text>              append an action-log line
#   debt     <rid> significance=<low|high> worthiness=<low|high> verdict=<tap|wave|not-significant> [reason=...]
#                                       append an understanding-debt verdict;
#                                       additive marker, ignored by check()/override()/descent()
#   debt-response <rid> <engage|defer|wave> [reason]  append the HUMAN's ★-tap choice;
#                                       additive `| DEBT |` marker, same ignore rules as debt
#   outcome  <rid> <phase> <start|end> [caught=<true|false>] [policy=<close|escalate|continue>]
#                                       record a gate's OUTCOME as an ADDITIVE marker:
#                                       a start/end timing bracket (duration derivable) +
#                                       caught=<bool> + an optional named failure-policy
#                                       (docs/patterns/failure-policy.md); ignored by
#                                       check()/override()/descent()/_rows() (key on $2==GATE)
#   outcome-read <rid> [phase]         read the outcome + duration back for a rid (round-trip)
#   config   <rid> [model=] [effort=] [kit_version=] [modules=] [lane=] [task_type=] [suite_hash=] [session_id=] [phase=]
#                                       record a run's config dimensions as an ADDITIVE marker
#                                       (bench-plane prerequisite); repeat with a
#                                       different phase= for per-stage model stamping
#   override <rid> <phase> <reason>    record a human override for a gate
#   plan-record <rid> <lane> [--ran <phase>[:<reason>]]... [--skipped <phase>:<reason>]...
#               [--override <phase>:<reason>]...
#                                       dispose EVERY phase of the lane's plan in one call
#                                       (`ship` may be omitted: the push records it); refuses
#                                       and writes NOTHING on any invalid disposition
#   inherit  <rid> full --from <parent-rid>
#                                       write one override line per spec-level gate (think..test-plan)
#                                       whose LAST state in the parent ledger is ran; refuses and
#                                       writes nothing otherwise; never build/review/docs/ship/reflect
#   check    <lane> <rid> [--kit-lanes]  exit 0 if every required gate has a ran|override entry; else 1
#                                       (--kit-lanes reads the kit root lane data only)
#   show     <rid>                     print the run's ledger
#   plan     <lane>                    the lane's ordered phase checklist
#   progress <rid> <lane>              plan x ledger -> "step k/n" + checklist
#   rid                                the canonical run id for the cwd: branch slug
#   descent  <rid> <lane>              plan-order timeline check; violations detected, never blocked
#   history  [--lane L] [--json]       one row per run: lane, repo, ran/skipped counts
#   report   --period week|month [--lane L]   markdown table of runs in the window + totals
#   validate-round open <rid> <spec>          pin the spec blob + repo snapshot, open the
#                                       parallel validation round's OUTCOME brackets
#   validate-round close <rid> <token> verdict=<APPROVED|NEEDS-REVISION> critical=<n>
#               warnings=<n> agents=<n> r6=<design-bearing=... pass|critical: ...>
#               [summary=<text>]              write the round's records + `ROUND close`;
#                                       bare `close <rid> <token>` resumes a `closing`
#                                       round; drift voids the round (2; a second void
#                                       since the last round-terminal exits 3)
#   validate-round incomplete <rid> <token> <reason>   record a stopped round
#   validate-round incomplete <rid> --stale <reason>   same, token from the last ROUND
#                                       (`| ROUND |` lines are additive; marker-keyed
#                                       readers skip them)
set -euo pipefail

GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_ROOT="$(cd "$GATE_DIR/.." && pwd)"  # the lib/ dir; cross-subsystem siblings resolve as "$LIB_ROOT/<subsystem>/<file>"
KIT_ROOT="$(cd "$GATE_DIR/../.." && pwd)"  # repo root = two levels above lib/<subsystem>/
# shellcheck source=lib/gate/lane-data.sh
source "$GATE_DIR/lane-data.sh" || { echo "FATAL: lib/gate/lane-data.sh missing or unreadable" >&2; exit 1; }
# --kit-lanes (check only): lane reads use the kit root file only (no project, no operator overlay). Set per call, never exported.
LANES_KIT_ONLY=""
# Durable run-telemetry root: resolve + one-time additive migration out of the
# ~/.claude/dwarves-kit reinstall blast zone. One resolver, no hard-coded default here.
# shellcheck source=lib/telemetry/kit-log-dir.sh
source "$LIB_ROOT/telemetry/kit-log-dir.sh" || { echo "FATAL: lib/telemetry/kit-log-dir.sh missing or unreadable" >&2; exit 1; }
# The ONE append substrate: row-append + root-location live here, not re-implemented
# below. gate-ledger's writes route through ledger_append; reads still use ledger_file()'s path.
# shellcheck source=lib/ledger/ledger.sh
source "$LIB_ROOT/ledger/ledger.sh" || { echo "FATAL: lib/ledger/ledger.sh missing or unreadable" >&2; exit 1; }
# The slug -> spec pick that ship-gate also uses (root docs/specs, then co-located */docs/specs).
# shellcheck source=lib/spec/spec-find.sh
# A stale install without spec-find.sh keeps the root-only lookup (mirrors hooks/ship-gate.sh).
if ! source "$LIB_ROOT/spec/spec-find.sh" 2>/dev/null; then
  spec_files() { ls "$1"/docs/specs/SPEC-*.md 2>/dev/null; return 0; }
  spec_for_slug() { [ -n "$2" ] || return 0; ls "$1"/docs/specs/SPEC-*-"$2".md 2>/dev/null | head -1 || true; return 0; }
fi
# The ledger-verdict cache keys (_lane_fp, _file_id), shared with lane-telemetry's cache.
# shellcheck source=lib/gate/ledger-key.sh
source "$GATE_DIR/ledger-key.sh" || { echo "FATAL: lib/gate/ledger-key.sh missing or unreadable" >&2; exit 1; }
kit_migrate_log_dir || true
LOG_DIR="$(kit_resolve_log_dir)" || exit 1
RUNS_DIR="$LOG_DIR/runs"

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
# Machine-readable epoch seconds for duration math. `date +%s` is identical on
# GNU (ubuntu) and BSD (macOS); we deliberately do NOT parse the ISO8601 now() back to epoch
# (that is the `date -d` vs `date -jf` portability trap the kit CI fails on). Duration is a
# pure integer subtraction of two epochs carried explicitly on the OUTCOME start/end lines.
now_epoch() { date +%s; }

# Collapse newlines/carriage-returns in operator/LLM-supplied free text to spaces before it
# is written to the append-only ledger (security review B1). Without this, a reason/action
# containing an embedded newline splits into extra pipe-delimited lines that readers
# (check/progress/descent + the override guard) cannot distinguish from real GATE
# lines -- a prompt-injection -> ledger-forgery -> gate-bypass chain (a forged `| ran |`
# line makes check() believe a required gate ran). One ledger line per call, always.
oneline() { printf '%s' "${*:-}" | tr '\n\r' '  '; }

# TTY-gated colors: escape codes emit ONLY on an interactive stdout with
# NO_COLOR unset, so every piped consumer (300+ test pins, scripts) sees plain bytes.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_DONE=$'\033[32m'; C_CUR=$'\033[1;33m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
  C_DONE=""; C_CUR=""; C_DIM=""; C_BOLD=""; C_OFF=""
fi
runid() { printf '%s' "$1" | tr '/ ' '--' | tr -cd '[:alnum:]._-'; }
ledger_file() {
  # Guard (review S1): a slug of only special chars normalizes to "",
  # which would silently merge audit trails into a hidden RUNS_DIR/.log.
  local safe; safe="$(runid "$1")"
  [ -n "$safe" ] || { echo "ledger_file: rid '$1' normalizes to an empty filename" >&2; return 1; }
  printf '%s/%s.log' "$RUNS_DIR" "$safe"
}

# Append ONE line to this rid's run ledger, ROUTED through the substrate: the
# substrate owns "compute root + mkdir + append", so gate-ledger no longer re-implements it.
# The stream is always `runs/<safe>.log`, the same file ledger_file() names for reads.
append_run_line() {
  local safe; safe="$(runid "$1")"
  [ -n "$safe" ] || { echo "append_run_line: rid '$1' normalizes to an empty filename" >&2; return 1; }
  ledger_append "runs/$safe.log" "$2"
}

# Stable key for a phase name: drop "(...)", lowercase, spaces -> dashes.
# "Design (opt-in)"->design, "Design critique (opt-in)"->design-critique,
# "Test plan (opt-in)"->test-plan, "Debug (off-cycle)"->debug, "UI design"->ui-design.
normalize_phase() {
  # collapse newlines first (security review, defense-in-depth): a phase arg with an embedded
  # newline would otherwise emit a second physical ledger line. Unreachable today (all callers
  # pass a hardcoded phase literal), but the guard is one tr and matches oneline()'s intent.
  local p
  if [[ "$1" =~ ^[[:lower:][:digit:]][[:lower:][:digit:]-]*$ ]]; then
    p="$1"   # already a stable key (every lane-data phase is): the pipeline below returns it unchanged, minus five spawns
  else
    p="$(printf '%s' "$1" | tr '\n\r' '  ' | sed -E 's/\([^)]*\)//g' | tr 'A-Z' 'a-z' \
      | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/[[:space:]]+/-/g')"
  fi
  # Alias command-name drift: agents recording ad-hoc sometimes use the command name
  # ("execute") instead of the matrix gate it owns ("build"), leaving check() blind to a
  # build that ran (seen 2026-07-21, finance-warehouse run). "verify" is NOT aliased to
  # "review": /kit:verify (right-arm re-run) and /kit:review (code review) are distinct gates.
  # "battery" is /kit:battery's own beat: distinct attribution in stats, but it satisfies
  # the same review gate the ship-gate checks (it IS the fresh-context review).
  case "$p" in execute) p=build ;; battery) p=review ;; esac
  printf '%s' "$p"
}

# print "<phase>\t<cell>" for each phase of the lane, in plan order (cell = measure-twice|run-lite).
# Empty output and nonzero exit => unknown lane (not in the lane data, or malformed).
lane_cells() { lane_rows "$1" ${LANES_KIT_ONLY:+kit}; }

required() {
  local lane="${1:-}"; [ -n "$lane" ] || { echo "usage: required <lane>" >&2; return 64; }
  local rows ph cell
  rows="$(lane_cells "$lane")" || { echo "unknown lane '$lane' (no valid [lane.$lane] data in kit.toml)" >&2; return 1; }
  while IFS=$'\t' read -r ph cell; do
    [ "$cell" = "measure-twice" ] && printf '%s\n' "$(normalize_phase "$ph")"
  done <<< "$rows"
  return 0
}

# START records the run's routing facts for lane telemetry: the lane the
# operator chose, the classifier's suggestion, the work type, and the repo. One line per
# run, written at assign/start time; lib/telemetry/lane-telemetry.sh aggregates these read-side.
start() {
  # --amend: a sanctioned correction. Writes START-AMEND; every
  # reader takes the LAST START-AMEND, else the FIRST plain START. Append-only stands.
  local marker=START uprefix=start
  if [ "${1:-}" = "--amend" ]; then marker=START-AMEND; uprefix="start --amend"; shift; fi
  local rid="${1:-}" lane="${2:-}" classified="${3:-}" type="${4:-}" ctype="${5:-}" repo="${6:-}"
  if [ -z "$rid" ] || [ -z "$lane" ] || [ -z "$classified" ] || [ -z "$type" ]; then
    echo "usage: $uprefix <rid> <chosen-lane> <classified-lane> <chosen-type> [classified-type] [repo]" >&2; return 64
  fi
  [ -n "$repo" ] || repo="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
  # the KV blob is space-split read-side; a space in any value corrupts the parse
  repo="$(printf '%s' "$repo" | tr ' ' '-')"
  type="$(printf '%s' "$type" | tr ' ' '-')"
  ctype="$(printf '%s' "$ctype" | tr ' ' '-')"
  lane="$(printf '%s' "$lane" | tr ' ' '-')"
  classified="$(printf '%s' "$classified" | tr ' ' '-')"
  mkdir -p "$RUNS_DIR"
  local line
  line="$(printf '%s | %s | lane=%s classified=%s type=%s' "$(now)" "$marker" "$lane" "$classified" "$type")"
  [ -n "$ctype" ] && line="$line ctype=$ctype"
  append_run_line "$rid" "$(printf '%s repo=%s' "$line" "$repo")"
  # A committed project override that dropped phases from this lane: say so in the ledger.
  local dp f; f="$(ledger_file "$rid")"
  while IFS= read -r dp; do
    [ -n "$dp" ] || continue
    grep -qF "| GATE | $dp | skipped | repo lane override (.kit.toml)" "$f" 2>/dev/null && continue
    record "$rid" "$dp" skipped "repo lane override (.kit.toml)"
  done < <(lane_dropped "$lane")
}

record() {
  local rid="${1:-}" raw="${2:-}" state="${3:-}"; shift 3 2>/dev/null || { echo "usage: record <rid> <phase> <ran|skipped> [reason]" >&2; return 64; }
  case "$state" in ran|skipped) ;; *) echo "state must be ran|skipped" >&2; return 64;; esac
  local phase; phase="$(normalize_phase "$raw")"
  local reason; reason="$(oneline "$@")"
  # Grill unknown-density conditioning: a grill SKIP must carry a reason= token from
  # the closed enum below, as the FIRST word of its reason text, so the kit's least-used,
  # highest-leverage gate (82% skipped over a 63-run probe) is auditable, not free text. The
  # sibling harness-observatory `kit_gates` reader treats this field as opaque text either way
  # (DECISIONS.md "01-kit-gates-lens"); the enum is enforced HERE, at write time, so a malformed
  # skip is refused before it ever lands, not caught later at analysis time. Every other
  # (phase, state) combination -- including grill+ran, and skipped on any OTHER phase -- is
  # behaviorally identical to before this change.
  if [ "$phase" = "grill" ] && [ "$state" = "skipped" ]; then
    # CLOSED enum, not a prefix match (security review MEDIUM finding): the bare token
    # ("reason=home-turf") or the token followed by its documented ":" delimiter
    # ("reason=home-turf: <why>") both match; a look-alike like "reason=home-turfish-nonsense"
    # does NOT, since it is neither exactly the token nor token+":".
    case "$reason" in
      reason=home-turf|reason=home-turf:*) ;;
      reason=density-low|reason=density-low:*) ;;
      reason=operator-wave|reason=operator-wave:*) ;;
      *)
        echo "record: a grill skip needs reason=<home-turf|density-low|operator-wave> (bare, or followed by ':') as its reason (got: '${reason:-<empty>}')" >&2
        return 64
        ;;
    esac
  fi
  mkdir -p "$RUNS_DIR"
  append_run_line "$rid" "$(printf '%s | GATE | %s | %s | %s' "$(now)" "$phase" "$state" "$reason")"
}

action() {
  local rid="${1:-}"; shift 2>/dev/null || { echo "usage: action <rid> <text>" >&2; return 64; }
  mkdir -p "$RUNS_DIR"
  append_run_line "$rid" "$(printf '%s | ACTION | %s' "$(now)" "$(oneline "$@")")"
}

# tokens: record a run's token usage as an ADDITIVE marker. Emits a `| TOKENS |` line
# that check()/override()/descent()/_rows() all ignore (they key on $2=="GATE"|START|ACTION), so a
# token line can never fake a gate. Values are sanitized to non-negative integers.
#
# `phase=` (rung-4 redteam cost checkpoint) is an OPTIONAL, purely additive key: when given, the
# TOKENS line is scoped to one gate phase (e.g. `phase=redteam`) instead of the whole rid. The
# `kit_gates` reader (lib/stats read_kit_gates, dwarves-kit lib/stats) pairs a phase-scoped TOKENS
# line to its GATE row the SAME way it already pairs an `| OUTCOME |` bracket: FIFO per (rid,
# phase), so a `cost=` value lands on the matching gate row instead of only the rid-wide total
# lane-telemetry's `_token_agg` already reads. Omitting `phase=` reproduces the exact pre-existing
# line shape (no behavior change for any existing caller).
# Usage: tokens <rid> in=N out=N cache_read=N cache_create=N [cost=N] [phase=P]
tokens() {
  local rid="${1:-}"; shift 2>/dev/null || { echo "usage: tokens <rid> in=N out=N cache_read=N cache_create=N [cost=N] [phase=P]" >&2; return 64; }
  [ -n "$rid" ] || { echo "tokens requires a rid" >&2; return 64; }
  local intok=0 outtok=0 cread=0 ccreate=0 cost="" phase="" kv k v
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    case "$k" in
      in)           intok="$(printf '%s' "$v" | tr -cd '0-9')"; intok="${intok:-0}" ;;
      out)          outtok="$(printf '%s' "$v" | tr -cd '0-9')"; outtok="${outtok:-0}" ;;
      cache_read)   cread="$(printf '%s' "$v" | tr -cd '0-9')"; cread="${cread:-0}" ;;
      cache_create) ccreate="$(printf '%s' "$v" | tr -cd '0-9')"; ccreate="${ccreate:-0}" ;;
      cost)         cost="$(printf '%s' "$v" | tr -cd '0-9.')" ;;   # decimal dollars: digits + dot(s); display-only, never summed
      phase)        phase="$(normalize_phase "$v")" ;;             # same normalizer the GATE/OUTCOME phase key uses
    esac
  done
  mkdir -p "$RUNS_DIR"
  local line; line="$(printf 'in=%s out=%s cache_read=%s cache_create=%s' "$intok" "$outtok" "$cread" "$ccreate")"
  [ -n "$cost" ] && line="$line cost=$cost"
  [ -n "$phase" ] && line="$line phase=$phase"
  append_run_line "$rid" "$(printf '%s | TOKENS | %s' "$(now)" "$line")"
}

# debt: record an understanding-debt verdict as an ADDITIVE marker,
# the exact `| TOKENS |` shape reused for a second concern: a `| DEBT |` line that check()/
# override()/descent()/_rows() all ignore (they key on $2=="GATE"|START|ACTION), so a debt
# line can never fake a gate or be mistaken for one. Written by `lib/classify/significance-classify.sh
# record` (the worker side: "the worker session writes the significance/
# worthiness marker"); the human-facing ★-tap nudge (engage/defer/wave) is a LATER, SEPARATE
# `| DEBT |` line appended by the conductor-side nudge -- this command only ever
# writes the classifier's verdict, never a human response.
#
# response=<engage|defer|wave> (understanding-gate): an OPTIONAL additive key,
# the three-way human disposition the Refinement point 3 names. First written by
# `lib/reflect/weekend-batch.sh mark-paid` (response=engage, closing the loop so a paid item is never
# re-collected); the future ★-tap nudge is a second, later caller of the SAME field --
# there is exactly one place a human response is recorded, never two.
# Usage: debt <rid> significance=<low|high> worthiness=<low|high> verdict=<tap|wave|not-significant> [response=<engage|defer|wave>] [reason=...]
debt() {
  local rid="${1:-}"; shift 2>/dev/null || { echo "usage: debt <rid> significance=<low|high> worthiness=<low|high> verdict=<tap|wave|not-significant> [response=<engage|defer|wave>] [reason=...]" >&2; return 64; }
  [ -n "$rid" ] || { echo "debt requires a rid" >&2; return 64; }
  local sig="" wor="" verdict="" response="" reason="" kv k v
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    case "$k" in
      significance) sig="$v" ;;
      worthiness)   wor="$v" ;;
      verdict)      verdict="$v" ;;
      response)     response="$v" ;;
      # Security LOW (TIER-4 close): a reason value containing a literal "=" can smuggle a
      # fake control token (e.g. "reason=response=engage") past a naive downstream KV-parse
      # (weekend-batch.sh's _kv, which greps the whole line). Belt-and-suspenders alongside
      # the struct-prefix cut in weekend-batch.sh: neuter it here at the source by replacing
      # "=" with ":" (matches the pre-existing "sig:full-lane" reason-text convention), so a
      # reason can never contain a real KEY=value control token.
      reason)       reason="$(oneline "$v" | tr '=' ':')" ;;
    esac
  done
  case "$sig" in low|high) ;; *) echo "debt: significance must be low|high (got '$sig')" >&2; return 64;; esac
  case "$wor" in low|high) ;; *) echo "debt: worthiness must be low|high (got '$wor')" >&2; return 64;; esac
  case "$verdict" in tap|wave|not-significant) ;; *) echo "debt: verdict must be tap|wave|not-significant (got '$verdict')" >&2; return 64;; esac
  if [ -n "$response" ]; then
    case "$response" in engage|defer|wave) ;; *) echo "debt: response must be engage|defer|wave (got '$response')" >&2; return 64;; esac
  fi
  mkdir -p "$RUNS_DIR"
  local line; line="$(printf 'significance=%s worthiness=%s verdict=%s' "$sig" "$wor" "$verdict")"
  [ -n "$response" ] && line="$line response=$response"
  [ -n "$reason" ] && line="$line reason=$reason"
  append_run_line "$rid" "$(printf '%s | DEBT | %s' "$(now)" "$line")"
}

# debt-response: record the HUMAN's ★-tap choice as the SEPARATE `| DEBT |` line the debt() header
# anticipates. Where debt() writes the CLASSIFIER's verdict (worker side), this
# writes the conductor-side human response to a `tap`: engage (pull the quiz) / defer (weekend batch)
# / wave (accept the debt knowingly). All three are logged , the only real failure is UNTRACKED
# debt, so waving is a first-class RECORDED choice, never a hard block. Same additive shape: check()/
# override()/descent()/_rows() ignore `| DEBT |`, so a response line can never fake or mask a gate.
#
# FORWARD-CARRY (TIER-4 close finding): the classifier (`debt()`) writes a FAT line
# (significance=/worthiness=/verdict=); this command historically wrote a THIN line (response= only,
# no sig/wor/verdict). The ledger is last-line-wins for readers, so any consumer that re-emits the
# LAST debt line's sig/wor/verdict through the fat `debt` verb (e.g. weekend-batch.sh mark-paid) saw
# empty enums and crashed -- and at the time this fix landed, `significance-classify record` (the
# fat writer) was unwired anywhere, making a thin-only debt-response the DEFAULT path, not an edge
# case. `record` was later wired into `/kit:ship` Step 8 (before the quiz-gate tap), so a live
# gate/gated-final ship now writes the fat line first; this forward-carry stays load-bearing for
# any rid predating that wiring and for non-gate ships (record's scope is gate/gated-final only,
# unchanged since). Fix: look back at the ledger for THIS rid's last FAT line (one carrying
# verdict=) and, if found, re-emit its sig/wor/verdict alongside response= -- making the response
# line self-describing without inventing data. If no fat line exists (a non-gate ship, or a rid
# from before that wiring), write the thin line as before; blank stays blank.
# Usage: debt-response <rid> <engage|defer|wave> [reason]
debt_response() {
  local rid="${1:-}" response="${2:-}"; shift 2 2>/dev/null || { echo "usage: debt-response <rid> <engage|defer|wave> [reason]" >&2; return 64; }
  [ -n "$rid" ] || { echo "debt-response requires a rid" >&2; return 64; }
  case "$response" in engage|defer|wave) ;; *) echo "debt-response: response must be engage|defer|wave (got '$response')" >&2; return 64;; esac
  # Security LOW (TIER-4 close), same guard as debt(): neuter a "=" in reason so it can never
  # smuggle a control token past a naive downstream KV-parse.
  local reason; reason="$(oneline "$@" | tr '=' ':')"
  mkdir -p "$RUNS_DIR"
  local f; f="$(ledger_file "$rid")" || return 1
  local sig="" wor="" verdict="" last_fat
  if [ -f "$f" ]; then
    last_fat="$(grep '| DEBT |' "$f" 2>/dev/null | grep 'verdict=' | tail -n1)" || true
    if [ -n "$last_fat" ]; then
      sig="$(printf '%s' "$last_fat" | grep -oE 'significance=[^ ]+' | head -n1 | cut -d= -f2-)" || true
      wor="$(printf '%s' "$last_fat" | grep -oE 'worthiness=[^ ]+' | head -n1 | cut -d= -f2-)" || true
      verdict="$(printf '%s' "$last_fat" | grep -oE 'verdict=[^ ]+' | head -n1 | cut -d= -f2-)" || true
    fi
  fi
  local line
  if [ -n "$verdict" ]; then
    line="$(printf 'significance=%s worthiness=%s verdict=%s response=%s' "$sig" "$wor" "$verdict" "$response")"
  else
    line="response=$response"
  fi
  [ -n "$reason" ] && line="$line reason=$reason"
  mkdir -p "$RUNS_DIR"
  append_run_line "$rid" "$(printf '%s | DEBT | %s' "$(now)" "$line")"
}

# outcome: record a gate's OUTCOME as an ADDITIVE marker beside TOKENS + DEBT.
# Emits a `| OUTCOME |` line that check()/override()/descent()/_rows()/_token_agg()/the
# ship-gate all IGNORE (they key on $2=="GATE"|START|START-AMEND|TOKENS|ACTION|DEBT), so an
# outcome line can never fake, mask, or be mistaken for a gate. Mirrors the `| GATE |` field
# layout (field 3 = phase, field 4 = event=start|end). A start/end pair BRACKETS the gate;
# duration is the epoch delta between them (now_epoch = date +%s, portable macOS + ubuntu --
# no date -d/-r, no stat). `caught=` is derived at the CALL SITE from the gate's own recorded
# state (non-pass -> true, clean pass -> false; open-fork 2 default) -- the verb only
# validates + records it, never re-computes it. The timing bracket is unconditional.
# `policy=` is an OPTIONAL, ADDITIVE third field naming which of the kit's three
# failure policies (close/escalate/continue, docs/patterns/failure-policy.md) this outcome
# was: omitted by a caller that doesn't classify one, so old callers and old ledger lines
# are unaffected.
# Usage: outcome <rid> <phase> <start|end> [caught=<true|false>] [policy=<close|escalate|continue>]
outcome() {
  local rid="${1:-}" raw="${2:-}" event="${3:-}"; shift 3 2>/dev/null || { echo "usage: outcome <rid> <phase> <start|end> [caught=<true|false>] [policy=<close|escalate|continue>]" >&2; return 64; }
  [ -n "$rid" ] || { echo "outcome requires a rid" >&2; return 64; }
  local phase; phase="$(normalize_phase "$raw")"
  [ -n "$phase" ] || { echo "outcome requires a phase" >&2; return 64; }
  case "$event" in start|end) ;; *) echo "outcome: event must be start|end (got '$event')" >&2; return 64;; esac
  mkdir -p "$RUNS_DIR"
  local f; f="$(ledger_file "$rid")" || return 1
  local epoch; epoch="$(now_epoch)"
  if [ "$event" = "start" ]; then
    append_run_line "$rid" "$(printf '%s | OUTCOME | %s | start | at=%s' "$(now)" "$phase" "$epoch")"
    return 0
  fi
  # event=end: caught defaults to false (a clean pass is the safe default); duration is
  # derived from THIS rid+phase's last start bracket (0 if none, so an unbracketed end stays
  # honest rather than erroring).
  local caught=false policy="" kv k v
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    case "$k" in caught) caught="$v" ;; policy) policy="$v" ;; esac
  done
  case "$caught" in true|false) ;; *) echo "outcome: caught must be true|false (got '$caught')" >&2; return 64;; esac
  case "$policy" in ""|close|escalate|continue) ;; *) echo "outcome: policy must be close|escalate|continue (got '$policy')" >&2; return 64;; esac
  local start_epoch="" dur=0
  if [ -f "$f" ]; then
    start_epoch="$(awk -F' [|] ' -v p="$phase" '
      $2=="OUTCOME" && $3==p && $4=="start" {
        n=split($5,a," "); for(i=1;i<=n;i++){split(a[i],kv2,"="); if(kv2[1]=="at") v=kv2[2]}
      } END{print v}' "$f")"
    if [ -n "$start_epoch" ] && printf '%s' "$start_epoch" | grep -qE '^[0-9]+$'; then
      dur=$((epoch - start_epoch)); [ "$dur" -ge 0 ] || dur=0
    fi
  fi
  local line; line="$(printf '%s | OUTCOME | %s | end | at=%s caught=%s dur_s=%s' "$(now)" "$phase" "$epoch" "$caught" "$dur")"
  [ -n "$policy" ] && line="$line policy=$policy"
  append_run_line "$rid" "$line"
}

# outcome-read: read a gate's OUTCOME back (round-trip). For each completed
# start/end bracket (or the one given phase), print "<phase> caught=<bool> dur_s=<N>" from
# the LAST end line for that phase (last-end-wins, agreeing with the ledger's append-only
# semantics), plus a trailing " policy=<val>" only when that end line carried one --
# an old or policy-less line reads back byte-identical to before. A phase with a start but
# no end prints "<phase> incomplete". Read-only.
# Usage: outcome-read <rid> [phase]
outcome_read() {
  local rid="${1:-}" want="${2:-}"
  [ -n "$rid" ] || { echo "usage: outcome-read <rid> [phase]" >&2; return 64; }
  local f; f="$(ledger_file "$rid")" || return 1
  [ -f "$f" ] || { echo "(no ledger for '$rid')" >&2; return 1; }
  local filter=""
  [ -n "$want" ] && filter="$(normalize_phase "$want")"
  awk -F' [|] ' -v want="$filter" '
    $2=="OUTCOME" && $4=="start" { started[$3]=1; if(!($3 in ord)) ord[$3]=++seq }
    $2=="OUTCOME" && $4=="end" {
      n=split($5,a," "); c=""; d=""; p2=""
      for(i=1;i<=n;i++){split(a[i],kv,"="); if(kv[1]=="caught")c=kv[2]; if(kv[1]=="dur_s")d=kv[2]; if(kv[1]=="policy")p2=kv[2]}
      caught[$3]=c; dur[$3]=d; policy[$3]=p2; ended[$3]=1; if(!($3 in ord)) ord[$3]=++seq
    }
    END {
      for (p in ord) {
        if (want!="" && p!=want) continue
        if (p in ended) {
          line = sprintf("%s caught=%s dur_s=%s", p, caught[p], dur[p])
          if (policy[p] != "") line = line " policy=" policy[p]
          printf "%d\t%s\n", ord[p], line
        } else printf "%d\t%s incomplete\n", ord[p], p
      }
    }' "$f" | sort -n | cut -f2-
}

override() {
  local rid="${1:-}" raw="${2:-}"; shift 2 2>/dev/null || { echo "usage: override <rid> <phase> <reason>" >&2; return 64; }
  local reason; reason="$(oneline "$@")"; [ -n "$reason" ] || { echo "override requires a reason" >&2; return 64; }
  local phase; phase="$(normalize_phase "$raw")"
  local f; f="$(ledger_file "$rid")"
  # Blanket-override guard: a reason already used to override a DIFFERENT phase
  # in this run is one pasted across all gates, which defeats the per-gate audit trail --
  # reject it (exit 65). Re-applying the same reason to the SAME phase (idempotent re-run)
  # is fine. Split on ' | ' so fields line up with the write format below.
  if [ -f "$f" ] && awk -F' [|] ' -v p="$phase" -v r="$reason" '
        $2=="GATE" && $4=="override" && $3!=p {
          rr=$5; for (i=6; i<=NF; i++) rr=rr " | " $i   # reason may contain " | "
          if (rr==r) found=1
        }
        END { exit !found }' "$f"; then
    echo "override rejected: reason already used for another gate in run '$rid' -- each gate override needs its own reason" >&2
    return 65
  fi
  mkdir -p "$RUNS_DIR"
  append_run_line "$rid" "$(printf '%s | GATE | %s | override | %s' "$(now)" "$phase" "$reason")"
}

show() { local f; f="$(ledger_file "${1:-}")"; if [ -f "$f" ]; then cat "$f"; else echo "(no ledger for '${1:-}')" >&2; return 1; fi; }

# `check` verdict cache: $LOG_DIR/.gate-check.cache, the same key scheme as lane-telemetry's
# .shipped-incomplete.cache (ledger-key.sh), so a check on an unchanged ledger skips the lane
# derivation (about 40 process spawns).
#   line 1   #fp=<cksum of the lane data + gate scripts>   (a mismatch drops every entry)
#   then     lane<TAB>rid<TAB>kit-lanes<TAB>size<TAB>mtime<TAB>inode<TAB>ctime<TAB>pass|fail:<phase>,<phase>
# Any miss, unreadable or malformed entry runs the full check. An entry is written only for a ledger
# whose ctime is at least 2 s old (a user can set mtime, never ctime): a same-size rewrite inside the
# timestamp second would otherwise be invisible to the key. An unreadable ledger is never cached. The rewrite is temp + mv; a write failure is never fatal.
_CHECK_RES_RE='^(pass|fail:[a-z0-9-]+(,[a-z0-9-]+)*)$'
_check_cache_get() {  # <prefix> <fp>: prints the cached result, or nothing on a miss
  local prefix="$1" fp="$2" nl=$'\n' file="$LOG_DIR/.gate-check.cache" cache rest res
  [ -r "$file" ] || return 0
  cache="$(<"$file")" || return 0
  case "$cache" in "#fp=$fp$nl"*) ;; *) return 0 ;; esac
  cache="$nl$cache$nl"
  case "$cache" in *"$nl$prefix"*) ;; *) return 0 ;; esac
  rest="${cache#*"$nl$prefix"}"; res="${rest%%"$nl"*}"
  [[ "$res" =~ $_CHECK_RES_RE ]] && printf '%s' "$res"
  return 0
}

_check_cache_put() {  # <prefix> <fp> <ctime> <result>
  local prefix="$1" fp="$2" ctime="$3" result="$4" nl=$'\n' file="$LOG_DIR/.gate-check.cache" keep=""
  [ -d "$LOG_DIR" ] || return 0
  [ "$(( $(now_epoch) - ctime ))" -ge 2 ] 2>/dev/null || return 0
  if [ -r "$file" ] && [ "$(head -n 1 "$file" 2>/dev/null || true)" = "#fp=$fp" ]; then
    # keep the newest 400 other entries; a fresh result replaces any earlier one for its key
    keep="$(tail -n +2 "$file" 2>/dev/null | grep -vF -- "$prefix" | tail -n 400 || true)"
  fi
  _cc_tmp="$(mktemp "$file.XXXXXX" 2>/dev/null)" || { _cc_tmp=""; return 0; }
  trap 'command rm -f "$_cc_tmp"' EXIT
  trap 'command rm -f "$_cc_tmp"; exit 143' TERM
  trap 'command rm -f "$_cc_tmp"; exit 130' INT
  { printf '#fp=%s\n' "$fp"; [ -z "$keep" ] || printf '%s\n' "$keep"; printf '%s%s\n' "$prefix" "$result"; } > "$_cc_tmp" 2>/dev/null \
    && mv -f "$_cc_tmp" "$file" 2>/dev/null || command rm -f "$_cc_tmp" 2>/dev/null || true
  trap - EXIT TERM INT
  return 0
}

# exit 0 if every required (measure-twice) gate has a ran|override entry; else 1 + list gaps.
check() {
  local kl=""; if [ "${3:-}" = "--kit-lanes" ]; then kl=1; fi
  local lane="${1:-}" rid="${2:-}"; [ -n "$lane" ] && [ -n "$rid" ] || { echo "usage: check <lane> <rid> [--kit-lanes]" >&2; return 64; }
  # Cache lookup first. Only a known lane with a usable rid and a stat-able ledger is ever cached,
  # so an unknown lane, an empty rid name or a missing ledger always takes the full path below.
  local tab=$'\t' safe ck_id="" ck_fp="" ck_prefix="" ck_res="" ck_phases="" ck_phase="" ck_ctime="" ck_f=""
  case " $LANE_NAMES " in
    *" $lane "*)
      safe="$(runid "$rid")"
      if [ -n "$safe" ]; then
        ck_f="$(ledger_file "$rid")"
        [ -r "$ck_f" ] && ck_id="$(_file_id "$ck_f")"
        if [ -n "$ck_id" ]; then
          ck_fp="$(_lane_fp)"
          ck_prefix="$lane$tab$safe$tab${kl:-0}$tab$ck_id$tab"
          ck_res="$(_check_cache_get "$ck_prefix" "$ck_fp")"
        fi
      fi ;;
  esac
  case "$ck_res" in
    pass) return 0 ;;
    fail:*)
      ck_phases="${ck_res#fail:}"
      while [ -n "$ck_phases" ]; do
        ck_phase="${ck_phases%%,*}"
        echo "MISSING-GATE: $ck_phase (required for lane '$lane'; no ran/override entry in the ledger)" >&2
        case "$ck_phases" in *,*) ck_phases="${ck_phases#*,}" ;; *) ck_phases="" ;; esac
      done
      return 1 ;;
  esac
  # FAIL CLOSED on an unknown lane (security review, TIER-4): `required` returns nonzero for a
  # lane with no valid lane data (a typo, or "mega"). Reading its EMPTY stream in
  # the loop below would leave missing=0 and vacuously PASS -- so an unknown lane would let
  # mega-merge auto-merge (and ship-gate pass) with zero gates enforced. Distinguish it from a
  # VALID lane that legitimately has zero measure-twice gates (e.g. `tiny`): `required` exits 0
  # there with empty output, which correctly passes.
  local req
  if ! req="$(LANES_KIT_ONLY="$kl" required "$lane" 2>/dev/null)"; then
    echo "check: unknown lane '$lane' (no valid [lane.$lane] data in kit.toml: tiny|normal|full|bug|backfill); refusing, fail-closed" >&2
    return 1
  fi
  local f; f="$(ledger_file "$rid")"
  local missing=0 phase missing_phases=""
  while IFS= read -r phase; do
    [ -n "$phase" ] || continue
    if [ ! -f "$f" ] || ! awk -F' [|] ' -v p="$phase" '$2=="GATE" && $3==p && ($4=="ran"||$4=="override"){f=1} END{exit !f}' "$f"; then
      echo "MISSING-GATE: $phase (required for lane '$lane'; no ran/override entry in the ledger)" >&2
      missing=1; missing_phases="$missing_phases${missing_phases:+,}$phase"
    fi
  done <<< "$req"
  if [ -n "$ck_prefix" ]; then
    if [ "$missing" -eq 0 ]; then ck_res=pass; else ck_res="fail:$missing_phases"; fi
    ck_ctime="${ck_id##*"$tab"}"
    [[ "$ck_res" =~ $_CHECK_RES_RE ]] && _check_cache_put "$ck_prefix" "$ck_fp" "$ck_ctime" "$ck_res"
  fi
  return "$missing"
}

# plan: the lane's ordered phase checklist, derived from the lane data (absent phases
# omitted; required = required, light = lite). grill is prepended as the universal
# intake phase (tiny lane exempt). This is what /kit:assign prints right after a
# lane is committed, so the operator sees the road before the run starts.
plan() {
  local lane="${1:-}"; [ -n "$lane" ] || { echo "usage: plan <lane>" >&2; return 64; }
  # Overlay lanes: a vertical kit (learning-kit etc.) drops <lane>.plan into
  # ~/.config/dwarves-kit/lanes.d/ ("N. phase level" lines, same shape as this
  # verb's output). Drop-in wins over "unknown lane", never over a kit.toml lane.
  local rows known=1; rows="$(lane_cells "$lane")" || known=0
  if [ "$known" = 0 ]; then
    local dropin="${DWARVES_KIT_LANES_D:-$HOME/.config/dwarves-kit/lanes.d}/$lane.plan"
    if [ -f "$dropin" ]; then
      grep -E '^[[:space:]]*[0-9]+\.[[:space:]]' "$dropin"
      return 0
    fi
  fi
  [ "$known" = 1 ] || { echo "unknown lane '$lane' (no valid [lane.$lane] data in kit.toml; no lanes.d drop-in)" >&2; return 1; }
  local i=0 ph cell mark
  if [ "$lane" != "tiny" ]; then
    i=1; printf '%2d. %-18s %s\n' 1 "grill" "intake (universal)"
  fi
  while IFS=$'\t' read -r ph cell; do
    case "$cell" in
      measure-twice) mark="required" ;;
      run-lite)      mark="lite" ;;
      *) continue ;;
    esac
    i=$((i+1))
    printf '%2d. %-18s %s\n' "$i" "$(normalize_phase "$ph")" "$mark"
  done <<< "$rows"
}

# Replay the disposition set parsed by plan_record() through the SAME record()/override()
# functions an operator calls by hand. Runs twice per call: once against a scratch ledger root
# (the dry run), once for real. The set travels in globals because a second positional pass
# would have to re-parse it, and bash 3.2 has no associative arrays to pass it in one value.
_plan_record_apply() {
  local i=0
  while [ "$i" -lt "$_pr_n" ]; do
    case "${_pr_kind[$i]}" in
      override) override "$_pr_rid" "${_pr_phase[$i]}" "${_pr_reason[$i]}" || return $? ;;
      *)        record "$_pr_rid" "${_pr_phase[$i]}" "${_pr_kind[$i]}" "${_pr_reason[$i]}" || return $? ;;
    esac
    i=$((i+1))
  done
}

# plan-record: dispose EVERY phase of a lane's plan in one call. A run that
# followed its lane needed one record/override call per gate, nine hand-typed calls on a
# normal-lane prose PR, each one a chance to mistype a phase or forget one.
#
# The lane's phases come from plan(), so the lane table is read in exactly one place. Each line
# is written by record() or override(), so the ledger line format, the grill-skip reason enum,
# and the distinct-override-reason guard live in one place and keep applying here unchanged.
#
# Refuse-before-write: a rejected call must leave the ledger untouched, so the whole set is
# first replayed against a scratch ledger root seeded with a copy of this rid's real log. The
# copy matters because the override guard judges a duplicate reason against the run's history,
# and the dry run must see both that history and the overrides the same call is adding. Only a
# fully clean replay is then written for real.
#
# `ship` is the one plan phase a caller may omit, because the push records it. Every other
# phase must carry a disposition, the lite and intake ones included: naming them all is what
# leaves check() clean after a single call.
#
# The exit code answers "did the write happen", not "is the lane complete". check()'s verdict
# prints after the written lines instead, since a run that leaves ship to the push would
# otherwise exit non-zero on its happy path.
# Usage: plan-record <rid> <lane> [--ran <phase>[:<reason>]]... [--skipped <phase>:<reason>]... [--override <phase>:<reason>]...
plan_record() {
  local rid="${1:-}" lane="${2:-}"
  if [ -z "$rid" ] || [ -z "$lane" ]; then
    echo "usage: plan-record <rid> <lane> [--ran <phase>[:<reason>]] [--skipped <phase>:<reason>] [--override <phase>:<reason>]" >&2
    return 64
  fi
  shift 2
  local plan_out; plan_out="$(plan "$lane")" || return 1

  local plan_phases=" " pline ph
  while IFS= read -r pline; do
    ph="$(printf '%s' "$pline" | awk '{print $2}')"
    [ -n "$ph" ] && plan_phases="$plan_phases$ph "
  done <<< "$plan_out"

  _pr_rid="$rid"; _pr_n=0; _pr_kind=(); _pr_phase=(); _pr_reason=()
  local seen=" " kind arg raw reason
  while [ $# -gt 0 ]; do
    case "$1" in
      --ran|--skipped|--override) kind="${1#--}" ;;
      *) echo "plan-record: unexpected argument '$1' (expected --ran|--skipped|--override)" >&2; return 64 ;;
    esac
    arg="${2:-}"
    [ -n "$arg" ] || { echo "plan-record: $1 needs a <phase>[:<reason>] argument" >&2; return 64; }
    raw="${arg%%:*}"
    if [ "$arg" = "$raw" ]; then reason=""; else reason="${arg#*:}"; fi
    # "phase: reason" reads the same as "phase:reason": the grill enum and the override-reason
    # comparison both key on the first characters of the text, so a stray space changes meaning.
    reason="$(printf '%s' "$reason" | sed -E 's/^[[:space:]]+//')"
    ph="$(normalize_phase "$raw")"
    [ -n "$ph" ] || { echo "plan-record: $1 needs a phase name" >&2; return 64; }
    case "$plan_phases" in
      *" $ph "*) ;;
      *) echo "plan-record: '$ph' is not a phase of lane '$lane' (plan:$plan_phases)" >&2; return 64 ;;
    esac
    case "$seen" in
      *" $ph "*) echo "plan-record: phase '$ph' given twice" >&2; return 64 ;;
    esac
    if [ "$kind" != "ran" ] && [ -z "$reason" ]; then
      echo "plan-record: --$kind needs a reason ('$ph:<reason>')" >&2; return 64
    fi
    seen="$seen$ph "
    _pr_kind[$_pr_n]="$kind"; _pr_phase[$_pr_n]="$ph"; _pr_reason[$_pr_n]="$reason"
    _pr_n=$((_pr_n+1))
    shift 2
  done

  local missing=""
  # shellcheck disable=SC2086  # plan phase keys are single tokens; the split is the iteration
  for ph in $plan_phases; do
    [ "$ph" = "ship" ] && continue
    case "$seen" in *" $ph "*) ;; *) missing="$missing $ph" ;; esac
  done
  if [ -n "$missing" ]; then
    echo "plan-record: lane '$lane' phases with no disposition:$missing (name every phase; only 'ship' may be omitted)" >&2
    return 64
  fi
  [ "$_pr_n" -gt 0 ] || { echo "plan-record: no dispositions given" >&2; return 64; }

  local scratch; scratch="$(mktemp -d)" || { echo "plan-record: cannot create a scratch dir for the dry run" >&2; return 1; }
  # The scratch dir holds a copy of the real ledger; an interrupt must not strand it in
  # TMPDIR. The trap runs at script exit, after this function's locals are gone, so it
  # reads a script-scope name (a local here made every refusal exit 1 under set -u).
  _pr_scratch="$scratch"
  trap 'rm -rf "${_pr_scratch:-}"' EXIT
  local real stem rc=0
  real="$(ledger_file "$rid")" || return 1
  stem="$(basename "$real")"
  mkdir -p "$scratch/runs"
  # Two copies: the dry run appends to the one under runs/, the other stays pristine for the
  # drift check below.
  if [ -f "$real" ]; then cp "$real" "$scratch/runs/$stem"; cp "$real" "$scratch/orig"; fi
  # Both roots move together: ledger_append resolves KIT_LEDGER_DIR per call, while
  # override()'s duplicate-reason guard reads RUNS_DIR through ledger_file().
  # The subshell inherits the EXIT trap; it must not delete the scratch the parent still compares.
  ( trap - EXIT; RUNS_DIR="$scratch/runs"; KIT_LEDGER_DIR="$scratch"; _plan_record_apply ) || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "plan-record: refused; nothing was written to the ledger for '$rid'" >&2
    return "$rc"
  fi

  # The dry run validated against a snapshot. A writer that appended to the real
  # ledger since then (another session's override on the same rid) could make the real
  # pass fail mid-loop and leave a partial ledger, so refuse when the file moved.
  if [ -f "$real" ] && ! cmp -s "$real" "$scratch/orig"; then
    echo "plan-record: the ledger for '$rid' changed during the dry run; nothing was written, re-run" >&2
    return 75
  fi
  rm -rf "$scratch"; _pr_scratch=""; trap - EXIT

  _plan_record_apply || {
    echo "plan-record: the dry run passed but a write failed for '$rid'; inspect with: gate-ledger.sh show $rid" >&2
    return 1
  }

  local i=0
  while [ "$i" -lt "$_pr_n" ]; do
    printf '%-18s %s\n' "${_pr_phase[$i]}" "${_pr_kind[$i]}"
    i=$((i+1))
  done
  local gaps
  if gaps="$(check "$lane" "$rid" 2>&1)"; then
    printf 'check: clean for lane %s\n' "$lane"
  else
    printf '%s\n' "$gaps" >&2
    printf 'check: gaps remain for lane %s (listed above)\n' "$lane"
  fi
  return 0
}

# inherit: a task branch built under an approved multi-task spec carries that spec's
# spec-level gates instead of re-running them. The verb writes one `override` line per phase,
# its reason built from evidence: the parent rid's ledger must hold `ran` as the LAST GATE line
# for every inherited phase (the ship-gate's own last-state read of validate). It attests only
# that fact, on this host's ledger: not approval, not task membership. Lead-only, no command
# calls it. build, review, docs, ship and reflect are never inherited.
#
# Every match against an existing reason uses the exact token "inherited from <parent>: " via
# awk index(), never a regex built from a rid, so `watch-hub` never matches `watch-hub-spec`.
# A refusal writes nothing. A write that fails partway stops and returns override()'s code;
# re-running the same call skips the lines already written and finishes.
# Usage: inherit <rid> full --from <parent-rid>
INHERITABLE="think design design-critique spec validate design-record test-plan"
inherit() {
  if [ "$#" -ne 4 ] || [ "$3" != "--from" ]; then
    echo "usage: inherit <rid> full --from <parent-rid>" >&2; return 64
  fi
  local rid parent lane="$2"
  rid="$(runid "$1")"; parent="$(runid "$4")"
  if [ -z "$rid" ] || [ -z "$parent" ]; then
    echo "inherit: the rid or the parent normalizes to an empty id" >&2; return 64
  fi
  [ "$parent" != "$rid" ] || { echo "inherit: parent '$parent' is the child rid itself; name the spec's rid" >&2; return 64; }
  [ "$lane" = full ] || { echo "inherit: v1 inherits spec-level gates for the full lane only (got '$lane')" >&2; return 64; }

  # Kit-root lane data, the same read as the ship-gate's hard-path floor (check --kit-lanes),
  # so a project overlay cannot shrink the set below what the floor demands. Fail closed.
  local req set="" ph
  req="$(LANES_KIT_ONLY=1 required full 2>/dev/null)" || { echo "inherit: the kit-root lane data for 'full' is unreadable; refusing, fail-closed" >&2; return 1; }
  for ph in $INHERITABLE; do
    if printf '%s\n' "$req" | grep -qxF -- "$ph"; then set="$set $ph"; fi
  done
  [ -n "$set" ] || { echo "inherit: the kit-root lane 'full' requires none of: $INHERITABLE; refusing, fail-closed" >&2; return 1; }

  local pf cf
  pf="$(ledger_file "$parent")"; cf="$(ledger_file "$rid")"
  [ -f "$pf" ] || { echo "inherit: no ledger for parent '$parent' under $RUNS_DIR (run ledgers are host-local; run this on the host that recorded the spec)" >&2; return 1; }
  local TOK="inherited from $parent: "

  # Judge: one row per phase, "<phase> <last state> <its ts> <its reason>", split on \037 (a
  # tab is IFS whitespace, so an empty field would collapse and shift the next one into place).
  local judge
  judge="$(awk -F' [|] ' -v set="$set" '
    BEGIN { n=split(set, S, " "); for (i=1; i<=n; i++) want[S[i]]=1 }
    $2=="GATE" && ($3 in want) { st[$3]=$4; ts[$3]=$1; r=$5; for (i=6; i<=NF; i++) r=r " | " $i; rs[$3]=r }
    END { for (i=1; i<=n; i++) { p=S[i]; printf "%s\037%s\037%s\037%s\n", p, ((p in st) ? st[p] : "none"), ts[p], rs[p] } }' "$pf")"
  local fails="" st ts r g nl=$'\n'
  while IFS=$'\037' read -r ph st ts r; do
    case "$st" in
      ran) printf '%s' "$ts" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' \
             || fails="$fails$nl  $ph: last state ran, but its timestamp is malformed" ;;
      none) fails="$fails$nl  $ph: no GATE line in the parent" ;;
      override)
        case "$r" in
          "inherited from "*) g="${r#inherited from }"; g="$(runid "${g%%: *}")"
                              fails="$fails$nl  $ph: the parent inherited it from '$g'; inherit from '$g' directly" ;;
          *) fails="$fails$nl  $ph: last state override, not ran" ;;
        esac ;;
      *) fails="$fails$nl  $ph: last state $(runid "${st:-empty}"), not ran" ;;
    esac
  done <<< "$judge"
  if [ -n "$fails" ]; then
    echo "inherit: parent '$parent' does not hold last state ran for every spec-level gate; nothing written:$fails" >&2
    return 1
  fi

  # Conflict: an inherited line for one of these phases from a DIFFERENT parent (a reused slug).
  local conflict=""
  if [ -f "$cf" ]; then
    conflict="$(awk -F' [|] ' -v set="$set" -v tok="$TOK" '
      BEGIN { n=split(set, S, " "); for (i=1; i<=n; i++) want[S[i]]=1 }
      $2=="GATE" && ($3 in want) && $4=="override" {
        r=$5; for (i=6; i<=NF; i++) r=r " | " $i
        if (index(r, "inherited from ")==1 && index(r, tok)!=1) { print $3; exit }
      }' "$cf")"
  fi
  if [ -n "$conflict" ]; then
    echo "inherit: child '$rid' already inherited $conflict from another parent (a reused slug?); refusing to mix parents, nothing written" >&2
    return 65
  fi

  local rc
  while IFS=$'\037' read -r ph st ts r; do
    if [ -f "$cf" ] && awk -F' [|] ' -v p="$ph" -v tok="$TOK" '
         $2=="GATE" && $3==p && $4=="override" { r=$5; for (i=6; i<=NF; i++) r=r " | " $i; if (index(r, tok)==1) f=1 }
         END { exit !f }' "$cf"; then
      printf '%s already inherited from %s\n' "$ph" "$parent"; continue
    fi
    override "$rid" "$ph" "${TOK}$ph ran there at $ts" || { rc=$?; echo "inherit: override() refused the $ph write (exit $rc); earlier lines stay, re-run the same call to finish" >&2; return "$rc"; }
    printf '%s inherited from %s\n' "$ph" "$parent"
  done <<< "$judge"
  return 0
}

# progress: plan x ledger -> one status line + checklist. A phase counts done when the
# ledger carries ANY entry for it (ran, skipped-with-reason, override); the current step
# is the first phase without one. Commands print this at phase entry.
progress() {
  local rid="${1:-}" lane="${2:-}"
  [ -n "$rid" ] && [ -n "$lane" ] || { echo "usage: progress <rid> <lane>" >&2; return 64; }
  local f; f="$(ledger_file "$rid")"
  local total=0 done_n=0 cur="" cur_idx=0 list="" ooo=0
  local idx ph rest
  while IFS= read -r pline; do
    idx="${pline%%.*}"; idx="$(printf '%s' "$idx" | tr -d ' ')"
    ph="$(printf '%s' "$pline" | awk '{print $2}')"
    total=$((total+1))
    # disposed = ran / override / skipped WITH a reason; a bare skip stays visible as a gap
    if [ -f "$f" ] && awk -F' [|] ' -v p="$ph" '$2=="GATE" && $3==p && ($4!="skipped" || (NF>=5 && $5!="")) {found=1} END{exit !found}' "$f"; then
      # a phase disposed AFTER the current pointer gets its own
      # marker (*), so an out-of-order ✓ can't mislead the at-a-glance read.
      if [ -n "$cur" ]; then
        done_n=$((done_n+1)); ooo=1; list="$list ${C_DONE}*$ph${C_OFF}"
      else
        done_n=$((done_n+1)); list="$list ${C_DONE}✓$ph${C_OFF}"
      fi
    elif [ -z "$cur" ]; then
      cur="$ph"; cur_idx="$idx"; list="$list ${C_CUR}▶$ph${C_OFF}"
    else
      list="$list ${C_DIM}·$ph${C_OFF}"
    fi
  done < <(plan "$lane")
  [ "$total" -gt 0 ] || return 1
  if [ -z "$cur" ]; then
    printf '%s%s · %s · complete (%d/%d)%s\n' "$C_DONE" "$rid" "$lane" "$done_n" "$total" "$C_OFF"
  else
    printf '%s%s · %s · step %s/%d (%s)%s\n' "$C_BOLD" "$rid" "$lane" "$cur_idx" "$total" "$cur" "$C_OFF"
  fi
  printf ' %s\n' "$list"
  [ "$ooo" -eq 1 ] && printf '%s  (* = disposed out of order)%s\n' "$C_DIM" "$C_OFF"
  return 0
}

# Descent check: the lane's plan order IS the V-model descent
# order. Replay the ledger timeline; a phase recorded while an EARLIER plan phase is
# still undisposed at that moment is a descent violation. Detection only: exit 0
# always (mid-flight never blocks); ship-gate surfaces the count as an
# advisory. Disposal semantics agree with progress(): ran / override / skipped WITH
# a non-empty reason dispose; a bare skip does not.
descent() {
  local rid="${1:-}" lane="${2:-}"
  [ -n "$rid" ] && [ -n "$lane" ] || { echo "usage: descent <rid> <lane>" >&2; return 64; }
  local f; f="$(ledger_file "$rid")" || return 0
  [ -f "$f" ] || { echo "descent clean (no ledger)"; return 0; }
  # phase + depth pairs: run-lite/intake phases are implicit checkpoints (review
  # HIGH: an unrecorded run-lite phase must not produce false violations); only
  # measure-twice (printed as "required") phases gate the descent when unrecorded.
  local plan_list; plan_list="$(plan "$lane" | awk '{print $2"="$3}' | tr '\n' ' ')" || return 0
  [ -n "$plan_list" ] || { echo "descent clean (no plan)"; return 0; }
  local out
  out="$(awk -F' [|] ' -v plan="$plan_list" '
    BEGIN {
      n=split(plan, R, " ")
      for (i=1;i<=n;i++) if (R[i]!="") {
        split(R[i], kv, "="); P[i]=kv[1]; order[kv[1]]=i
        if (kv[2]=="lite") disposed[kv[1]]=1   # run-lite only; grill (intake) + required phases stay real checkpoints
      }
    }
    $2=="GATE" {
      p=$3; if (!(p in order)) next
      for (j=1; j<order[p]; j++) if (P[j]!="" && !(P[j] in disposed) && !((p SUBSEP P[j]) in seen)) {
        printf "DESCENT: %s recorded before %s disposed\n", p, P[j]
        seen[p SUBSEP P[j]]=1   # dedup: one line per (phase, gap) pair
      }
      if ($4!="skipped" || (NF>=5 && $5!="")) disposed[p]=1
    }' "$f")"
  if [ -n "$out" ]; then printf '%s\n' "$out"; else echo "descent clean"; fi
  return 0
}

# The canonical run id: the current branch with its leading
# `type/` segment stripped, the EXACT transform ship-gate keys its ledger check by
# (`${branch#*/}` here == `${BRANCH#*/}` in hooks/ship-gate.sh; agreement-pinned in tests/test-meta.sh).
# One rid from assign to ship means no mirror records. Fails loudly off a work
# branch: a wrong rid recorded silently is worse than no rid.
rid() {
  local branch slug
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  case "$branch" in
    ""|HEAD|master|main)
      echo "rid: not on a work branch (got '${branch:-none}'); create the branch first, then derive the rid" >&2
      return 1 ;;
  esac
  slug="${branch#*/}"
  if [ -z "$slug" ] || [ -z "$(runid "$slug")" ]; then
    echo "rid: branch '$branch' strips to an empty slug" >&2
    return 1
  fi
  # Emit the runid-normalized form (review S2): the visible key equals the
  # ledger filename stem, so forensic review never chases two spellings.
  printf '%s\n' "$(runid "$slug")"
}

# mutation: record the ADVISORY mutation-smoke's verdict (kit-run-integrity) as
# an ADDITIVE marker -- the exact `| TOKENS |`/`| DEBT |` shape reused for a third concern: a
# `| MUTATION |` line that check()/override()/descent()/_rows() all ignore (they key on
# $2=="GATE"|START|ACTION), so a mutation verdict can never fake, satisfy, or mask a gate. This is
# the additive property the kit relies on; no reader changes. The smoke is warn-only (gate-zero),
# so this marker is a record of what it FOUND, never a gate the ship path enforces. Independent of
# the `caught=` GATE-line marker -- a different surface (this is a whole new marker verb).
# Usage: mutation <rid> verdict=<flag|clean|skip> [file=... line=... op=... attempts=N reason=...]
mutation() {
  local rid="${1:-}"; shift 2>/dev/null || { echo "usage: mutation <rid> verdict=<flag|clean|skip> [k=v ...]" >&2; return 64; }
  [ -n "$rid" ] || { echo "mutation requires a rid" >&2; return 64; }
  local verdict="" rest="" kv k v
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    # every value is single-token (space-split read-side); collapse spaces + neuter embedded "="
    # in free text so a value can never smuggle a second KV or split the ledger line. The "="->":"
    # step matches debt()'s pre-existing neutering and makes this line's comment true.
    v="$(printf '%s' "$v" | tr '\n\r' '  ' | tr ' ' '_' | tr '=' ':')"
    case "$k" in
      verdict) verdict="$v" ;;
      *)       rest="$rest $k=$v" ;;
    esac
  done
  case "$verdict" in flag|clean|skip) ;; *) echo "mutation: verdict must be flag|clean|skip (got '$verdict')" >&2; return 64;; esac
  mkdir -p "$RUNS_DIR"
  append_run_line "$rid" "$(printf '%s | MUTATION | verdict=%s%s' "$(now)" "$verdict" "$rest")"
}

# config_stamp: record a run's configuration dimensions as an ADDITIVE marker
# (bench-plane prerequisite: DECISION-BRIEF-bench-plane.md §1), the exact
# `| TOKENS |`/`| DEBT |`/`| MUTATION |` shape reused for a fourth concern: a
# `| CONFIG |` line that check()/override()/descent()/_rows() all ignore (same
# key-on-$2 convention), so a config line can never fake or mask a gate. Every
# value passes through oneline() (embedded newlines/pipes collapsed) before it
# is written, matching every other free-text field in this file.
#
# `phase=` (optional, same idiom as tokens()'s phase=) scopes one CONFIG line to
# a single stage, so a caller emits one line per stage for "model-per-stage"
# instead of one flat rid-wide line; omitting it stamps the whole run.
# kit_version defaults to $KIT_ROOT/VERSION when omitted (the running kit's own
# version, not a value the caller should normally need to pass). suite_hash
# stays empty for real work by contract (only a bench replay sets it, per the
# brief's "null for real work" line) -- this function never invents one.
# Usage: config <rid> [model=M] [effort=E] [kit_version=V] [modules=M1,M2,...]
#               [lane=L] [task_type=T] [suite_hash=H] [session_id=S] [phase=P]
config_stamp() {
  local rid="${1:-}"; shift 2>/dev/null || {
    echo "usage: config <rid> [model=M] [effort=E] [kit_version=V] [modules=M1,M2,...] [lane=L] [task_type=T] [suite_hash=H] [session_id=S] [phase=P]" >&2
    return 64
  }
  [ -n "$rid" ] || { echo "config requires a rid" >&2; return 64; }
  local model="" effort="" kver="" modules="" lane="" ttype="" shash="" sid="" phase="" kv k v
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    case "$k" in
      model)       model="$(oneline "$v")" ;;
      effort)      effort="$(oneline "$v")" ;;
      kit_version) kver="$(oneline "$v")" ;;
      modules)     modules="$(oneline "$v")" ;;
      lane)        lane="$(oneline "$v")" ;;
      task_type)   ttype="$(oneline "$v")" ;;
      suite_hash)  shash="$(oneline "$v")" ;;
      session_id)  sid="$(oneline "$v")" ;;
      phase)       phase="$(normalize_phase "$v")" ;;
    esac
  done
  if [ -z "$kver" ]; then
    kver="$(cat "$KIT_ROOT/VERSION" 2>/dev/null)" || kver=""
    [ -n "$kver" ] || kver="unknown"
  fi
  [ -n "$sid" ] || sid="${CLAUDE_SESSION_ID:-}"
  mkdir -p "$RUNS_DIR"
  local line; line="kit_version=$kver"
  [ -n "$model" ]   && line="$line model=$model"
  [ -n "$effort" ]  && line="$line effort=$effort"
  [ -n "$modules" ] && line="$line modules=$modules"
  [ -n "$lane" ]    && line="$line lane=$lane"
  [ -n "$ttype" ]   && line="$line task_type=$ttype"
  [ -n "$shash" ]   && line="$line suite_hash=$shash"
  [ -n "$sid" ]     && line="$line session_id=$sid"
  [ -n "$phase" ]   && line="$line phase=$phase"
  append_run_line "$rid" "$(printf '%s | CONFIG | %s' "$(now)" "$line")"
}

# Usage: history [--lane L] [--json] : one row per run over all gate ledgers.
# Ported from learning-kit/bin/study-history: aggregates every
# runs/<rid>.log START line's lane + repo with its GATE ran/skipped counts.
history() {
  local lane_opt="" fmt=csv arg
  while [ $# -gt 0 ]; do case "$1" in
    --json) fmt=json ;;
    --lane) lane_opt="${2:-}"; shift ;;
    *) echo "usage: history [--lane L] [--json]" >&2; return 64 ;;
  esac; shift; done
  [ -d "$RUNS_DIR" ] || return 0
  local rows="" f rid runlane repo t0 t1 ran skipped
  for f in "$RUNS_DIR"/*.log; do
    [ -f "$f" ] || continue
    grep -q '| START |' "$f" || continue
    runlane="$(grep -m1 '| START |' "$f" | grep -o 'lane=[^ ]*' | head -1 | cut -d= -f2)"
    if [ -n "$lane_opt" ] && [ "${runlane:-}" != "$lane_opt" ]; then continue; fi
    rid="$(basename "$f" .log)"
    repo="$(grep -m1 '| START |' "$f" | grep -o 'repo=[^ ]*' | head -1 | cut -d= -f2)"
    t0="$(head -1 "$f" | cut -d' ' -f1)"
    t1="$(tail -1 "$f" | cut -d' ' -f1)"
    ran="$(grep -c '| GATE | .* | ran |' "$f" 2>/dev/null || true)"
    skipped="$(grep -c '| GATE | .* | skipped |' "$f" 2>/dev/null || true)"
    rows="${rows}${rid},${runlane},${repo},${t0},${t1},${ran},${skipped}\n"
  done
  if [ "$fmt" = csv ]; then
    printf 'rid,lane,repo,first_ts,last_ts,gates_ran,gates_skipped\n'
    printf '%b' "$rows"
  else
    printf '%b' "$rows" | awk -F, 'BEGIN{print "["} NR>1{print ","} NR>=1{printf "{\"rid\":\"%s\",\"lane\":\"%s\",\"repo\":\"%s\",\"first_ts\":\"%s\",\"last_ts\":\"%s\",\"gates_ran\":%s,\"gates_skipped\":%s}",$1,$2,$3,$4,$5,$6,$7} END{print "\n]"}'
  fi
}

# _cutoff_iso <days> -- "now minus <days> days" as an ISO8601 Z timestamp. Portable: BSD `date`
# (macOS) needs `-v-Nd`; GNU `date` (Linux/CI) needs `-d "-N days"`. ISO8601 Z timestamps sort
# correctly as PLAIN STRINGS, so filtering below is a string compare, never a date parse.
# Same idiom as lib/reflect/weekend-batch.sh's helper of the same name (kept local, not shared,
# since it is six lines and the two callers have no other coupling).
_cutoff_iso() {
  local days="$1"
  if date -v-1d >/dev/null 2>&1; then
    date -u -v-"${days}"d +%Y-%m-%dT%H:%M:%SZ
  else
    date -u -d "-${days} days" +%Y-%m-%dT%H:%M:%SZ
  fi
}

# Usage: report --period week|month [--lane L] : cross-cutting markdown table of runs whose
# first ledger line falls in the window, with GATE ran/skipped totals. The
# smallest useful version over gate-ledger's own runs/ corpus (mega.sh cmd_report is a
# different, per-mega-goal report and does not satisfy this).
report() {
  local period="" lane_opt=""
  while [ $# -gt 0 ]; do case "$1" in
    --period) period="${2:-}"; shift ;;
    --lane) lane_opt="${2:-}"; shift ;;
    *) echo "usage: report --period week|month [--lane L]" >&2; return 64 ;;
  esac; shift; done
  local days
  case "$period" in
    week)  days=7 ;;
    month) days=30 ;;
    *) echo "usage: report --period week|month [--lane L]" >&2; return 64 ;;
  esac
  local since; since="$(_cutoff_iso "$days")"
  printf '# Gate-ledger report (%s, since %s)\n\n' "$period" "$since"
  [ -d "$RUNS_DIR" ] || { printf 'No runs recorded.\n'; return 0; }
  local f rid runlane repo t0 ran skipped rows="" total_runs=0 total_ran=0 total_skipped=0
  for f in "$RUNS_DIR"/*.log; do
    [ -f "$f" ] || continue
    grep -q '| START |' "$f" || continue
    t0="$(head -1 "$f" | cut -d' ' -f1)"
    [ -n "$t0" ] && { [ "$t0" '>' "$since" ] || [ "$t0" = "$since" ]; } || continue
    runlane="$(grep -m1 '| START |' "$f" | grep -o 'lane=[^ ]*' | head -1 | cut -d= -f2)"
    if [ -n "$lane_opt" ] && [ "${runlane:-}" != "$lane_opt" ]; then continue; fi
    rid="$(basename "$f" .log)"
    repo="$(grep -m1 '| START |' "$f" | grep -o 'repo=[^ ]*' | head -1 | cut -d= -f2)"
    ran="$(grep -c '| GATE | .* | ran |' "$f" 2>/dev/null || true)"
    skipped="$(grep -c '| GATE | .* | skipped |' "$f" 2>/dev/null || true)"
    rows="${rows}| ${rid} | ${runlane} | ${repo} | ${ran} | ${skipped} |\n"
    total_runs=$((total_runs + 1)); total_ran=$((total_ran + ran)); total_skipped=$((total_skipped + skipped))
  done
  if [ "$total_runs" -eq 0 ]; then
    printf 'No runs in this window.\n'
    return 0
  fi
  printf '| rid | lane | repo | gates_ran | gates_skipped |\n|---|---|---|---|---|\n'
  printf '%b' "$rows"
  printf '\n**Totals:** %d runs, %d gates ran, %d gates skipped\n' "$total_runs" "$total_ran" "$total_skipped"
}


# ---- validate-round -----------------------------------------------------------
# The parallel validation round's ledger bookkeeping as a single verb. `open` binds
# the rid to the spec the ship-gate will read, pins the spec blob plus a repo
# snapshot, and opens both OUTCOME brackets; `close` writes the round's GATE/OUTCOME
# records in a fixed order; `incomplete` records a stopped round. Round state lives
# in the rid ledger as additive `| ROUND |` lines; marker-keyed readers skip them.
# Exits: 0 ok; 1 state/binding/git failure; 2 void on drift; 3 void with the
# restart budget spent; 64 bad input.

# Token: <spec blob sha>.<epoch>.<n>; the blob is sha1 (40) or sha256 (64) long.
_VR_TOK_RE='^([0-9a-f]{40}|[0-9a-f]{64})\.[0-9]+\.[0-9]+$'

# The rid's last `| ROUND |` line ($2=="ROUND" on ` | `-split fields), or nothing.
_vr_last_round() {
  local f; f="$(ledger_file "$1")"
  [ -f "$f" ] || return 0
  awk -F' [|] ' '$2=="ROUND"{l=$0} END{print l}' "$f"
}

# Field N of a ledger line on ` | ` boundaries.
_vr_field() { printf '%s' "$1" | awk -F' [|] ' -v n="$2" 'NR==1{print $n}'; }

# k=v lookup inside a ROUND line's field 4 (space-separated k=v; values never carry
# a space or `=` by construction).
_vr_kv() {
  printf '%s' "$1" \
    | awk -v k="$2" '{n=split($0,w," "); for(i=1;i<=n;i++){split(w[i],kv,"="); if(kv[1]==k) v=kv[2]}} END{print v}'
}

# Write $6.. as a ledger record unless a line with the same fields 2-4 already sits
# after line $2 (a partially written round is resumed, never duplicated).
_vr_w() {
  local f="$1" clnr="$2" m="$3" p="$4" s="$5"; shift 5
  if awk -F' [|] ' -v a="$clnr" -v m="$m" -v p="$p" -v s="$s" \
      'NR>a && $2==m && $3==p && $4==s {f=1} END{exit !f}' "$f"; then
    return 0
  fi
  "$@"
}

# Refuse (64) a value holding a newline, CR or `|`: it would split or fake the
# ` | `-split ledger fields. $1 names the field for the message.
_vr_refuse_ctl() {
  case "$2" in
    *$'\n'*|*$'\r'*|*'|'*) echo "validate-round: $1 may not hold newline, CR or '|'" >&2; exit 64 ;;
  esac
}

# The repo snapshot pin: porcelain of the tracked+untracked tree minus the
# hook/cache writers (Grounding item 4), hashed as one blob. Callers assign it
# unconditionally (`x="$(_vr_porcelain ...)"`) so a git failure hits the ERR trap.
_vr_porcelain() {
  git -C "$1" status --porcelain --untracked-files=all -- . ':(exclude)_meta' ':(exclude).claude' ':(exclude,glob)**/.pytest_cache/**' ':(exclude,glob)**/.ruff_cache/**' ':(exclude,glob)**/.mypy_cache/**' ':(exclude,glob)**/.hypothesis/**' | git -C "$1" hash-object --stdin
}

# Load the rid's ledger state into the _vrL_* globals: the ledger file, the last
# ROUND line, its state field, its field 4 and the token= key in field 4. One
# prelude for every sub-verb.
_vr_load() {
  _vrL_f="$(ledger_file "$1")"
  _vrL_last="$(_vr_last_round "$1")"
  _vrL_state="$(_vr_field "$_vrL_last" 3)"
  _vrL_f4="$(_vr_field "$_vrL_last" 4)"
  _vrL_token="$(_vr_kv "$_vrL_f4" token)"
}

# Normalize a ledger line for plan comparison: drop the field-1 timestamp and
# mask the volatile at=/dur_s= fields, so only the semantic content compares.
_vr_norm() {
  printf '%s' "$1" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z \| //; s/at=[0-9]+/at=E/g; s/dur_s=[0-9]+/dur_s=D/g'
}

# Print one foreign ledger line to stderr with a `  foreign: ` prefix, control
# bytes stripped: the line is untrusted data shown to the lead, never a command.
_vr_print_foreign() {
  local clean
  clean="$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\010\013-\037\177')"
  printf '  foreign: %s\n' "$clean" >&2
}

# Resume guard (review MEDIUM): the lines after the round's `ROUND closing` line
# must be a strict PREFIX of the round's planned records (normalized on the full
# line minus timestamp, not only fields 2-4). Anything else is forged or foreign
# -- every offending line is listed on stderr and the resume refuses (exit 1) so
# a planted `GATE ... ran "FORGED"` is never adopted as the round's own record.
# $1=ledger file $2=closing line number; $@ = planned lines, normalized, in order.
_vr_check_resume() {
  local f="$1" clnr="$2"; shift 2
  local -a planned=()
  local p
  for p in "$@"; do planned+=("$(_vr_norm "$p")"); done
  local i=0 line bad=0
  while IFS= read -r line; do
    i=$((i + 1))
    if [ "$i" -le "${#planned[@]}" ] && [ "$(_vr_norm "$line")" = "${planned[$((i - 1))]}" ]; then
      continue
    fi
    if [ "$bad" = 0 ]; then
      printf 'validate-round: lines after the ROUND closing that are not this round'"'"'s planned records:\n' >&2
    fi
    bad=1
    _vr_print_foreign "$line"
  done < <(tail -n +"$((clnr + 1))" "$f")
  [ "$bad" = 0 ]
}

# validate-round open <rid> <spec>: bind rid to the spec the ship-gate will read,
# pin the blob + repo snapshot, open both OUTCOME brackets. Prints the round token.
_vr_open() {
  local rid="${1:-}" spec="${2:-}"
  [ -n "$rid" ] && [ -n "$spec" ] || { echo "usage: validate-round open <rid> <spec>" >&2; exit 64; }
  # spec path refusals (all 64) run before any git call and before canonicalization.
  case "$spec" in
    *[[:space:]]*|*"="*) echo "validate-round: spec path may not hold whitespace or '='" >&2; exit 64 ;;
  esac
  local sdir="${spec%/*}" sbase="${spec##*/}"
  [ "$sdir" = "$spec" ] && sdir="."
  [ -d "$sdir" ]   || { echo "validate-round: spec directory '$sdir' does not exist" >&2; exit 64; }
  [ -f "$spec" ]   || { echo "validate-round: spec '$spec' is not a regular file" >&2; exit 64; }
  [ ! -L "$spec" ] || { echo "validate-round: spec '$spec' is a symlink" >&2; exit 64; }
  [ -r "$spec" ]   || { echo "validate-round: spec '$spec' is not readable" >&2; exit 64; }
  # Canonical path via pwd -P, the only place caller-relative resolution happens.
  # CDPATH= keeps a set CDPATH from echoing the resolved dir into the value; `--`
  # keeps a dash-leading directory out of option parsing.
  local spec_dir spec_abs
  spec_dir="$(CDPATH= cd -- "$sdir" && pwd -P)"
  spec_abs="$spec_dir/$sbase"
  # Re-check the charset: a spaced/`=` ancestor can enter through canonicalization.
  case "$spec_abs" in
    *[[:space:]]*|*"="*) echo "validate-round: canonical spec path '$spec_abs' holds whitespace or '='" >&2; exit 64 ;;
  esac
  # And re-run the regular-file/not-a-symlink checks on the canonical path, the
  # path the pin and every later hash actually use.
  { [ -f "$spec_abs" ] && [ ! -L "$spec_abs" ]; } \
    || { echo "validate-round: canonical spec '$spec_abs' is not a regular file or is a symlink" >&2; exit 64; }
  _vr_load "$rid"
  case "$_vrL_state" in
    open|closing) echo "validate-round: a round is already $_vrL_state for '$rid'" >&2; exit 1 ;;
  esac
  local top branch slug nrid
  top="$(git -C "$spec_dir" rev-parse --show-toplevel)"
  branch="$(git -C "$top" rev-parse --abbrev-ref HEAD)"
  # Same refusal as rid() (`""|HEAD|master|main`), on `git -C <toplevel>`: rid() runs a
  # bare `git` from the cwd, which would read the caller's repo.
  case "$branch" in
    ""|HEAD|master|main) echo "validate-round: '$top' is not on a work branch (got '${branch:-none}')" >&2; exit 1 ;;
  esac
  slug="${branch#*/}"
  nrid="$(runid "$slug")"
  [ "$slug" = "$nrid" ] || { echo "validate-round: branch slug '$slug' normalizes to '$nrid'; cannot bind a rid" >&2; exit 1; }
  [ "$nrid" = "$rid" ]  || { echo "validate-round: rid '$rid' is not the branch's slug-derived rid '$nrid'" >&2; exit 1; }
  # The accepted spec is the file the ship-gate itself will read: spec_for_slug from
  # lib/spec/spec-find.sh, the one pick both share (root docs/specs first, then a co-located
  # <ns>/docs/specs/SPEC-<digits>-<slug>.md, shallow first).
  local match
  match="$(spec_for_slug "$top" "$slug")"
  [ -n "$match" ]            || { echo "validate-round: no SPEC-*-$slug.md under '$top' (docs/specs or a co-located */docs/specs)" >&2; exit 1; }
  [ "$match" = "$spec_abs" ] || { echo "validate-round: spec '$spec_abs' is not the ship-gate pick '$match'" >&2; exit 1; }
  local blob head_sha por n ep token
  blob="$(git -C "$top" hash-object -w "$spec_abs")"
  head_sha="$(git -C "$top" rev-parse HEAD)"
  por="$(_vr_porcelain "$top")"
  n=1
  if [ -f "$_vrL_f" ]; then n="$(awk -F' [|] ' '$2=="ROUND" && $3=="open"{c++} END{print c+1}' "$_vrL_f")"; fi
  ep="$(now_epoch)"
  token="$blob.$ep.$n"
  outcome "$rid" Validate start
  outcome "$rid" design-record start
  append_run_line "$rid" "$(printf '%s | ROUND | open | token=%s top=%s spec=%s blob=%s head=%s porcelain=%s' "$(now)" "$token" "$top" "$spec_abs" "$blob" "$head_sha" "$por")"
  printf '%s\n' "$token"
}

# The GATE/OUTCOME records a close writes, in order, skipping any already present
# after this round's closing line, then the terminal `ROUND close` line.
_vr_close_records() {
  local rid="$1" token="$2" verdict="$3" critical="$4" warnings="$5" agents="$6" r6="$7" summary="$8" clnr="$9"
  local f; f="$(ledger_file "$rid")"
  local r6rest="${r6#* }" r6crit=0
  case "$r6rest" in "critical: "*) r6crit=1 ;; esac
  # The planned records, normalized for the resume prefix check: the lines after
  # `closing` must be exactly these, in order, or the resume refuses (a forged
  # line sharing fields 2-4 must not be adopted as the round's own record).
  local -a planned
  local caught_v="" caught_dr=""
  if [ "$verdict" = "APPROVED" ]; then
    # DEC-N: each gate's end carries the validation-wide caught rollup.
    caught_v="$(_vr_caught "$f" "$clnr" validate)"
    caught_dr="$(_vr_caught "$f" "$clnr" design-record)"
    planned=(
      "GATE | validate | ran | APPROVED critical=$critical warnings=$warnings fresh agents=$agents parallel"
      "OUTCOME | validate | end | at=E caught=$caught_v dur_s=D"
      "GATE | design-record | ran | $r6"
      "OUTCOME | design-record | end | at=E caught=$caught_dr dur_s=D"
    )
  elif [ "$r6crit" = 1 ]; then
    planned=(
      "GATE | validate | skipped | NEEDS REVISION: $summary"
      "OUTCOME | validate | end | at=E caught=true dur_s=D"
      "GATE | design-record | skipped | $r6rest"
      "OUTCOME | design-record | end | at=E caught=true dur_s=D"
    )
  else
    planned=(
      "GATE | validate | skipped | NEEDS REVISION: $summary"
      "OUTCOME | validate | end | at=E caught=true dur_s=D"
      "GATE | design-record | ran | $r6"
      "OUTCOME | design-record | end | at=E caught=false dur_s=D"
    )
  fi
  _vr_check_resume "$f" "$clnr" "${planned[@]}" || exit 1
  if [ "$verdict" = "APPROVED" ]; then
    _vr_w "$f" "$clnr" GATE validate ran          record "$rid" Validate ran "APPROVED critical=$critical warnings=$warnings fresh agents=$agents parallel"
    _vr_w "$f" "$clnr" OUTCOME validate end       outcome "$rid" Validate end caught="$caught_v"
    _vr_w "$f" "$clnr" GATE design-record ran     record "$rid" design-record ran "$r6"
    _vr_w "$f" "$clnr" OUTCOME design-record end  outcome "$rid" design-record end caught="$caught_dr"
  else
    _vr_w "$f" "$clnr" GATE validate skipped      record "$rid" Validate skipped "NEEDS REVISION: $summary"
    _vr_w "$f" "$clnr" OUTCOME validate end       outcome "$rid" Validate end caught=true
    if [ "$r6crit" = 1 ]; then
      _vr_w "$f" "$clnr" GATE design-record skipped  record "$rid" design-record skipped "$r6rest"
      _vr_w "$f" "$clnr" OUTCOME design-record end   outcome "$rid" design-record end caught=true
    else
      _vr_w "$f" "$clnr" GATE design-record ran      record "$rid" design-record ran "$r6"
      _vr_w "$f" "$clnr" OUTCOME design-record end   outcome "$rid" design-record end caught=false
    fi
  fi
  append_run_line "$rid" "$(printf '%s | ROUND | close | token=%s verdict=%s' "$(now)" "$token" "$verdict")"
}

# validate-round close <rid> <token> verdict=.. critical=.. warnings=.. agents=..
# r6=.. [summary=..]: write the round's records in a fixed order, then `ROUND close`.
_vr_close() {
  local rid="${1:-}" token="${2:-}"
  [ -n "$rid" ] && [ -n "$token" ] || { echo "usage: validate-round close <rid> <token> [k=v ...]" >&2; exit 64; }
  shift 2
  [[ "$token" =~ $_VR_TOK_RE ]] || { echo "validate-round: malformed token" >&2; exit 64; }
  # `close <rid> <token>` alone resumes a `closing kind=close` round (no drift check).
  [ "$#" -eq 0 ] && { _vr_close_resume "$rid" "$token"; return; }
  local verdict="" critical="" warnings="" agents="" r6="" summary="" seen=" " kv k v
  for kv in "$@"; do
    case "$kv" in *=*) ;; *) echo "validate-round: '$kv' is not key=value" >&2; exit 64 ;; esac
    k="${kv%%=*}"; v="${kv#*=}"
    case "$k" in verdict|critical|warnings|agents|r6|summary) ;; *) echo "validate-round: unknown key '$k'" >&2; exit 64 ;; esac
    case "$seen" in *" $k "*) echo "validate-round: repeated key '$k'" >&2; exit 64 ;; esac
    seen="$seen$k "
    case "$k" in
      r6|summary) _vr_refuse_ctl "$k" "$v" ;;
    esac
    case "$k" in
      verdict)  case "$v" in APPROVED|NEEDS-REVISION) ;; *) echo "validate-round: verdict must be APPROVED|NEEDS-REVISION" >&2; exit 64 ;; esac; verdict="$v" ;;
      critical) case "$v" in ''|*[!0-9]*) echo "validate-round: critical must be a non-negative integer" >&2; exit 64 ;; esac; critical="$v" ;;
      warnings) case "$v" in ''|*[!0-9]*) echo "validate-round: warnings must be a non-negative integer" >&2; exit 64 ;; esac; warnings="$v" ;;
      agents)   case "$v" in ''|*[!0-9]*) echo "validate-round: agents must be an integer" >&2; exit 64 ;; esac
                [ "$v" -ge 1 ] || { echo "validate-round: agents must be >= 1" >&2; exit 64; }
                agents="$v" ;;
      r6)       r6="$v" ;;
      summary)  summary="$v" ;;
    esac
  done
  local missing=""
  [ -n "$verdict" ]  || missing="$missing verdict"
  [ -n "$critical" ] || missing="$missing critical"
  [ -n "$warnings" ] || missing="$missing warnings"
  [ -n "$agents" ]   || missing="$missing agents"
  [ -n "$r6" ]       || missing="$missing r6"
  [ -n "$missing" ]  && { echo "validate-round: missing keys:$missing" >&2; exit 64; }
  # r6 = `design-bearing=<yes|no> pass` | `design-bearing=<yes|no> critical: <finding>`
  local db r6rest r6crit=0 dbok=0
  db="${r6%% *}"; r6rest="${r6#* }"
  case "$db" in design-bearing=yes|design-bearing=no) dbok=1 ;; esac
  { [ "$r6rest" != "$r6" ] && [ "$dbok" = 1 ]; } \
    || { echo "validate-round: r6 must be 'design-bearing=<yes|no> pass|critical: <finding>'" >&2; exit 64; }
  case "$r6rest" in
    pass) ;;
    "critical: "?*) r6crit=1 ;;
    *) echo "validate-round: r6 must end in 'pass' or 'critical: <finding>'" >&2; exit 64 ;;
  esac
  # verdict/count consistency: APPROVED wants critical=0 and R6 pass; NEEDS-REVISION
  # wants critical>=1 (which an R6 `critical:` finding also requires).
  if [ "$verdict" = "APPROVED" ]; then
    [ "$critical" = "0" ] || { echo "validate-round: APPROVED needs critical=0" >&2; exit 64; }
    [ "$r6crit" = 0 ]     || { echo "validate-round: APPROVED needs r6 pass" >&2; exit 64; }
  else
    [ "$critical" -ge 1 ] || { echo "validate-round: NEEDS-REVISION needs critical>=1" >&2; exit 64; }
  fi
  [ "$r6crit" = 0 ] || { [ "$verdict" = "NEEDS-REVISION" ] && [ "$critical" -ge 1 ]; } \
    || { echo "validate-round: r6 'critical:' needs NEEDS-REVISION with critical>=1" >&2; exit 64; }
  [ -n "$summary" ] || summary="$critical critical"
  _vr_load "$rid"
  { [ "$_vrL_state" = "open" ] && [ "$_vrL_token" = "$token" ]; } \
    || { echo "validate-round: last ROUND for '$rid' is not an open carrying this token" >&2; exit 1; }
  # Drift: compare the ledger tail and the three repo pins against the ROUND open
  # line. `top` comes from the stored line (the spec's directory may be gone).
  local f4 top spec_p blob_o head_o por_o drift="" last_line blob_now head_now por_now voids
  f4="$_vrL_f4"
  top="$(_vr_kv "$f4" top)";      spec_p="$(_vr_kv "$f4" spec)"
  blob_o="$(_vr_kv "$f4" blob)";  head_o="$(_vr_kv "$f4" head)"; por_o="$(_vr_kv "$f4" porcelain)"
  last_line="$(tail -1 "$_vrL_f")"
  if [ "$last_line" != "$_vrL_last" ]; then
    drift="ledger"
    printf 'validate-round: ledger lines after the pinned ROUND open:\n' >&2
    # the line goes via ENVIRON so backslashes in it are not escape-processed
    VR_O="$_vrL_last" awk '{buf[NR]=$0; if($0==ENVIRON["VR_O"])m=NR} END{for(i=m+1;i<=NR;i++)print buf[i]}' "$_vrL_f" \
      | while IFS= read -r line; do _vr_print_foreign "$line"; done
  fi
  # A missing, symlinked or unreadable spec is blob drift, never a git failure.
  blob_now=""
  if [ -f "$spec_p" ] && [ ! -L "$spec_p" ] && [ -r "$spec_p" ]; then
    blob_now="$(git -C "$top" hash-object "$spec_p")"
  fi
  [ "$blob_now" = "$blob_o" ] || drift="${drift}${drift:+,}blob"
  head_now="$(git -C "$top" rev-parse HEAD)"
  [ "$head_now" = "$head_o" ] || drift="${drift}${drift:+,}head"
  por_now="$(_vr_porcelain "$top")"
  [ "$por_now" = "$por_o" ] || drift="${drift}${drift:+,}porcelain"
  if [ -n "$drift" ]; then
    # restart budget: one void per validation; a second void since the last
    # round-terminal line stops the round as incomplete instead of retrying.
    voids="$(awk -F' [|] ' '$2=="ROUND" && ($3=="close"||$3=="incomplete"){v=0} $2=="ROUND" && $3=="void"{v++} END{print v+0}' "$_vrL_f")"
    append_run_line "$rid" "$(printf '%s | ROUND | void | token=%s why=%s' "$(now)" "$token" "$drift")"
    if [ "$voids" -ge 1 ]; then
      _vr_incomplete_block "$rid" "$token" "restart budget spent"
      exit 3
    fi
    exit 2
  fi
  append_run_line "$rid" "$(printf '%s | ROUND | closing | token=%s kind=close verdict=%s critical=%s warnings=%s agents=%s | %s | %s' \
    "$(now)" "$token" "$verdict" "$critical" "$warnings" "$agents" "$r6" "$summary")"
  local clnr
  clnr="$(wc -l < "$_vrL_f" | tr -d ' ')"
  _vr_close_records "$rid" "$token" "$verdict" "$critical" "$warnings" "$agents" "$r6" "$summary" "$clnr"
  printf 'blob=%s\n' "${token%%.*}"
}

# The validation-wide caught rollup for one gate (DEC-N): the window opens after
# the latest of the rid's first `ROUND open`, the previous validation-terminal
# ROUND (`close` verdict=APPROVED or `incomplete`) and the latest
# `GATE | validate | ran`; it counts only `OUTCOME <phase> end caught=true` lines
# the verb wrote itself (inside a closing..ROUND block), and it reads only lines
# before this round's own `closing` so the round's own `ran` never bounds it.
_vr_caught() {
  awk -F' [|] ' -v ph="$3" -v endb="$2" '
    NR>=endb { exit }
    $2=="ROUND" {
      if ($3=="open" && fo==0) fo=NR
      if (($3=="close" && $4 ~ /(^| )verdict=APPROVED( |$)/) || $3=="incomplete") term=NR
      inblk = ($3=="closing")
    }
    $2=="GATE" && $3=="validate" && $4=="ran" { vran=NR }
    $2=="OUTCOME" && $3==ph && $4=="end" && inblk && $5 ~ /(^| )caught=true( |$)/ { hit=NR }
    END { s=fo; if (term>s) s=term; if (vran>s) s=vran; print (hit>s) ? "true" : "false" }
  ' "$1"
}

# `close <rid> <token>` resume: last ROUND must be `closing kind=close` carrying
# the token; the pinned fields rebuild the planned records, and only missing ones
# are written.
_vr_close_resume() {
  local rid="$1" token="$2"
  _vr_load "$rid"
  local kind clnr
  kind="$(_vr_kv "$_vrL_f4" kind)"
  { [ "$_vrL_state" = "closing" ] && [ "$_vrL_token" = "$token" ] && [ "$kind" = "close" ]; } \
    || { echo "validate-round: last ROUND for '$rid' is not a closing kind=close with this token" >&2; exit 1; }
  local verdict critical warnings agents r6 summary
  verdict="$(_vr_kv "$_vrL_f4" verdict)";  critical="$(_vr_kv "$_vrL_f4" critical)"
  warnings="$(_vr_kv "$_vrL_f4" warnings)"; agents="$(_vr_kv "$_vrL_f4" agents)"
  r6="$(_vr_field "$_vrL_last" 5)"; summary="$(_vr_field "$_vrL_last" 6)"
  clnr="$(awk -F' [|] ' '$2=="ROUND"{n=NR} END{print n+0}' "$_vrL_f")"
  _vr_close_records "$rid" "$token" "$verdict" "$critical" "$warnings" "$agents" "$r6" "$summary" "$clnr"
  printf 'blob=%s\n' "${token%%.*}"
}

# The incomplete stop's writes: `ROUND closing kind=incomplete` (skipped when the
# closing line already exists, i.e. resume), the paired skipped records, and the
# terminal `ROUND incomplete`.
_vr_incomplete_block() {
  local rid="$1" token="$2" reason="$3" clnr="${4:-}"
  local f; f="$(ledger_file "$rid")"
  if [ -z "$clnr" ]; then
    append_run_line "$rid" "$(printf '%s | ROUND | closing | token=%s kind=incomplete | %s' "$(now)" "$token" "$reason")"
    clnr="$(wc -l < "$f" | tr -d ' ')"
  fi
  _vr_check_resume "$f" "$clnr" \
    "GATE | validate | skipped | incomplete: $reason" \
    "OUTCOME | validate | end | at=E caught=false dur_s=D" \
    "GATE | design-record | skipped | incomplete: $reason" \
    "OUTCOME | design-record | end | at=E caught=false dur_s=D" \
    || exit 1
  _vr_w "$f" "$clnr" GATE validate skipped        record "$rid" Validate skipped "incomplete: $reason"
  _vr_w "$f" "$clnr" OUTCOME validate end         outcome "$rid" Validate end caught=false
  _vr_w "$f" "$clnr" GATE design-record skipped   record "$rid" design-record skipped "incomplete: $reason"
  _vr_w "$f" "$clnr" OUTCOME design-record end    outcome "$rid" design-record end caught=false
  append_run_line "$rid" "$(printf '%s | ROUND | incomplete | token=%s' "$(now)" "$token")"
}

# validate-round incomplete: `incomplete <rid> <token> <reason>` records a stopped
# round over open|void; `incomplete <rid> --stale <reason>` resolves the token from
# the last ROUND line (open|void, or resume a closing kind=incomplete with its
# pinned reason); `incomplete <rid> <token>` resumes a closing kind=incomplete.
_vr_incomplete() {
  local rid="${1:-}" a2="${2:-}"
  [ -n "$rid" ] && [ -n "$a2" ] || { echo "usage: validate-round incomplete <rid> (<token> [reason]|--stale <reason>)" >&2; exit 64; }
  local token reason kind clnr
  if [ "$a2" = "--stale" ]; then
    [ $# -eq 3 ] || { echo "usage: validate-round incomplete <rid> --stale <reason>" >&2; exit 64; }
    reason="$3"
    [ -n "$reason" ] || { echo "validate-round: reason may not be empty" >&2; exit 64; }
    _vr_refuse_ctl reason "$reason"
    _vr_load "$rid"
    case "$_vrL_state" in
      open|void)
        _vr_incomplete_block "$rid" "$_vrL_token" "$reason" ;;
      closing)
        kind="$(_vr_kv "$_vrL_f4" kind)"
        [ "$kind" = "incomplete" ] || { echo "validate-round: --stale cannot resume a closing kind=close" >&2; exit 1; }
        printf 'validate-round: resuming a closing round; reason ignored: %s\n' "$reason" >&2
        clnr="$(awk -F' [|] ' '$2=="ROUND"{n=NR} END{print n+0}' "$_vrL_f")"
        _vr_incomplete_block "$rid" "$_vrL_token" "$(_vr_field "$_vrL_last" 5)" "$clnr" ;;
      *) echo "validate-round: --stale needs an open, void or closing kind=incomplete round" >&2; exit 1 ;;
    esac
    return 0
  fi
  token="$a2"
  [[ "$token" =~ $_VR_TOK_RE ]] || { echo "validate-round: malformed token" >&2; exit 64; }
  _vr_load "$rid"
  if [ $# -ge 3 ]; then
    [ $# -eq 3 ] || { echo "usage: validate-round incomplete <rid> <token> <reason>" >&2; exit 64; }
    reason="$3"
    [ -n "$reason" ] || { echo "validate-round: reason may not be empty" >&2; exit 64; }
    _vr_refuse_ctl reason "$reason"
    { { [ "$_vrL_state" = "open" ] || [ "$_vrL_state" = "void" ]; } && [ "$_vrL_token" = "$token" ]; } \
      || { echo "validate-round: last ROUND for '$rid' is not an open/void carrying this token" >&2; exit 1; }
    _vr_incomplete_block "$rid" "$token" "$reason"
  else
    # resume: `closing kind=incomplete` carrying the token; the reason is pinned.
    kind="$(_vr_kv "$_vrL_f4" kind)"
    { [ "$_vrL_state" = "closing" ] && [ "$kind" = "incomplete" ] && [ "$_vrL_token" = "$token" ]; } \
      || { echo "validate-round: last ROUND for '$rid' is not a closing kind=incomplete with this token" >&2; exit 1; }
    clnr="$(awk -F' [|] ' '$2=="ROUND"{n=NR} END{print n+0}' "$_vrL_f")"
    _vr_incomplete_block "$rid" "$token" "$(_vr_field "$_vrL_last" 5)" "$clnr"
  fi
}

# Scoped wrapper: the ERR trap maps every unplanned failure (a git call dying, a
# missing tool) to exit 1, while the planned exits above keep their own codes.
# The subshell keeps file scope clean: other verbs keep `set -euo pipefail` as-is.
validate_round() {
  ( set -E; trap 'exit 1' ERR; _vr_dispatch "$@" )
}

_vr_dispatch() {
  local sub="${1:-}"
  case "$sub" in
    open|close|incomplete) shift ;;
    *) echo "usage: validate-round {open|close|incomplete} ..." >&2; exit 64 ;;
  esac
  # Strip every repo-local git env var once for the verb (an inherited
  # GIT_DIR/GIT_COMMON_DIR would override `git -C` discovery); the list is
  # git's own so new vars are covered.
  unset $(git rev-parse --local-env-vars)
  "_vr_$sub" "$@"
}


cmd="${1:-}"; shift 2>/dev/null || true
case "$cmd" in
  required) required "$@" ;;
  start)    start "$@" ;;
  record)   record "$@" ;;
  action)   action "$@" ;;
  tokens)   tokens "$@" ;;
  debt)     debt "$@" ;;
  debt-response) debt_response "$@" ;;
  outcome)      outcome "$@" ;;
  outcome-read) outcome_read "$@" ;;
  mutation) mutation "$@" ;;
  config)   config_stamp "$@" ;;
  override) override "$@" ;;
  plan-record) plan_record "$@" ;;
  inherit)  inherit "$@" ;;
  check)    check "$@" ;;
  show)     show "$@" ;;
  plan)     plan "$@" ;;
  progress) progress "$@" ;;
  rid)      rid "$@" ;;
  descent)  descent "$@" ;;
  history) history "$@" ;;
  report)  report "$@" ;;
  validate-round) validate_round "$@" ;;
  *) echo "usage: gate-ledger.sh {required|start|record|action|tokens|debt|debt-response|outcome|outcome-read|mutation|config|override|plan-record|inherit|check|show|plan|progress|rid|descent|history|report|validate-round} ..." >&2; exit 64 ;;
esac
