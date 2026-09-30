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
gl() { env DWARVES_KIT_LOG_DIR="$LOGD" KIT_CONFIG_OPERATOR="${GL_OPERATOR:-/nonexistent}" bash "$GL" "$@"; }

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
mkrepo() {   # mkrepo [true|false] [branch]: the lane_gates value committed on the default branch (default true), and its name (default main)
  ROOT="$(_mk)"
  git init -q -b "${2:-main}" "$ROOT" >/dev/null 2>&1
  git -C "$ROOT" config user.email t@t; git -C "$ROOT" config user.name t
  mkdir -p "$ROOT/docs/verification" "$ROOT/docs/specs"
  echo m > "$ROOT/docs/verification/README.md"
  printf '[gate]\nlane_gates = %s\n' "${1:-true}" > "$ROOT/.kit.toml"
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
           db/migrations/0001_users.sql src/auth/login.py config/secrets/prod.txt certs/site.pem app/.env \
           src/authentication/x.go src/auth_service.py .github/actions/a/action.yml Dockerfile terraform/iam.tf; do
    mkrepo; addfile "$p" "x"
    out="$(floor_out)"; case "$out" in "full "*": $p"*) ;; *) bad="$bad [$p => '$out']" ;; esac
  done
  for p in .env.example CHANGELOG.md src/app.py docs/notes.md src/authors.go terraform/main.tf; do
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
app/db.py|DELETE FROM users WHERE 1=1|hit
app/db.py|x("DROP  TABLE users")|hit
app/db.py|x("TRUNCATE users")|hit
db/reset.sql|TRUNCATE TABLE users|hit
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
# Lane data overrides (project layer), the base-pinned gate switch, and the ship-gate wiring.
# ---------------------------------------------------------------------------
NORMAL_PHASES='["think", "spec", "validate", "design-record", "test-plan", "build", "review", "docs", "ship"]'
# commit_kit_toml <content>: write .kit.toml (always keeps the lane_gates switch on) and commit it.
commit_kit_toml() { printf '[gate]\nlane_gates = true\n%s\n' "$1" > "$ROOT/.kit.toml"; _commit "chore: kit config"; }
plan_phases() { KIT_PROJECT_ROOT="$ROOT" gl plan "$1" 2>/dev/null | awk '{print $2}' | tr '\n' ' '; }

case_override_drop_review() {
  mkrepo; new_log
  commit_kit_toml '[lane.normal]
phases = ["think", "spec", "validate", "design-record", "test-plan", "build", "ship", "docs"]
light  = ["think", "design-record", "test-plan", "docs"]'
  local plan; plan="$(plan_phases normal)"
  KIT_PROJECT_ROOT="$ROOT" gl start ov-1 normal normal feature >/dev/null 2>&1
  local led; led="$(gl show ov-1 2>/dev/null)"
  if ! printf '%s' "$plan" | grep -qw review && printf '%s' "$led" | grep -qF '| GATE | review | skipped | repo lane override (.kit.toml)'; then pass override-drop-review
  else fail override-drop-review "plan='$plan' ledger='$led'"; fi
}

case_override_uncommitted() {
  mkrepo; new_log
  printf '[gate]\nlane_gates = true\n[lane.normal]\nphases = ["spec", "build", "ship"]\n[lanes]\ndefault = "bug"\n' > "$ROOT/.kit.toml"
  local plan err cls cerr
  plan="$(plan_phases normal)"; err="$(KIT_PROJECT_ROOT="$ROOT" gl plan normal 2>&1 >/dev/null)"
  cls="$(KIT_PROJECT_ROOT="$ROOT" lcx classify "add a users page" 2>/dev/null)"
  cerr="$(KIT_PROJECT_ROOT="$ROOT" lcx classify "add a users page" 2>&1 >/dev/null)"
  if printf '%s' "$plan" | grep -qw review && [ "$cls" = normal ] \
     && printf '%s' "$err" | grep -q 'not committed and clean' && printf '%s' "$cerr" | grep -qF '[lanes] default'; then pass override-uncommitted
  else fail override-uncommitted "plan='$plan' classify='$cls' err='$err' cerr='$cerr'"; fi
}

case_override_typo() {
  mkrepo; new_log
  commit_kit_toml '[lane.normal]
phases = ["spec", "reveiw", "build", "ship"]'
  local kit got err
  kit="$(KIT_PROJECT_ROOT=/nonexistent gl plan normal 2>/dev/null)"; got="$(KIT_PROJECT_ROOT="$ROOT" gl plan normal 2>/dev/null)"
  err="$(KIT_PROJECT_ROOT="$ROOT" gl plan normal 2>&1 >/dev/null)"
  if [ "$kit" = "$got" ] && printf '%s' "$err" | grep -q "reveiw"; then pass override-typo
  else fail override-typo "plans differ or stderr misses the phase: '$err'"; fi
}

