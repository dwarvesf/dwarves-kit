#!/usr/bin/env bash
# plugin-check smoke test. FULLY HERMETIC: a stub `claude` (tests/fixtures/stub-claude)
# stands in for the real CLI and returns fixture JSON; the suite NEVER shells the real
# `claude plugin ... update`. The stub touches a canary file on any forbidden/unexpected
# verb (above all `plugin update`), and the suite asserts the canary never appears (AC9/AC10).
#
# State files (installed_plugins.json / plugin-catalog-cache.json / known_marketplaces.json)
# are assembled into an ephemeral $CC_PLUGINS_DIR per run; a real micro-git-repo backs the
# ponytail "current" case and the kit directory-source case so the sha compare is real, not
# mocked.
#
# Run: bash tests/smoke.sh   Pass: "smoke: all N passed", exit 0. Fail: prints which, exit 1.
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${DIR}/bin/plugin-check"
FX="${DIR}/tests/fixtures"
STUB="${FX}/stub-claude"

pass=0; fail=0
ok() { echo "  ok: $*"; pass=$((pass+1)); }
no() { echo "  FAIL: $*" >&2; fail=$((fail+1)); }

# --- build an ephemeral plugins dir + stub PATH ------------------------------
WORK="$(mktemp -d "${TMPDIR:-/tmp}/plugin-check-smoke.XXXXXX")"
CANARY="${WORK}/CANARY-real-updater-was-shelled"
STUBBIN="${WORK}/bin"; mkdir -p "$STUBBIN"
# Put the stub on PATH AS `claude` too (defense: the tool defaults CLAUDE_BIN=claude).
cp "$STUB" "$STUBBIN/claude"; chmod +x "$STUBBIN/claude"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# ponytail upstream = a real micro git repo whose HEAD sha we pin into installed_plugins.
PONYTAIL_CLONE="${WORK}/marketplaces/ponytail"
mkdir -p "$PONYTAIL_CLONE"
git -C "$PONYTAIL_CLONE" init -q
git -C "$PONYTAIL_CLONE" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "ponytail head"
PONYTAIL_HEAD="$(git -C "$PONYTAIL_CLONE" rev-parse HEAD)"

# kit = a directory-source marketplace (a real git working tree, deliberately "ahead").
KIT_DIR="${WORK}/dwarves-kit"
mkdir -p "$KIT_DIR"
git -C "$KIT_DIR" init -q
git -C "$KIT_DIR" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "kit head"

OFFICIAL_CLONE="${WORK}/marketplaces/claude-plugins-official"  # not-git on purpose (real one is not git)
mkdir -p "$OFFICIAL_CLONE"

CCDIR="${WORK}/plugins"; mkdir -p "$CCDIR"

# installed_plugins: copy the fixture, but rewrite ponytail's installed sha to the real
# PONYTAIL_HEAD so the clone-HEAD compare yields a provable "current".
jq --arg head "$PONYTAIL_HEAD" '
  .plugins["ponytail@ponytail"][0].gitCommitSha = $head
' "${FX}/installed_plugins.json" > "${CCDIR}/installed_plugins.json"

cp "${FX}/plugin-catalog-cache.json" "${CCDIR}/plugin-catalog-cache.json"

# known_marketplaces: fill the @PLACEHOLDERS@ with the ephemeral clone paths.
sed -e "s|@OFFICIAL_CLONE@|${OFFICIAL_CLONE}|g" \
    -e "s|@PONYTAIL_CLONE@|${PONYTAIL_CLONE}|g" \
    -e "s|@KIT_DIR@|${KIT_DIR}|g" \
    "${FX}/known_marketplaces.template.json" > "${CCDIR}/known_marketplaces.json"

# The environment every plugin-check invocation runs under.
run() {
  CC_PLUGINS_DIR="$CCDIR" \
  CLAUDE_BIN="${STUBBIN}/claude" \
  STUB_ROSTER="${FX}/roster.json" \
  STUB_CANARY="$CANARY" \
  PATH="${STUBBIN}:${PATH}" \
  "$BIN" "$@"
}

echo "[setup] ponytail HEAD=${PONYTAIL_HEAD:0:9}  workdir=$WORK"

# === status (refresh path: stub marketplace update succeeds) =================
STATUS_OUT="$(run status 2>&1)" || true

