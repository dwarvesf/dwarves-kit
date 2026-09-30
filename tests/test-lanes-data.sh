#!/usr/bin/env bash
# test-lanes-data.sh -- lanes as data: the lane reader, the light default classifier, the
# hard-path floor, and the ship-gate wiring. Each case prints `PASS <name>` or
# `FAIL <name>: <why>`; the file exits nonzero on any FAIL.
#
# Run: bash tests/test-lanes-data.sh [case ...]   (no args = every case)
#      bash tests/test-lanes-data.sh baseline     (rewrites docs/verification/lanes-as-data/baseline.txt)
#
# Isolation: every case builds temp repos and a temp DWARVES_KIT_LOG_DIR; the real ledger
# corpus and the operator overlay are never read or written.

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GL="$KIT_DIR/lib/gate/gate-ledger.sh"
LC="$KIT_DIR/lib/classify/lane-classify.sh"
GP="$KIT_DIR/lib/gate/gate-policy.sh"
HOOK="$KIT_DIR/hooks/ship-gate.sh"
BASELINE="$KIT_DIR/docs/verification/lanes-as-data/baseline.txt"
LANES="tiny normal full bug backfill"

FAILS=0
TMPS=()
_mk() { local d; d="$(mktemp -d)"; TMPS+=("$d"); printf '%s' "$d"; }
cleanup() { local d; for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1: $2"; FAILS=$((FAILS+1)); }

# Every gate-ledger call in this file runs on a temp log dir with no operator overlay.
LOGD=""
new_log() { LOGD="$(_mk)/logs"; mkdir -p "$LOGD/runs"; }
gl() { env DWARVES_KIT_LOG_DIR="$LOGD" KIT_CONFIG_OPERATOR=/nonexistent bash "$GL" "$@"; }

# ---------------------------------------------------------------------------
# capture: plan + required for all five lanes, plus progress + descent against a canned
# fixture ledger (fixed rid; ran, skipped, bare skip, override, one out-of-order record).
# ---------------------------------------------------------------------------
capture() {
  new_log
  local rid=fixture-rid l
  {
    printf '%s\n' "2026-01-01T00:00:00Z | START | lane=normal classified=normal type=spec-feature repo=fx"
    printf '%s\n' "2026-01-01T00:00:01Z | GATE | grill | ran | fixture"
    printf '%s\n' "2026-01-01T00:00:02Z | GATE | build | ran | out of order on purpose"
    printf '%s\n' "2026-01-01T00:00:03Z | GATE | spec | ran | fixture"
    printf '%s\n' "2026-01-01T00:00:04Z | GATE | think | skipped | fixture reason"
    printf '%s\n' "2026-01-01T00:00:05Z | GATE | review | skipped | "
    printf '%s\n' "2026-01-01T00:00:06Z | GATE | validate | override | fixture override"
  } > "$LOGD/runs/$rid.log"
  for l in $LANES; do
    echo "== plan $l";     gl plan "$l" 2>&1
    echo "== required $l"; gl required "$l" 2>&1
    echo "== progress $l"; gl progress "$rid" "$l" 2>&1
    echo "== descent $l";  gl descent "$rid" "$l" 2>&1
  done
}

case_baseline() { mkdir -p "$(dirname "$BASELINE")"; capture > "$BASELINE"; echo "wrote $BASELINE ($(wc -l < "$BASELINE") lines)"; }

case_parity() {
  local d; d="$(diff "$BASELINE" <(capture))" && pass parity || fail parity "reader output differs from the baseline: $(printf '%s' "$d" | head -6 | tr '\n' '~')"
}

# After the normal-lane flip only normal's validate and review may differ from the baseline.
# Each output line is prefixed with its section header so a changed line names its lane.
_annotate() { awk '/^== /{sec=$2" "$3; next} {print sec ": " $0}'; }
case_parity_after_flip() {
  local d bad
  d="$(diff <(_annotate < "$BASELINE") <(capture | _annotate) | grep -E '^[<>]' || true)"
  [ -n "$d" ] || { fail parity-after-flip "no difference: the flip did not land"; return; }
  bad="$(printf '%s\n' "$d" | grep -vE '^[<>] (plan|required|progress|descent) normal: .*(validate|review)' || true)"
  if [ -z "$bad" ]; then pass parity-after-flip
  else fail parity-after-flip "unexpected changed lines: $(printf '%s' "$bad" | head -4 | tr '\n' '~')"; fi
}
case_plan_flip() {
  local out; new_log
  out="$(gl required normal | tr '\n' ' ')"
  [ "$out" = "spec validate build review ship " ] && pass plan-flip || fail plan-flip "required normal = '$out'"
}

# ---------------------------------------------------------------------------
# Fixture helpers: a temp repo on branch feat/x off main, with the proof marker and a committed
# .kit.toml that turns lane_gates on. Nothing here touches a real repo or the real ledger.
# ---------------------------------------------------------------------------
lcx() { env KIT_CONFIG_OPERATOR=/nonexistent DWARVES_KIT_LOG_DIR="${LOGD:-/nonexistent}" bash "$LC" "$@"; }
ROOT=""
_git() { git -C "$ROOT" -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
# _commit <message>: commit everything staged, quietly.
_commit() { _git add -A -f >/dev/null 2>&1; _git commit -q -m "$1" >/dev/null 2>&1; }
mkrepo() {
  ROOT="$(_mk)"
  git init -q -b main "$ROOT" >/dev/null 2>&1
  git -C "$ROOT" config user.email t@t; git -C "$ROOT" config user.name t
  mkdir -p "$ROOT/docs/verification" "$ROOT/docs/specs"
  echo m > "$ROOT/docs/verification/README.md"
  printf '[gate]\nlane_gates = true\n' > "$ROOT/.kit.toml"
  echo hi > "$ROOT/README.md"
  _commit "chore: init"
  _git checkout -q -b feat/x >/dev/null 2>&1
}
# addfile <path> <content>: add one file and commit it on the branch.
addfile() {
  mkdir -p "$(dirname "$ROOT/$1")"; printf '%s\n' "$2" > "$ROOT/$1"
  _commit "chore: add file"
}
floor_out() { lcx floor "$ROOT" main 2>/dev/null; }

case_four_false_hits() {
  local t out bad=""
  for t in "add token count column" "add queue timeout" "add webhook retry log line" "add user role label"; do
    out="$(lcx classify "$t" 2>&1)"; [ "$out" = normal ] || bad="$bad [$t => $out]"
  done
  [ -z "$bad" ] && pass four-false-hits || fail four-false-hits "$bad"
}

case_webhook_signature_suggests() {
  local err; err="$(lcx classify "add webhook signature check" 2>&1 >/dev/null)"
  case "$err" in *"LANE-SUGGEST: full (external-provider)"*) pass webhook-signature-suggests ;; *) fail webhook-signature-suggests "stderr: $err" ;; esac
}