case_override_no_light() {
  mkrepo; new_log
  commit_kit_toml '[lane.normal]
phases = ["spec", "build", "ship"]'
  local got; got="$(KIT_PROJECT_ROOT="$ROOT" gl required normal 2>/dev/null | tr '\n' ' ')"
  [ "$got" = "spec build ship " ] && pass override-no-light || fail override-no-light "required normal = '$got'"
}

case_pinned_root() {
  new_log
  local evil; evil="$(_mk)"
  printf '[lane.normal]\nphases = ["spec", "build"]\nlight = []\n' > "$evil/kit.toml"
  local got; got="$(KIT_PROJECT_ROOT=/nonexistent KIT_CONFIG_ROOT="$evil" DWARVES_KIT="$evil" gl required normal 2>/dev/null | tr '\n' ' ')"
  [ "$got" = "spec validate build review ship " ] && pass pinned-root || fail pinned-root "required normal = '$got'"
}

case_malformed_array_fails_closed() {
  mkrepo; new_log
  commit_kit_toml '[lane.normal]
phases = ["spec",'
  local err rc=0
  err="$(KIT_PROJECT_ROOT="$ROOT" gl check normal mf-1 2>&1)" || rc=$?
  if [ "$rc" = 1 ] && printf '%s' "$err" | grep -q 'unknown lane'; then pass malformed-array-fails-closed
  else fail malformed-array-fails-closed "rc=$rc err=$err"; fi
}

case_policy_at_base() {
  mkrepo
  printf '[gate]\nlane_gates = false\n' > "$ROOT/.kit.toml"; _commit "chore: switch off"
  local at_rc=0 no_at_rc=0
  env KIT_CONFIG_OPERATOR=/nonexistent KIT_CONFIG_ROOT="$KIT_DIR" bash "$GP" enabled lane_gates "$ROOT" --at main >/dev/null 2>&1 || at_rc=$?
  env KIT_CONFIG_OPERATOR=/nonexistent KIT_CONFIG_ROOT="$KIT_DIR" bash "$GP" enabled lane_gates "$ROOT" >/dev/null 2>&1 || no_at_rc=$?
  if [ "$at_rc" = 0 ] && [ "$no_at_rc" = 1 ]; then pass policy-at-base
  else fail policy-at-base "--at main rc=$at_rc (want 0), no --at rc=$no_at_rc (want 1)"; fi
}

# ---- ship-gate hook ----
# ship_fixture <migration|none|dataloss|doc|clean> <spec-lane|none>: repo on feat/x, slug x, ledger in $LOGD.
ship_fixture() {
  local what="$1" lane="$2"
  mkrepo; new_log
  [ "$lane" = none ] || { printf 'Lane: %s\n' "$lane" > "$ROOT/docs/specs/SPEC-001-x.md"; }
  case "$what" in
    migration) mkdir -p "$ROOT/db/migrations"; echo "create table users (id int);" > "$ROOT/db/migrations/0001_users.sql" ;;
    dataloss)  mkdir -p "$ROOT/app"; echo 'DROP TABLE users;' > "$ROOT/app/db.py" ;;
    doc)       echo 'DROP TABLE users;' > "$ROOT/docs/notes.md" ;;
    truncate)  mkdir -p "$ROOT/app"; printf '# truncate long names\nname.truncate(20)\n' > "$ROOT/app/fmt.py" ;;
    clean)     mkdir -p "$ROOT/src"; echo "x = 1" > "$ROOT/src/app.py" ;;
  esac
  _commit "chore: change"
}
record_gates() { local p; for p in "$@"; do gl record x "$p" ran "fixture $p" >/dev/null 2>&1; done; }
# run_hook: pushes feat/x through the real hook in the fixture; sets HOOK_RC and HOOK_ERR.
# HOOK_CMD overrides the command, HOOK_CWD the directory the hook is invoked from.
run_hook() {
  HOOK_RC=0
  local cmd="${HOOK_CMD:-git push -u origin feat/x}" cwd="${HOOK_CWD:-$ROOT}" payload
  payload="$(jq -cn --arg c "$cmd" --arg d "$cwd" '{tool_input:{command:$c},cwd:$d}')"
  HOOK_ERR="$( cd "$cwd" && printf '%s' "$payload" \
    | env CLAUDE_PLUGIN_ROOT="$KIT_DIR" DWARVES_KIT_LOG_DIR="$LOGD" KIT_CONFIG_OPERATOR="${HOOK_OPERATOR:-/nonexistent}" KIT_CONFIG_ROOT="$KIT_DIR" \
      bash "$HOOK" 2>&1 >/dev/null )" || HOOK_RC=$?
}
NORMAL_GATES="spec validate build review ship"