echo "[1] status: all 6 fixture plugins each appear with a STATUS (AC1)"
n_rows=$(grep -Ec '(current|OUTDATED|unknown)[[:space:]]' <<<"$STATUS_OUT" || true)
if grep -q 'ponytail' <<<"$STATUS_OUT" && grep -q 'superpowers' <<<"$STATUS_OUT" \
   && grep -q 'playwright' <<<"$STATUS_OUT" && grep -q 'swift-lsp' <<<"$STATUS_OUT" \
   && grep -q 'kit' <<<"$STATUS_OUT" && grep -q 'evil' <<<"$STATUS_OUT" \
   && [ "${n_rows:-0}" -ge 6 ]; then ok "6 plugin rows present"; else no "status missing rows ($n_rows):
$STATUS_OUT"; fi

echo "[2] status: a claude-plugins-official plugin resolves to a real STATUS (multi-plugin path, AC1/AC2)"
if grep -Eq 'superpowers[[:space:]]+6.0.3[[:space:]]+[0-9a-f]+[[:space:]]+OUTDATED[[:space:]]+claude-plugins-official' <<<"$STATUS_OUT"; then
  ok "superpowers (official) resolved -> OUTDATED"; else no "official multi-plugin row wrong:
$STATUS_OUT"; fi

echo "[3] status: ponytail (single-plugin mp, clone HEAD == installed sha) shows current (AC2)"
if grep -Eq 'ponytail[[:space:]].*[[:space:]]current[[:space:]]+ponytail' <<<"$STATUS_OUT"; then
  ok "ponytail current (sha proven)"; else no "ponytail not current:
$STATUS_OUT"; fi

echo "[4] status (AC3 negative control): superpowers pinned-old in fixture -> OUTDATED"
# (Single clean assertion. This control genuinely fails if the row regresses to current/unknown.)
if grep -Eq 'superpowers[[:space:]].*OUTDATED' <<<"$STATUS_OUT"; then
  ok "OUTDATED row present for pinned-old superpowers"; else no "AC3 OUTDATED missing:
$STATUS_OUT"; fi

echo "[5] status (AC8): sentinel-version playwright NEVER false-current from string-diff; sha governs"
# playwright installed version is the sentinel 'unknown'; upstream source_sha == installed sha,
# so it is legitimately current VIA SHA (not via comparing the string 'unknown' to '1.0.0').
if grep -Eq 'playwright[[:space:]].*[[:space:]]current[[:space:]]' <<<"$STATUS_OUT" \
   && ! grep -Eq 'playwright[[:space:]]+unknown[[:space:]]+1.0.0' <<<"$STATUS_OUT"; then
  ok "playwright current via sha; sentinel version not string-compared"; else no "AC8 playwright wrong:
$STATUS_OUT"; fi

echo "[6] status (AC8 variant): swift-lsp has NO installed sha -> unknown, never false current"
if grep -Eq 'swift-lsp[[:space:]].*[[:space:]]unknown[[:space:]]' <<<"$STATUS_OUT" \
   && grep -q 'no installed sha' <<<"$STATUS_OUT"; then
  ok "swift-lsp unknown (no installed sha)"; else no "swift-lsp should be unknown:
$STATUS_OUT"; fi

echo "[7] status: kit directory-source labelled dev-tree, no hard verdict (edge case)"
if grep -Eq 'kit[[:space:]].*[[:space:]]unknown[[:space:]]' <<<"$STATUS_OUT" \
   && grep -q 'dev tree, may be ahead' <<<"$STATUS_OUT"; then
  ok "kit unknown + 'local (dev tree, may be ahead)'"; else no "kit dir-source label wrong:
$STATUS_OUT"; fi

echo "[8] status: exit 0 even though some rows are unknown/outdated"
run status >/dev/null 2>&1 && rc=0 || rc=$?
if [ "$rc" -eq 0 ]; then ok "status exit 0"; else no "status exit=$rc"; fi

# === AC4: catalog-refresh failure (offline) -> unknown, never false-current ==
echo "[9] status (AC4): refresh FAILS (offline sim) -> not-provably-current rows degrade to unknown"
OFFLINE_OUT="$(CC_PLUGINS_DIR="$CCDIR" CLAUDE_BIN="${STUBBIN}/claude" STUB_ROSTER="${FX}/roster.json" \
  STUB_CANARY="$CANARY" STUB_REFRESH_FAIL=1 PATH="${STUBBIN}:${PATH}" "$BIN" status 2>&1)" || true