case_suggest_records() {
  new_log
  local out err led extra
  out="$(lcx classify --rid sr-1 "add a users table migration" 2>/dev/null)"
  err="$(lcx classify --rid sr-1 "add a users table migration" 2>&1 >/dev/null)"
  led="$(cat "$LOGD/runs/sr-1.log" 2>/dev/null)"
  lcx classify "add a users table migration" >/dev/null 2>&1
  extra="$(ls "$LOGD/runs" 2>/dev/null | grep -vc '^sr-1\.log$' || true)"
  if [ "$out" = normal ] && printf '%s' "$err" | grep -qF 'LANE-SUGGEST: full (data-model)' \
     && printf '%s' "$led" | grep -qF '| ACTION | lane-suggest full flags=data-model' && [ "$extra" = 0 ]; then pass suggest-records
  else fail suggest-records "out=$out err=$err ledger=$led extra-ledgers=$extra"; fi
}

case_explain_suggest_line() {
  local out; out="$(lcx explain "add webhook signature check" 2>/dev/null)"
  printf '%s' "$out" | grep -qF 'suggest: full (external-provider)' && pass explain-suggest-line || fail explain-suggest-line "$out"
}

case_classify_files_full() {
  local out; out="$(lcx classify --files "db/migrations/0001_users.sql" "add a users table migration" 2>/dev/null)"
  [ "$out" = full ] && pass classify-files-full || fail classify-files-full "got $out"
}

case_escalate_suggest() {
  local d f out err; d="$(_mk)"; f="$d/spec.md"
  printf '# spec\nAdd jwt authentication for the api.\n' > "$f"
  out="$(lcx escalate normal "$f" 2>/dev/null)"; err="$(lcx escalate normal "$f" 2>&1 >/dev/null)"
  if [ "$out" = "HOLD normal" ] && printf '%s' "$err" | grep -q 'LANE-SUGGEST'; then pass escalate-suggest
  else fail escalate-suggest "out=$out err=$err"; fi
}

case_floor_paths() {
  local p bad="" out
  for p in alembic/versions/x.py drizzle/0001.sql db/changelog/db.changelog-master.xml .github/workflows/ci.yml .kit.toml \
           db/migrations/0001_users.sql src/auth/login.py config/secrets/prod.txt certs/site.pem app/.env; do
    mkrepo; addfile "$p" "x"
    out="$(floor_out)"; case "$out" in "full "*": $p"*) ;; *) bad="$bad [$p => '$out']" ;; esac
  done
  for p in .env.example CHANGELOG.md src/app.py docs/notes.md; do
    mkrepo; addfile "$p" "x"
    out="$(floor_out)"; [ -z "$out" ] || bad="$bad [$p should not hit: '$out']"
  done
  [ -z "$bad" ] && pass floor-paths || fail floor-paths "$bad"
}