case_ship_migration_blocks() {
  ship_fixture migration normal; record_gates $NORMAL_GATES
  run_hook
  local blocked_rc="$HOOK_RC" blocked_err="$HOOK_ERR" p
  for p in think design design-critique design-record test-plan docs reflect; do gl override x "$p" "fixture reason $p" >/dev/null 2>&1; done
  run_hook
  if [ "$blocked_rc" = 2 ] && printf '%s' "$blocked_err" | grep -qF 'hard path (migration' && [ "$HOOK_RC" = 0 ]; then pass ship-migration-blocks
  else fail ship-migration-blocks "blocked rc=$blocked_rc err=$blocked_err; after overrides rc=$HOOK_RC err=$HOOK_ERR"; fi
}

case_ship_migration_absent_quiet() {
  ship_fixture clean normal; record_gates $NORMAL_GATES; run_hook
  [ "$HOOK_RC" = 0 ] && pass ship-migration-absent-quiet || fail ship-migration-absent-quiet "rc=$HOOK_RC err=$HOOK_ERR"
}

case_ship_switch_off_on_base() {
  mkrepo false; new_log
  printf 'Lane: normal\n' > "$ROOT/docs/specs/SPEC-001-x.md"
  mkdir -p "$ROOT/db/migrations"; echo "create table t (id int);" > "$ROOT/db/migrations/0001_t.sql"; _commit "chore: change"
  record_gates $NORMAL_GATES; run_hook
  if [ "$HOOK_RC" = 0 ] && grep -q 'OFF-BY-CONFIG | floor' "$LOGD/ship-gate.log" 2>/dev/null; then pass ship-switch-off-on-base
  else fail ship-switch-off-on-base "rc=$HOOK_RC err=$HOOK_ERR log=$(cat "$LOGD/ship-gate.log" 2>/dev/null)"; fi
}

case_ship_flip_gate_in_pr() {
  ship_fixture migration normal
  printf '[gate]\nlane_gates = false\n' > "$ROOT/.kit.toml"; _commit "chore: flip the switch in the PR"
  record_gates $NORMAL_GATES; run_hook
  [ "$HOOK_RC" = 2 ] && pass ship-flip-gate-in-pr || fail ship-flip-gate-in-pr "rc=$HOOK_RC err=$HOOK_ERR"
}

case_ship_hollow_full_override() {
  ship_fixture migration full
  commit_kit_toml '[lane.full]
phases = ["build"]'
  record_gates build; run_hook
  [ "$HOOK_RC" = 2 ] && pass ship-hollow-full-override || fail ship-hollow-full-override "rc=$HOOK_RC err=$HOOK_ERR"
}

case_ship_data_loss() {
  local bad="" w rc
  for w in dataloss doc truncate; do
    ship_fixture "$w" normal; record_gates $NORMAL_GATES; run_hook
    case "$w" in dataloss) want=2 ;; *) want=0 ;; esac
    [ "$HOOK_RC" = "$want" ] || bad="$bad [$w rc=$HOOK_RC want $want: $HOOK_ERR]"
  done
  [ -z "$bad" ] && pass ship-data-loss || fail ship-data-loss "$bad"
}

# No spec: the floor needs no lane. A hard-path push still owes the full lane's gates or an audited
# override for the slug, so renaming a branch cannot dodge it. With the switch off at the base it passes.
case_ship_no_spec_blocks() {
  ship_fixture migration none; run_hook
  local rc1="$HOOK_RC" err1="$HOOK_ERR" p
  for p in think design design-critique spec validate design-record test-plan build review docs ship reflect; do gl override x "$p" "no-spec reason $p" >/dev/null 2>&1; done
  run_hook; local rc2="$HOOK_RC"
  mkrepo false; new_log; mkdir -p "$ROOT/db/migrations"; echo "create table t (id int);" > "$ROOT/db/migrations/0001_t.sql"; _commit "chore: change"
  run_hook
  if [ "$rc1" = 2 ] && printf '%s' "$err1" | grep -qF "no spec found for 'x'" && [ "$rc2" = 0 ] && [ "$HOOK_RC" = 0 ]; then pass ship-no-spec-blocks
  else fail ship-no-spec-blocks "no-spec rc=$rc1 err=$err1; after overrides rc=$rc2; switch off at base rc=$HOOK_RC"; fi
}

case_ship_suggest_advisory() {
  ship_fixture clean normal; record_gates $NORMAL_GATES
  gl action x "lane-suggest full flags=data-model" >/dev/null 2>&1
  run_hook
  if [ "$HOOK_RC" = 0 ] && printf '%s' "$HOOK_ERR" | grep -qF "the classifier suggested full (data-model) and the run ships as normal"; then pass ship-suggest-advisory
  else fail ship-suggest-advisory "rc=$HOOK_RC err=$HOOK_ERR"; fi
}