# ponytail matched the (now-unrefreshable) clone, so it must NOT be asserted current; it degrades.
if grep -q 'catalog refresh FAILED' <<<"$OFFLINE_OUT" \
   && grep -Eq 'ponytail[[:space:]].*[[:space:]]unknown[[:space:]]' <<<"$OFFLINE_OUT" \
   && grep -q 'catalog stale' <<<"$OFFLINE_OUT"; then
  ok "offline: ponytail downgraded to unknown (no false current)"; else no "AC4 offline wrong:
$OFFLINE_OUT"; fi

echo "[10] status --no-refresh: catalog treated stale -> ponytail unknown, exit 0 (AC4)"
NR_OUT="$(run status --no-refresh 2>&1)" || true
if grep -q 'catalog NOT refreshed' <<<"$NR_OUT" \
   && grep -Eq 'ponytail[[:space:]].*[[:space:]]unknown[[:space:]]' <<<"$NR_OUT"; then
  ok "--no-refresh degrades ponytail to unknown"; else no "AC4 --no-refresh wrong:
$NR_OUT"; fi

echo "[11] status --no-refresh: still NEVER prints 'current' for a sha-matched row off a stale catalog"
if ! grep -Eq '[[:space:]]current[[:space:]]' <<<"$NR_OUT"; then
  ok "no false 'current' on stale catalog"; else no "false current on stale catalog:
$NR_OUT"; fi

# === update dry-run (AC5/AC7): prints commands, runs NOTHING =================
echo "[12] update <plugin> dry-run prints 'marketplace update -- <mp>' then 'update -- <plugin>@<mp>' (full pluginId, -- guard) + restart note (AC5)"
UP_OUT="$(run update superpowers 2>&1)" || true
if grep -q 'claude plugin marketplace update -- claude-plugins-official' <<<"$UP_OUT" \
   && grep -Eq 'claude plugin update -- superpowers@claude-plugins-official$' <<<"$UP_OUT" \
   && grep -qi 'restart' <<<"$UP_OUT"; then
  ok "dry-run bump commands correct (full pluginId <plugin>@<mp>, -- guard, restart note)"; else no "AC5 dry-run wrong:
$UP_OUT"; fi

echo "[13] update dry-run mutated NOTHING: canary absent (AC5/AC7/AC9)"
if [ ! -e "$CANARY" ]; then ok "no canary after dry-run (real updater never shelled)"; else no "CANARY created by dry-run!"; fi

echo "[14] update dry-run state files unchanged on disk (AC7 read-only on installed state)"
before="$(shasum "${CCDIR}/installed_plugins.json" | awk '{print $1}')"
run update >/dev/null 2>&1 || true
after="$(shasum "${CCDIR}/installed_plugins.json" | awk '{print $1}')"
if [ "$before" = "$after" ]; then ok "installed_plugins.json untouched by update dry-run"; else no "update dry-run mutated state file"; fi

# === AC10: injection-defense ================================================
echo "[15] AC10: injection plugin name created NO side-effect file (/tmp/SHOULD_NOT_EXIST)"
rm -f /tmp/SHOULD_NOT_EXIST
run status >/dev/null 2>&1 || true
run update >/dev/null 2>&1 || true
# also exercise the dry-run that targets the evil row explicitly via the "all outdated" set
if [ ! -e /tmp/SHOULD_NOT_EXIST ]; then ok "injection name ran no side effect"; else no "INJECTION FIRED: /tmp/SHOULD_NOT_EXIST exists"; rm -f /tmp/SHOULD_NOT_EXIST; fi

echo "[16] AC10: injection name appears as a literal plugin row (handled as data, not flag/code)"
if grep -q 'evil' <<<"$STATUS_OUT"; then ok "injection name shown as inert data row"; else no "injection row missing:
$STATUS_OUT"; fi

echo "[17] AC9: across ALL the above runs, the forbidden 'plugin update' verb was never reached (no canary)"
if [ ! -e "$CANARY" ]; then ok "canary absent across full suite (autonomy gate held)"; else no "canary present: real updater WAS shelled"; fi