# A file moved OUT of a hard path still hits: both sides of a rename are listed.
case_floor_rename_counts_both_sides() {
  mkrepo
  _git checkout -q main >/dev/null 2>&1
  mkdir -p "$ROOT/db/migrations"; echo "select 1" > "$ROOT/db/migrations/z.sql"; _commit "chore: seed migration"
  _git checkout -q -b feat/w >/dev/null 2>&1
  mkdir -p "$ROOT/tests"; _git mv db/migrations/z.sql tests/z.sql >/dev/null 2>&1; _commit "chore: move it"
  local out; out="$(lcx floor "$ROOT" main 2>/dev/null)"
  case "$out" in "full migration: db/migrations/z.sql") pass floor-rename-counts-both-sides ;; *) fail floor-rename-counts-both-sides "got '$out'" ;; esac
}

case_floor_data_loss() {
  local bad="" out path content want
  while IFS='|' read -r path content want; do
    [ -n "$path" ] || continue
    mkrepo; addfile "$path" "$content"; out="$(floor_out)"
    if [ "$want" = hit ]; then case "$out" in "full data-loss: $path") ;; *) bad="$bad [$content in $path => '$out']" ;; esac
    else [ -z "$out" ] || bad="$bad [$content in $path should not hit: '$out']"; fi
  done <<'CASES'
app/db.py|DROP TABLE users;|hit
app/db.py|db.execute("TRUNCATE users;")|hit
app/db.js|await db.users.deleteMany({})|hit
db/reset.sql|TRUNCATE users|hit
app/db.py|DELETE FROM users|hit
app/db.py|DELETE FROM users WHERE id = 1|miss
app/fmt.py|# truncate long names|miss
app/fmt.py|name.truncate(20)|miss
docs/notes.md|DROP TABLE users;|miss
docs/notes.md|db.execute("TRUNCATE users;")|miss
CASES
  [ -z "$bad" ] && pass floor-data-loss || fail floor-data-loss "$bad"
}

# A dirty .kit.toml that deletes an extra_hard_paths entry cannot drop it: the HEAD copy counts too.
case_floor_extra_paths_union() {
  mkrepo
  printf '[gate]\nlane_gates = true\n[lanes]\nextra_hard_paths = "^payments/"\n' > "$ROOT/.kit.toml"
  _commit "chore: extra path"
  _git checkout -q -b feat/x2 >/dev/null 2>&1
  addfile payments/charge.py "x"
  printf '[gate]\nlane_gates = true\n[lanes]\nextra_hard_paths = ""\n' > "$ROOT/.kit.toml"
  local out; out="$(lcx floor "$ROOT" feat/x 2>/dev/null)"
  case "$out" in "full extra: payments/charge.py") pass floor-extra-paths-union ;; *) fail floor-extra-paths-union "got '$out'" ;; esac
}

case_floor_invalid_extra_ere() {
  mkrepo
  printf '[gate]\nlane_gates = true\n[lanes]\nextra_hard_paths = "(unclosed"\n' > "$ROOT/.kit.toml"
  _commit "chore: bad ere"
  _git branch -q cfgbase >/dev/null 2>&1
  addfile src/app.py "x"
  local out err; out="$(lcx floor "$ROOT" cfgbase 2>/dev/null)"; err="$(lcx floor "$ROOT" cfgbase 2>&1 >/dev/null)"
  if [ -z "$out" ] && printf '%s' "$err" | grep -q 'not a valid ERE'; then pass floor-invalid-extra-ere; else fail floor-invalid-extra-ere "out='$out' err='$err'"; fi
}

# ---------------------------------------------------------------------------
run_case() {
  local fn="case_${1//-/_}"
  if declare -F "$fn" >/dev/null; then "$fn"; else fail "$1" "no such case"; fi
}
# `parity` (byte-identical against the baseline) holds only at the refactor commit; after the
# flip the standing check is parity-after-flip.
ALL="parity-after-flip plan-flip four-false-hits webhook-signature-suggests suggest-records explain-suggest-line classify-files-full escalate-suggest floor-paths floor-rename-counts-both-sides floor-data-loss floor-extra-paths-union floor-invalid-extra-ere"
if [ "$#" -eq 0 ]; then set -- $ALL; fi
for c in "$@"; do run_case "$c"; done
[ "$FAILS" -eq 0 ]