# The WORKFLOW.md lane x phase matrix is the human view of kit.toml [lane.*]: for every lane the
# non-skip cells, in order, equal `plan` (minus the grill intake line). LANES_WORKFLOW points the
# case at a mutated copy for the negative control.
WORKFLOW_VIEW="${LANES_WORKFLOW:-$KIT_DIR/docs/WORKFLOW.md}"
_view_rows() {  # <lane> -> "phase level" from the matrix
  awk -v lane="$1" '
    /^## Lane.*depth matrix/ {inmx=1; next}
    inmx && /^## / {exit}
    inmx && /^\| *Phase *\|/ { n=split($0,h,"|"); for(i=1;i<=n;i++){gsub(/^ +| +$/,"",h[i]); if(h[i]==lane) col=i}; next }
    inmx && col>0 && /^\|/ {
      if ($0 ~ /^\| *-+/) next
      split($0,c,"|"); ph=c[2]; cell=c[col]; gsub(/^ +| +$/,"",ph); gsub(/^ +| +$/,"",cell)
      sub(/ *\(.*\)/,"",ph); ph=tolower(ph); gsub(/ /,"-",ph)
      if (cell=="measure-twice") print ph " required"; else if (cell=="run-lite") print ph " lite"
    }' "$WORKFLOW_VIEW"
}
case_workflow_view() {
  new_log
  local l want got bad=""
  for l in $LANES; do
    want="$(_view_rows "$l")"
    got="$(gl plan "$l" 2>/dev/null | awk '$2!="grill"{print $2 " " $3}')"
    [ "$want" = "$got" ] || bad="$bad [$l: view='$(printf '%s' "$want" | tr '\n' ',')' data='$(printf '%s' "$got" | tr '\n' ',')']"
  done
  [ -z "$bad" ] && pass workflow-view || fail workflow-view "$bad"
}

# The hook times out fast and fails open, so the floor must stay flat as the diff grows:
# 1000 changed paths and 20000 added lines with the hard path LAST, extras configured, run under one second.
_now() { python3 -c 'import time;print(time.time())'; }
case_floor_timing() {
  mkrepo
  printf '[gate]\nlane_gates = true\n[lanes]\nextra_hard_paths = "^payments/|^ledger/"\n' > "$ROOT/.kit.toml"; _commit "chore: extras"
  _git branch -q timebase >/dev/null 2>&1
  mkdir -p "$ROOT/pad" "$ROOT/zz/auth"
  local i; for i in $(seq 1 1000); do seq 1 20 > "$ROOT/pad/f$i.txt"; done   # 1000 files, 20000 added lines
  echo x > "$ROOT/zz/auth/z.ts"; echo 'x = 1' > "$ROOT/pad/code.py"
  _commit "chore: padding"
  local t0 t1 out; t0="$(_now)"; out="$(lcx floor "$ROOT" timebase 2>/dev/null)"; t1="$(_now)"
  local ms; ms="$(python3 -c "print(int(($t1-$t0)*1000))")"
  if [ "$out" = "full auth: zz/auth/z.ts" ] && [ "$ms" -lt 2000 ]; then pass "floor-timing (${ms}ms for 1000 paths)"
  else fail floor-timing "out='$out' elapsed=${ms}ms (limit 2000ms; typical 500ms)"; fi
}

# Non-ASCII names must be matched as written (no C-quoted octal), including in added-line scans.
case_floor_non_ascii() {
  local bad="" out p
  for p in "secrets/naïve.txt" "clé.pem" "migrations/é.sql" "src/auth/prénom.ts"; do
    mkrepo; addfile "$p" "x"; out="$(floor_out)"
    case "$out" in "full "*": $p") ;; *) bad="$bad [$p => '$out']" ;; esac
  done
  mkrepo; echo more >> "$ROOT/README.md"; mkdir -p "$ROOT/app"; echo 'db.execute("DROP TABLE users")' > "$ROOT/app/migré.py"; _commit "chore: drop"
  out="$(floor_out)"; case "$out" in "full data-loss: app/migré.py") ;; *) bad="$bad [DROP TABLE in migré.py => '$out']" ;; esac
  mkrepo; mkdir -p "$ROOT/app"; echo 'db.execute("DROP TABLE users")' > "$ROOT/app/my file.py"
  _commit "chore: spaced name"; out="$(floor_out)"
  case "$out" in "full data-loss: app/my file.py") ;; *) bad="$bad [DROP TABLE in a spaced name => '$out']" ;; esac
  mkrepo; mkdir -p "$ROOT/app"; echo 'db.execute("DROP TABLE users")' > "$ROOT/app/q\"x.py"; _commit "chore: quoted name"; out="$(floor_out)"
  case "$out" in 'full data-loss: app/q"x.py') ;; *) bad="$bad [DROP TABLE in a name with a quote => '$out']" ;; esac
  [ -z "$bad" ] && pass floor-non-ascii || fail floor-non-ascii "$bad"
}