# === AC6/AC9: --apply on an already-current plugin is a no-op (no real updater shelled) ==
# This is the ONLY --apply path the suite exercises (the autonomy gate, AC9): ponytail is
# provably current (clone HEAD == installed sha), so --apply must short-circuit to "skip:
# already current" BEFORE shelling `plugin update`. If it shelled the updater, the stub
# would canary. We refresh-success here (default stub) so ponytail is genuinely current.
echo "[18] update ponytail --apply on a CURRENT plugin -> no-op 'already current', no canary (AC6/AC9)"
rm -f "$CANARY"
APPLY_OUT="$(run update ponytail --apply 2>&1)" && arc=0 || arc=$?
if grep -qi 'already current' <<<"$APPLY_OUT" && [ ! -e "$CANARY" ] && [ "$arc" -eq 0 ]; then
  ok "--apply no-op on current plugin (real updater never shelled)"; else no "AC6/AC9 no-op wrong (rc=$arc, canary=$([ -e "$CANARY" ] && echo YES || echo no)):
$APPLY_OUT"; fi

# === failure modes ==========================================================
echo "[19] no plugins dir -> 'no plugins installed', exit 0"
EMPTY="${WORK}/empty-home"; mkdir -p "$EMPTY"
OUT="$(CC_PLUGINS_DIR="${EMPTY}/nope" CLAUDE_BIN="${STUBBIN}/claude" STUB_ROSTER="${FX}/roster.json" STUB_CANARY="$CANARY" PATH="${STUBBIN}:${PATH}" "$BIN" status 2>&1)" && rc=0 || rc=$?
if grep -q 'no plugins installed' <<<"$OUT" && [ "$rc" -eq 0 ]; then ok "absent plugins dir handled, exit 0"; else no "absent dir wrong (rc=$rc): $OUT"; fi

echo "[20] torn/invalid roster JSON -> 'state unreadable', exit 0 (not a jq trace)"
BADROSTER="${WORK}/bad-roster.json"; printf '%s' '[{"id":"x@y","ver' > "$BADROSTER"
OUT="$(CC_PLUGINS_DIR="$CCDIR" CLAUDE_BIN="${STUBBIN}/claude" STUB_ROSTER="$BADROSTER" STUB_CANARY="$CANARY" PATH="${STUBBIN}:${PATH}" "$BIN" status 2>&1)" && rc=0 || rc=$?
if grep -q 'state unreadable' <<<"$OUT" && [ "$rc" -eq 0 ] && ! grep -qi 'jq: error' <<<"$OUT"; then
  ok "torn JSON -> clean message, exit 0"; else no "torn-read wrong (rc=$rc): $OUT"; fi

echo "[21] update <not-installed> -> clear error, exit non-zero"
OUT="$(run update definitely-not-installed 2>&1)" && rc=0 || rc=$?
if grep -q 'not installed' <<<"$OUT" && [ "$rc" -ne 0 ]; then ok "unknown plugin rejected (exit $rc)"; else no "unknown-plugin path wrong (rc=$rc): $OUT"; fi

echo "[22] claude CLI absent -> prints intended commands, exit non-zero (never opaque shell error)"
OUT="$(CC_PLUGINS_DIR="$CCDIR" CLAUDE_BIN="/nonexistent/claude-binary" PATH="/usr/bin:/bin" "$BIN" status 2>&1)" && rc=0 || rc=$?
if grep -qi "claude.*not found" <<<"$OUT" && grep -q 'claude plugin marketplace update' <<<"$OUT" && [ "$rc" -ne 0 ]; then
  ok "absent CLI -> intended commands + non-zero exit"; else no "absent-CLI path wrong (rc=$rc): $OUT"; fi

# === AC6: --apply applies + summarizes (stub acts as a controllable updater) ==
# These set STUB_ALLOW_UPDATE so the stub EMULATES the updater (exit 0, or 1 on STUB_FAIL_PLUGIN)
# instead of canarying. It is still the stub, never the real CLI; the autonomy gate (AC9) stays
# proven by the DEFAULT-stub runs above ([13][17][18], canary absent). superpowers is OUTDATED.
echo "[23] update <outdated> --apply success -> 'applied' summary, exit 0, restart reminder (AC6)"
A_OK="$(CC_PLUGINS_DIR="$CCDIR" CLAUDE_BIN="${STUBBIN}/claude" STUB_ROSTER="${FX}/roster.json" \
  STUB_CANARY="$CANARY" STUB_ALLOW_UPDATE=1 PATH="${STUBBIN}:${PATH}" \
  "$BIN" update superpowers --apply 2>&1)" && a_ok_rc=0 || a_ok_rc=$?
if grep -Eq 'applied:.*superpowers' <<<"$A_OK" && grep -qi 'restart' <<<"$A_OK" && [ "$a_ok_rc" -eq 0 ]; then
  ok "--apply success: applied summary + exit 0"; else no "AC6 applied-path wrong (rc=$a_ok_rc):
$A_OK"; fi

echo "[24] update <outdated> --apply failure -> 'failed' summary, exit non-zero (AC6 partial-failure)"
A_BAD="$(CC_PLUGINS_DIR="$CCDIR" CLAUDE_BIN="${STUBBIN}/claude" STUB_ROSTER="${FX}/roster.json" \
  STUB_CANARY="$CANARY" STUB_ALLOW_UPDATE=1 STUB_FAIL_PLUGIN=superpowers PATH="${STUBBIN}:${PATH}" \
  "$BIN" update superpowers --apply 2>&1)" && a_bad_rc=0 || a_bad_rc=$?
if grep -Eq 'failed:.*superpowers' <<<"$A_BAD" && [ "$a_bad_rc" -ne 0 ]; then
  ok "--apply failure: failed summary + exit non-zero"; else no "AC6 failed-path wrong (rc=$a_bad_rc):
$A_BAD"; fi

echo "[25] named update <unknown/dir> --apply is REFUSED, real updater never shelled (verdict gate)"
rm -f "$CANARY"
G_OUT="$(run update kit --apply 2>&1)" && g_rc=0 || g_rc=$?
if grep -qi 'refusing to --apply' <<<"$G_OUT" && [ ! -e "$CANARY" ] && [ "$g_rc" -ne 0 ]; then
  ok "named --apply on a dev-tree/unknown row refused, no canary, exit $g_rc"; else no "named-apply gate wrong (rc=$g_rc, canary=$([ -e "$CANARY" ] && echo YES || echo no)):
$G_OUT"; fi

echo "[26] AC10: dry-run bump command for the hostile 'evil' row is paste-safe (-- guard + shell-quoted)"
EVIL_DRY="$(run update 2>&1)" || true   # 'all outdated' dry-run; evil is OUTDATED so its cmd is emitted
EVIL_CMD_LINES="$(grep -E '^[[:space:]]*claude plugin (update|marketplace update) ' <<<"$EVIL_DRY" || true)"
# the emitted command lines must carry the -- guard and must NOT contain the raw injection payload.
# shellcheck disable=SC2016  # the single-quoted '$(touch' is an intentional literal for grep -F
if grep -qF 'plugin update -- ' <<<"$EVIL_CMD_LINES" \
   && ! grep -qF '; touch /tmp/SHOULD_NOT_EXIST' <<<"$EVIL_CMD_LINES" \
   && ! grep -qF '$(touch' <<<"$EVIL_CMD_LINES"; then
  ok "dry-run bump commands paste-safe (-- guard present, metachars quoted)"; else no "AC10 paste-safety wrong:
$EVIL_CMD_LINES"; fi

echo "[27] update <outdated> --apply on an already-latest plugin -> 'already latest' no-op, NOT 'applied', exit 0"
# the CLI exits 0 with 'already at the latest version' for a version-current plugin whose sha
# differs (the accepted over-report); the tool must classify that as a no-op, not a real apply.
AL_OUT="$(CC_PLUGINS_DIR="$CCDIR" CLAUDE_BIN="${STUBBIN}/claude" STUB_ROSTER="${FX}/roster.json" \
  STUB_CANARY="$CANARY" STUB_ALLOW_UPDATE=1 STUB_ALREADY_LATEST=superpowers PATH="${STUBBIN}:${PATH}" \
  "$BIN" update superpowers --apply 2>&1)" && al_rc=0 || al_rc=$?
if grep -qi 'already latest' <<<"$AL_OUT" && ! grep -Eq 'applied:.*superpowers' <<<"$AL_OUT" && [ "$al_rc" -eq 0 ]; then
  ok "--apply already-latest reported as no-op (not 'applied'), exit 0"; else no "already-latest classification wrong (rc=$al_rc):
$AL_OUT"; fi

echo
if [[ $fail -gt 0 ]]; then echo "smoke: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "smoke: all $pass passed"