# The ship-gate hook must outlive the floor: a hook timeout fails open.
case_hook_timeout() {
  local f bad=""
  for f in hooks/hooks.json settings.json; do
    python3 - "$KIT_DIR/$f" <<'PY' || bad="$bad [$f]"
import json, sys
d = json.load(open(sys.argv[1]))
found = []
def walk(o):
    if isinstance(o, dict):
        if "ship-gate.sh" in str(o.get("command", "")):
            found.append(o.get("timeout", 0))
        for v in o.values(): walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)
walk(d)
sys.exit(0 if found and all(t >= 30 for t in found) else 1)
PY
  done
  [ -z "$bad" ] && pass hook-timeout || fail hook-timeout "ship-gate timeout under 30s in:$bad"
}

# A submodule bump (gitlink, mode 160000) changes code the diff cannot show: a hard path.
case_floor_submodule() {
  mkrepo
  _git update-index --add --cacheinfo 160000,"$(git -C "$ROOT" rev-parse HEAD)",vendor/sub >/dev/null 2>&1
  _git commit -q -m "chore: bump submodule" >/dev/null 2>&1   # not _commit: add -A would drop a gitlink with no checkout
  local out; out="$(floor_out)"
  case "$out" in "full submodule: vendor/sub") pass floor-submodule ;; *) fail floor-submodule "got '$out'" ;; esac
}

# An override that empties a lane with required gates would waive them all: it is ignored.
case_override_empty_phases() {
  mkrepo; new_log
  commit_kit_toml '[lane.full]
phases = []'
  local got err
  got="$(KIT_PROJECT_ROOT="$ROOT" gl required full 2>/dev/null | tr '\n' ' ')"; err="$(KIT_PROJECT_ROOT="$ROOT" gl required full 2>&1 >/dev/null)"
  if [ "$got" = "think design design-critique spec validate design-record test-plan build review docs ship reflect " ] \
     && printf '%s' "$err" | grep -q 'sets no phases'; then pass override-empty-phases
  else fail override-empty-phases "required full = '$got' err='$err'"; fi
}

# The floor reads the kit root lane data only: an operator overlay that hollows full cannot pass it.
case_ship_operator_hollow_full() {
  ship_fixture migration full
  local op; op="$(_mk)"; printf '[lane.full]\nphases = ["build"]\n' > "$op/kit.toml"
  record_gates build
  HOOK_OPERATOR="$op" run_hook
  [ "$HOOK_RC" = 2 ] && pass ship-operator-hollow-full || fail ship-operator-hollow-full "rc=$HOOK_RC err=$HOOK_ERR"
}

# ---- what counts as a push to the default branch, and which ref is shipped ----
case_ship_push_forms() {
  ship_fixture migration normal; record_gates $NORMAL_GATES
  local bad="" c want other; other="$(_mk)"
  while IFS='|' read -r want c; do
    [ -n "$c" ] || continue
    HOOK_CMD="$c" run_hook
    [ "$HOOK_RC" = "$want" ] || bad="$bad [want $want got $HOOK_RC: $c]"
  done <<CASES
2|gh pr create --base master --fill
2|git push --force-with-lease origin feat/x
0|git push --force origin feat/x
0|git push -f origin feat/x
2|git commit -m "fix main thing" && git push -u origin feat/x
2|git -c user.name=x push -u origin feat/x
0|git push origin feat/x:master
0|git push origin HEAD:refs/heads/main
0|git push origin main
2|git push origin HEAD:refs/heads/feat/x
CASES
  HOOK_CWD="$other" HOOK_CMD="git -C $ROOT push -u origin feat/x" run_hook
  [ "$HOOK_RC" = 2 ] || bad="$bad [git -C <dir> push from elsewhere: rc=$HOOK_RC]"
  [ -z "$bad" ] && pass ship-push-forms || fail ship-push-forms "$bad"
}

# A remote fixture: bare origin, default branch <name>, origin/HEAD set, then the working repo pushed to it.
mkrepo_remote() {   # mkrepo_remote <default-branch>
  mkrepo true "$1"
  local bare; bare="$(_mk)/origin.git"
  git init -q --bare -b "$1" "$bare" >/dev/null 2>&1
  _git remote add origin "$bare" >/dev/null 2>&1
  _git push -q origin "$1" >/dev/null 2>&1
  _git remote set-head origin "$1" >/dev/null 2>&1
}

# The base is origin/HEAD, not a local branch: unpushed commits on local master ride the diff.
case_ship_base_is_origin_head() {
  mkrepo_remote master; new_log
  _git checkout -q master >/dev/null 2>&1
  mkdir -p "$ROOT/auth"; echo x > "$ROOT/auth/b.ts"; _commit "chore: unpushed auth commit on local master"
  _git checkout -q -B feat/x >/dev/null 2>&1
  printf 'Lane: normal\n' > "$ROOT/docs/specs/SPEC-001-x.md"; _commit "chore: spec"
  record_gates $NORMAL_GATES; run_hook
  if [ "$HOOK_RC" = 2 ] && printf '%s' "$HOOK_ERR" | grep -qF 'hard path (auth'; then pass ship-base-is-origin-head
  else fail ship-base-is-origin-head "rc=$HOOK_RC err=$HOOK_ERR"; fi
}

# The ref being pushed is what gets checked, not the clean HEAD the operator happens to sit on.
case_ship_checks_pushed_ref() {
  mkrepo_remote main; new_log
  _git checkout -q -b feat/x >/dev/null 2>&1
  printf 'Lane: normal\n' > "$ROOT/docs/specs/SPEC-001-x.md"; _commit "chore: spec"
  _git checkout -q -b feat/evil main >/dev/null 2>&1
  mkdir -p "$ROOT/auth"; echo x > "$ROOT/auth/c.ts"; _commit "chore: evil"
  _git checkout -q feat/x >/dev/null 2>&1
  record_gates $NORMAL_GATES
  HOOK_CMD="git push origin feat/evil" run_hook
  if [ "$HOOK_RC" = 2 ] && printf '%s' "$HOOK_ERR" | grep -qF "no spec found for 'evil'"; then pass ship-checks-pushed-ref
  else fail ship-checks-pushed-ref "rc=$HOOK_RC err=$HOOK_ERR"; fi
}

# The suggested override command is shell-quoted, so a slug with a metacharacter stays one word.
case_ship_slug_quoted() {
  ship_fixture migration none
  _git checkout -q -b 'feat/a!b' >/dev/null 2>&1
  HOOK_CMD="git push -u origin feat/a!b" run_hook
  if [ "$HOOK_RC" = 2 ] && printf '%s' "$HOOK_ERR" | grep -qF 'override a\!b <phase>'; then pass ship-slug-quoted
  else fail ship-slug-quoted "rc=$HOOK_RC err=$HOOK_ERR"; fi
}

# `risk` answers callers that read "full" as a risk signal: full when the lane is full OR a full
# suggestion fired; otherwise the lane. A cosmetic task stays tiny even with a keyword.
case_risk_verb() {
  local bad="" got t want
  while IFS='|' read -r want t; do
    [ -n "$t" ] || continue
    got="$(lcx risk "$t" 2>/dev/null)"; [ "$got" = "$want" ] || bad="$bad [$t => $got, want $want]"
  done <<'CASES'
full|add jwt authentication
full|add webhook signature check
normal|add a date picker to the settings page
normal|add token count column
tiny|fix a typo in the auth README
bug|the parser crashes on empty input, fix the regression
CASES
  got="$(lcx risk --files "db/migrations/0001_users.sql" "add a users page" 2>/dev/null)"; [ "$got" = full ] || bad="$bad [hard path in --files => $got]"
  [ -z "$bad" ] && pass risk-verb || fail risk-verb "$bad"
}

# Significance keys its "full lane" leg on risk, so a keyword-only task keeps the leg it had.
case_significance_uses_risk() {
  local out; out="$(env KIT_PROJECT_ROOT=/nonexistent bash "$KIT_DIR/lib/classify/significance-classify.sh" explain "add a login rate limiter" 2>/dev/null)"
  printf '%s' "$out" | grep -qF 'significance: high (full lane)' && pass significance-uses-risk || fail significance-uses-risk "$out"
}

# The floor must not leave a RETURN trap behind in a sourcing shell, and a glob character in a
# path must not expand against the caller's directory.
case_floor_no_leaks() {
  mkrepo; addfile 'app/a*b.py' 'x = 1'
  local out; out="$(cd "$ROOT" && env KIT_CONFIG_OPERATOR=/nonexistent bash -c 'source "$1"; floor "$2" main >/dev/null 2>&1; trap -p RETURN' _ "$LC" "$ROOT")"
  if [ -z "$out" ]; then pass floor-no-leaks; else fail floor-no-leaks "RETURN trap left set: $out"; fi
}

# Only the five kit lanes exist: a committed [lane.mega] block must not turn `mega` into a lane
# whose gate check passes (check fails closed on an unknown lane).
case_override_unknown_lane_name() {
  mkrepo; new_log
  commit_kit_toml '[lane.mega]
phases = ["ship"]'
  local rc=0 err
  err="$(KIT_PROJECT_ROOT="$ROOT" gl check mega um-1 2>&1)" || rc=$?
  if [ "$rc" = 1 ] && printf '%s' "$err" | grep -q 'unknown lane'; then pass override-unknown-lane-name
  else fail override-unknown-lane-name "check mega rc=$rc err=$err"; fi
}

# Both config files must parse as real TOML (a backslash in a basic string is an error that a
# tolerant reader can swallow), and the kit's own extra_hard_paths must be a valid ERE.
case_toml_valid() {
  local out
  out="$(python3 - "$KIT_DIR" <<'PY' 2>&1
import re, sys
try:
    import tomllib
except ImportError:
    print("SKIP no tomllib"); sys.exit(0)
d = sys.argv[1]
for f in ("kit.toml", ".kit.toml"):
    try:
        data = tomllib.load(open(f"{d}/{f}", "rb"))
    except Exception as e:
        print(f"{f}: {e}"); sys.exit(1)
    extra = data.get("lanes", {}).get("extra_hard_paths", "")
    if extra:
        try: re.compile(extra)
        except re.error as e: print(f"{f}: extra_hard_paths is not a valid regex: {e}"); sys.exit(1)
PY
)" && pass toml-valid || fail toml-valid "$out"
}

# The hook computes the merge base once, and skips the diff scan when the floor switch is off.
_git_shim() {   # _git_shim <dir> <log>: a git wrapper that logs merge-base and raw-diff calls
  local real; real="$(command -v git)"
  printf '#!/bin/bash\ncase " $* " in *" merge-base "*) echo merge-base >> "%s" ;; *" --raw "*) echo raw >> "%s" ;; esac\nexec "%s" "$@"\n' "$2" "$2" "$real" > "$1/git"
  chmod +x "$1/git"
}
case_ship_merge_base_once() {
  local shim log bad=""; shim="$(_mk)"; log="$shim/calls"; : > "$log"; _git_shim "$shim" "$log"
  ship_fixture migration normal; record_gates $NORMAL_GATES
  PATH="$shim:$PATH" run_hook
  local mb raw; mb="$(grep -c merge-base "$log" || true)"; raw="$(grep -c raw "$log" || true)"
  [ "$HOOK_RC" = 2 ] || bad="$bad [switch on: rc=$HOOK_RC]"
  [ "$mb" = 1 ] || bad="$bad [merge-base ran $mb times, want 1]"
  [ "$raw" -ge 1 ] || bad="$bad [switch on: no diff scan]"
  : > "$log"
  mkrepo false; new_log; printf 'Lane: normal\n' > "$ROOT/docs/specs/SPEC-001-x.md"; mkdir -p "$ROOT/db/migrations"; echo "select 1" > "$ROOT/db/migrations/0001_t.sql"; _commit "chore: change"
  record_gates $NORMAL_GATES; PATH="$shim:$PATH" run_hook
  raw="$(grep -c raw "$log" || true)"
  [ "$HOOK_RC" = 0 ] || bad="$bad [switch off: rc=$HOOK_RC]"
  [ "$raw" = 0 ] || bad="$bad [switch off but the diff scan ran $raw times]"
  [ -z "$bad" ] && pass ship-merge-base-once || fail ship-merge-base-once "$bad"
}

# Layer precedence: project (committed) over operator over kit root, per lane, whole-lane wins.
case_override_operator_precedence() {
  mkrepo; new_log
  local op; op="$(_mk)"; printf '[lane.normal]\nphases = ["spec", "build"]\n' > "$op/kit.toml"
  local via_op via_proj
  via_op="$(GL_OPERATOR="$op" KIT_PROJECT_ROOT=/nonexistent gl required normal 2>/dev/null | tr '\n' ' ')"
  commit_kit_toml '[lane.normal]
phases = ["build"]'
  via_proj="$(GL_OPERATOR="$op" KIT_PROJECT_ROOT="$ROOT" gl required normal 2>/dev/null | tr '\n' ' ')"
  if [ "$via_op" = "spec build " ] && [ "$via_proj" = "build " ]; then pass override-operator-precedence
  else fail override-operator-precedence "operator only='$via_op' operator+project='$via_proj'"; fi
}

# A committed [lanes] default applies; an unknown lane name falls back to normal.
case_default_lane_layers() {
  mkrepo
  commit_kit_toml '[lanes]
default = "bug"'
  local applied; applied="$(KIT_PROJECT_ROOT="$ROOT" lcx classify "add a users page" 2>/dev/null)"
  commit_kit_toml '[lanes]
default = "mega"'
  local fallback; fallback="$(KIT_PROJECT_ROOT="$ROOT" lcx classify "add a users page" 2>/dev/null)"
  if [ "$applied" = bug ] && [ "$fallback" = normal ]; then pass default-lane-layers
  else fail default-lane-layers "committed default bug => '$applied'; invalid default => '$fallback' (want normal)"; fi
}

# start (and start --amend) records each dropped phase once.
case_start_no_duplicate_skips() {
  mkrepo; new_log
  commit_kit_toml '[lane.normal]
phases = ["think", "spec", "validate", "design-record", "test-plan", "build", "ship", "docs"]'
  KIT_PROJECT_ROOT="$ROOT" gl start dup-1 normal normal feature >/dev/null 2>&1
  KIT_PROJECT_ROOT="$ROOT" gl start --amend dup-1 normal normal feature >/dev/null 2>&1
  local n; n="$(gl show dup-1 2>/dev/null | grep -c '| GATE | review | skipped | repo lane override')"
  [ "$n" = 1 ] && pass start-no-duplicate-skips || fail start-no-duplicate-skips "review skipped line appears $n times (want 1)"
}

# Fail-closed ref parsing: every ref the command could push is accounted for, or the push blocks.
case_ship_fail_closed_refs() {
  mkrepo_remote main; new_log
  _git checkout -q -B feat/evil main >/dev/null 2>&1
  mkdir -p "$ROOT/auth"; echo x > "$ROOT/auth/a.ts"; _commit "chore: evil"
  local ev; ev="$(git -C "$ROOT" rev-parse HEAD)"; _git tag v1 >/dev/null 2>&1
  _git checkout -q -B feat/x main >/dev/null 2>&1
  printf 'Lane: normal\n' > "$ROOT/docs/specs/SPEC-001-x.md"; _commit "chore: spec"
  record_gates $NORMAL_GATES
  local bad="" want c
  while IFS='|' read -r want c; do
    [ -n "$c" ] || continue
    HOOK_CMD="$c" run_hook
    [ "$HOOK_RC" = "$want" ] || bad="$bad [want $want got $HOOK_RC: $c :: $(printf '%s' "$HOOK_ERR" | head -1 | cut -c1-90)]"
  done <<CASES
0|git push
0|git push -u origin feat/x
0|git push origin HEAD
0|git log -1 --format="%s about git push" && git push -u origin feat/x
0|git push -u origin feat/x && gh pr create --fill
2|git push origin feat/evil
2|git push origin feat/x feat/evil
2|git push --all origin
2|git push --mirror origin
2|git push --tags origin
2|git push --follow-tags origin
2|git push origin $ev:refs/heads/feat/y
2|git push origin feat/evil~0:feat/y
2|git push origin feat/evil && git push origin feat/x
2|git --git-dir .git push origin feat/x
2|git push origin v1
2|gh pr create --head feat/evil --fill
2|git push origin nothere
2|git push origin \$BRANCH
2|xargs git push origin
CASES
  HOOK_CWD="$(_mk)" HOOK_CMD="git -C $ROOT push -u origin feat/x" run_hook
  [ "$HOOK_RC" = 0 ] || bad="$bad [git -C <dir> push from elsewhere: rc=$HOOK_RC]"
  # the fail-closed rule applies only where the gate does: a repo with the switch off at its default branch
  mkrepo_remote main; new_log
  _git checkout -q main >/dev/null 2>&1
  printf '[gate]\nlane_gates = false\n' > "$ROOT/.kit.toml"; _commit "chore: off"; _git push -q origin main >/dev/null 2>&1
  _git checkout -q -B feat/x >/dev/null 2>&1
  HOOK_CMD="git push --all origin" run_hook
  [ "$HOOK_RC" = 0 ] || bad="$bad [switch off: git push --all blocked, rc=$HOOK_RC]"
  [ -z "$bad" ] && pass ship-fail-closed-refs || fail ship-fail-closed-refs "$bad"
}

# ---------------------------------------------------------------------------
run_case() {
  local fn="case_${1//-/_}"
  if declare -F "$fn" >/dev/null; then "$fn"; else fail "$1" "no such case"; fi
}
# `parity` (byte-identical against the baseline) holds only at the refactor commit; after the
# flip the standing check is parity-after-flip.
ALL="parity-after-flip plan-flip four-false-hits webhook-signature-suggests suggest-records explain-suggest-line classify-files-full escalate-suggest floor-paths floor-rename-counts-both-sides floor-data-loss floor-extra-paths-union floor-invalid-extra-ere override-drop-review override-uncommitted override-typo override-no-light pinned-root malformed-array-fails-closed policy-at-base ship-migration-blocks ship-migration-absent-quiet ship-switch-off-on-base ship-flip-gate-in-pr ship-hollow-full-override ship-data-loss ship-no-spec-blocks ship-suggest-advisory workflow-view floor-timing floor-non-ascii hook-timeout floor-submodule override-empty-phases ship-operator-hollow-full ship-push-forms ship-base-is-origin-head ship-checks-pushed-ref ship-slug-quoted risk-verb significance-uses-risk floor-no-leaks override-unknown-lane-name toml-valid ship-merge-base-once override-operator-precedence default-lane-layers start-no-duplicate-skips ship-fail-closed-refs"
if [ "$#" -eq 0 ]; then set -- $ALL; fi
for c in "$@"; do run_case "$c"; done
[ "$FAILS" -eq 0 ]
