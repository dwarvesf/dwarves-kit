#!/usr/bin/env bash
# test-mega-review.sh -- `mega review --html <slug>` (SPEC-197, harness-loop sub-goal 07).
#
# Pins the composer's load-bearing properties over a fixture mega + a fixture ledger corpus
# (DWARVES_KIT_LOG_DIR sandboxed; no real network, GH_BIN stubbed like tests/test-mega.sh):
#   1. HONEST-EMPTY NC: a mega whose sub-goals carry NO ledger rows renders a page that SAYS SO
#      (a banner) and fabricates ZERO gate-table rows, never a crash.
#   2. A populated sub-goal renders its real GATE rows + summed TOKENS.
#   3. Attention classification: OK collapses by default; CLAIM-UNVERIFIED opens by default.
#   4. Proof-of-done link is best-effort (found when the file exists, "(unlinked...)" honest
#      when it does not -- never a broken/fabricated link).
#   5. The harness-wide footer is honest-dash when a source is unset/absent, and a REAL (not
#      fabricated) 0 when the source resolves but is legitimately empty.
#   6. `--html` is required; a missing slug/flag is a usage error, not a silent no-op.
#   7. COVERAGE-DELTA: TOKENS lines sum across retries (not last-wins); a sub-goal with no
#      **Branch:** line never contaminates another sub-goal's ledger group (rid isolation).
#
# Run: bash tests/test-mega-review.sh   (exit 0 = all AC/NC green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MEGA="$KIT_DIR/lib/mega.sh"

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dk-mega-review-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT

# ---- gh stub: no real network call is ever made (mirrors tests/test-mega.sh's STUBGH) ----------
# Two DIFFERENT `gh pr view` shapes hit this one stub: `lib/mega.sh status`'s own `_pr_state`
# calls `gh pr view <N> --json state -q '.state'` (bare-string output, real gh's `-q` behavior),
# while `lib/mega-review.py`'s `pr_state()` calls `gh pr view <N> --json state,url,mergedAt,
# statusCheckRollup,title` with NO `-q` (full JSON). Detect `-q` in argv and branch, matching
# real `gh`'s own contract instead of picking one shape and breaking the other caller.
STUBGH="$TMP/gh-stub"
cat > "$STUBGH" <<'GHSTUB'
#!/usr/bin/env bash
has_q=0
for a in "$@"; do [ "$a" = "-q" ] && has_q=1; done
case "$1 $2" in
  "pr list") echo "[]" ;;
  "pr view")
    if [ "$has_q" = 1 ]; then
      echo MERGED
    else
      echo '{"state":"MERGED","url":"https://example.invalid/pr/1","mergedAt":"2026-01-01T00:00:00Z","statusCheckRollup":[{"conclusion":"SUCCESS"}],"title":"stub"}'
    fi
    ;;
  *) echo "{}" ;;
esac
GHSTUB
chmod +x "$STUBGH"

# ---- sandboxed ledger root (never touches the real ~/.local/state/dwarves-kit corpus) ----------
export DWARVES_KIT_LOG_DIR="$TMP/kitlogs"
mkdir -p "$DWARVES_KIT_LOG_DIR/runs"

CODEROOT="$TMP/coderoot"
mkdir -p "$CODEROOT/docs/verification"

MROOT="$TMP/megagoals"
MEGADIR="$MROOT/reviewmega"
mkdir -p "$MEGADIR/goals"

cat > "$MEGADIR/ROADMAP.md" <<'EOF'
# Mega-goal: reviewmega
## Sub-goals
- [x] 01-populated has a real ledger with two builds, auto, PR #__
- [x] 02-noledger has a branch but nothing was ever recorded, auto, PR #__
- [ ] 03-nobranch has no goal file at all, auto, PR #__
EOF

printf '# 01-populated\n**Branch:** feat/reviewmega-01-populated\n' > "$MEGADIR/goals/01-populated.md"
printf '# 02-noledger\n**Branch:** feat/reviewmega-02-noledger\n' > "$MEGADIR/goals/02-noledger.md"
# 03-nobranch: deliberately no goals/03-nobranch.md file at all (honest-absence case).

# 01-populated's ledger: two builds (TOKENS must SUM, not last-wins) + a claim-unverified-shaped
# reason string with pipe-adjacent characters (escaping sanity, not a security assertion here --
# render.py's own html.escape is exercised implicitly by every render call in this suite).
cat > "$DWARVES_KIT_LOG_DIR/runs/reviewmega-01-populated.log" <<'EOF'
2026-07-01T00:00:00Z | GATE | build | ran | first attempt
2026-07-01T00:00:00Z | TOKENS | in=100 out=50 cache_read=10 cache_create=5
2026-07-01T00:05:00Z | GATE | build | ran | retry after a flaky test
2026-07-01T00:05:00Z | TOKENS | in=200 out=75 cache_read=0 cache_create=0
2026-07-01T00:06:00Z | GATE | ship | ran | PR #501 opened
EOF

# docs/verification best-effort proof link: only 01-populated's bare-slug file exists.
echo "# proof" > "$CODEROOT/docs/verification/populated.md"

run_review() {  # slug [extra args...]
  local slug="$1"; shift
  GH_BIN="$STUBGH" bash "$MEGA" review "$slug" --html \
    --megagoals-root "$MROOT" --code-root "$CODEROOT" --base master "$@"
}

# =========================== 1. populated + honest gate table ====================================
OUT1="$TMP/out1.html"
run_review reviewmega --out "$OUT1" > "$TMP/run1.out" 2>&1
rc1=$?
[ "$rc1" = 0 ] && [ -f "$OUT1" ] && ok "review exits 0 and writes the requested --out path" \
  || { no "review run failed (rc=$rc1)"; cat "$TMP/run1.out"; }

grep -q '01-populated' "$OUT1" && ok "01-populated group is present" || no "01-populated group missing"
grep -q 'first attempt' "$OUT1" && grep -q 'retry after a flaky test' "$OUT1" \
  && ok "both GATE rows for 01-populated render (not just the last)" || no "GATE rows missing/collapsed"
grep -qE 'tokens: in=300 out=125 cache_read=10 cache_create=5' "$OUT1" \
  && ok "TOKENS lines SUM across retries (100+200=300, 50+75=125), not last-wins" \
  || { no "token sum wrong or missing"; grep -o 'tokens:[^<]*' "$OUT1"; }
grep -q 'docs/verification/populated.md' "$OUT1" \
  && ok "proof-of-done best-effort link found for 01-populated (bare-slug candidate)" \
  || no "proof-of-done link not found for 01-populated"

# =========================== 2. no-ledger sub-goal: honest, not fabricated =======================
grep -q '02-noledger' "$OUT1" && ok "02-noledger group is present" || no "02-noledger group missing"
grep -q '(no ledger rows for this sub-goal)' "$OUT1" \
  && ok "02-noledger renders the honest 'no ledger rows' message" || no "02-noledger did not render honest-empty"
grep -q '(unlinked -- best-effort search found no file' "$OUT1" \
  && ok "02-noledger's proof link is honestly unlinked (no fabricated path)" || no "02-noledger proof link not honestly unlinked"

# =========================== 3. 03-nobranch: no goal file at all, still renders ==================
grep -q '03-nobranch' "$OUT1" && ok "03-nobranch group renders despite no goals/ file" || no "03-nobranch group missing"

# =========================== 4. rid isolation: 01's ledger never leaks into 02's group ============
# Cut the file at 02-noledger's <details> boundary and confirm none of 01's unique reason text
# appears inside 02's own block.
awk '/02-noledger/{flag=1} flag && /<\/details>/{print; exit} flag' "$OUT1" > "$TMP/slice02.html"
grep -q 'first attempt' "$TMP/slice02.html" \
  && no "rid isolation: 01-populated's ledger leaked into 02-noledger's group" \
  || ok "rid isolation: 02-noledger's group carries none of 01-populated's ledger rows"

# =========================== 5. honest-empty NC: a mega with NO ledger rows anywhere =============
MEGADIR2="$MROOT/emptymega"; mkdir -p "$MEGADIR2/goals"
cat > "$MEGADIR2/ROADMAP.md" <<'EOF'
# Mega-goal: emptymega
## Sub-goals
- [ ] 01-fresh nothing has run yet, auto, PR #__
- [ ] 02-fresh2 nothing here either, auto, PR #__
EOF
printf '# 01-fresh\n**Branch:** feat/emptymega-01-fresh\n' > "$MEGADIR2/goals/01-fresh.md"
printf '# 02-fresh2\n**Branch:** feat/emptymega-02-fresh2\n' > "$MEGADIR2/goals/02-fresh2.md"
OUT2="$TMP/out2.html"
run_review emptymega --out "$OUT2" > "$TMP/run2.out" 2>&1
rc2=$?
[ "$rc2" = 0 ] && ok "honest-empty NC: review still exits 0 on a mega with zero ledger rows" || no "honest-empty NC: nonzero exit (rc=$rc2)"
grep -q 'No ledger rows found for ANY sub-goal in this mega yet' "$OUT2" \
  && ok "honest-empty NC: the page states the absence plainly (a banner)" || no "honest-empty NC: no banner"
if grep -q '<tr>' "$OUT2"; then no "honest-empty NC: fabricated <tr> gate rows on a ledger-less mega"; else ok "honest-empty NC: zero <tr> rows anywhere (never fabricated)"; fi

# =========================== 6. attention classification: open vs collapsed ======================
# 01-populated has no PR merged confirmation path here (ship ran, no PR# regex in ROADMAP line
# since the fixture uses the literal "PR #__" placeholder) -- git-truth classifies it PENDING/WIP
# depending on branch resolution; assert the MECHANICAL property instead: an OK-classified group
# never carries the `open` attribute, a non-OK one does. Build a tiny 2-row fixture with a known
# git-truth outcome via a merged PR# so classification is deterministic.
MEGADIR3="$MROOT/attnmega"; mkdir -p "$MEGADIR3/goals"
cat > "$MEGADIR3/ROADMAP.md" <<'EOF'
# Mega-goal: attnmega
## Sub-goals
- [x] 01-shipped merged clean, auto, PR #501 merged deadbee
- [x] 02-lying claims merged but the PR never actually merged, auto, PR #502
EOF
printf '# 01-shipped\n**Branch:** feat/attnmega-01-shipped\n' > "$MEGADIR3/goals/01-shipped.md"
printf '# 02-lying\n**Branch:** feat/attnmega-02-lying\n' > "$MEGADIR3/goals/02-lying.md"
STUBGH2="$TMP/gh-stub2"
cat > "$STUBGH2" <<'GHSTUB2'
#!/usr/bin/env bash
has_q=0
for a in "$@"; do [ "$a" = "-q" ] && has_q=1; done
if [ "$1 $2" = "pr list" ]; then echo "[]"; exit 0; fi
if [ "$1 $2" = "pr view" ]; then
  state="OPEN"; [ "$3" = "501" ] && state="MERGED"
  if [ "$has_q" = 1 ]; then echo "$state"; exit 0; fi
  echo "{\"state\":\"$state\",\"url\":\"https://example.invalid/$3\",\"statusCheckRollup\":[]}"
  exit 0
fi
echo "{}"
GHSTUB2
chmod +x "$STUBGH2"
OUT3="$TMP/out3.html"
GH_BIN="$STUBGH2" bash "$MEGA" review attnmega --html --megagoals-root "$MROOT" --code-root "$CODEROOT" --base master --out "$OUT3" > "$TMP/run3.out" 2>&1
grep -q '<details class="att-ok">' "$OUT3" \
  && ok "attention: an OK sub-goal renders WITHOUT the open attribute (collapsed)" || no "attention: OK group is not collapsed"
grep -q '<details class="att-bad" open>' "$OUT3" \
  && ok "attention: a CLAIM-UNVERIFIED sub-goal renders WITH the open attribute (needs eyes)" || no "attention: bad group is not open"

# =========================== 7. footer: honest-dash vs a real (not fabricated) zero ===============
unset STATS_LEARNED_MD 2>/dev/null || true
run_review reviewmega --out "$TMP/out-footer1.html" > /dev/null 2>&1
grep -q 'staged candidates: -' "$TMP/out-footer1.html" \
  && ok "footer: staged candidates honest-dash when _meta/backlog-staging.md is absent" || no "footer: staged should be honest-dash"
grep -q 'learned-ledger queued: -' "$TMP/out-footer1.html" \
  && ok "footer: learned-ledger honest-dash when STATS_LEARNED_MD is unset" || no "footer: learned-ledger should be honest-dash"
grep -qE 'unpaid debt \(7d window\): 0' "$TMP/out-footer1.html" \
  && ok "footer: unpaid-debt is a REAL 0 (weekend-batch.sh resolved and legitimately found nothing), not honest-dash" \
  || no "footer: unpaid-debt should be a real 0 here (weekend-batch.sh is reachable)"

# Now populate the two consumer files and confirm real counts appear.
mkdir -p "$CODEROOT/_meta"
cat > "$CODEROOT/_meta/backlog-staging.md" <<EOF
## [staged] first candidate
- Intent: do a thing
- Source: session $(date -v-10d +%Y-%m-%d 2>/dev/null || date -d '-10 days' +%Y-%m-%d)

## [staged] second candidate
- Intent: do another thing
- Source: session $(date +%Y-%m-%d)

## [promoted] already handled
- Intent: not staged anymore
- Source: session $(date +%Y-%m-%d)
EOF
export STATS_LEARNED_MD="$TMP/learned-ledger.md"
cat > "$STATS_LEARNED_MD" <<'EOF'
## Ledger
| date | item | kind | home | status |
|---|---|---|---|---|
| 2026-07-01 | concept-a | concept | til | queued |
| 2026-07-05 | insight-b | insight | drop | flushed:abc |
| 2026-06-20 | concept-c | concept | research | queued |
EOF
run_review reviewmega --out "$TMP/out-footer2.html" > /dev/null 2>&1
grep -qE 'staged candidates: 2, oldest 10d' "$TMP/out-footer2.html" \
  && ok "footer: staged candidates counts [staged] blocks only + computes oldest age" \
  || { no "footer: staged count/age wrong"; grep -o 'staged candidates:[^<]*' "$TMP/out-footer2.html"; }
grep -qE 'learned-ledger queued: 2' "$TMP/out-footer2.html" \
  && ok "footer: learned-ledger counts status=queued rows only (2 of 3)" \
  || { no "footer: learned-ledger queued count wrong"; grep -o 'learned-ledger queued:[^<]*' "$TMP/out-footer2.html"; }
unset STATS_LEARNED_MD

# =========================== 8. usage guards ======================================================
if bash "$MEGA" review reviewmega --megagoals-root "$MROOT" --code-root "$CODEROOT" >/dev/null 2>"$TMP/noflag.err"; then
  no "usage: 'review <slug>' without --html should fail"
else
  grep -q -- '--html is required' "$TMP/noflag.err" && ok "usage: missing --html is a clear error" || no "usage: wrong/missing error message for missing --html"
fi
if bash "$MEGA" review --html --megagoals-root "$MROOT" --code-root "$CODEROOT" >/dev/null 2>"$TMP/noslug.err"; then
  no "usage: 'review --html' without a slug should fail"
else
  grep -q 'a <slug> is required' "$TMP/noslug.err" && ok "usage: missing slug is a clear error" || no "usage: wrong/missing error message for missing slug"
fi

# =========================== 9. OUTCOME-only ledger (no GATE rows): honest, not fabricated ======
# Real-corpus finding (SPEC-197 DEC-007): a ledger can carry OUTCOME markers with zero paired
# GATE rows (a pre-OUTCOME-sweep artifact). Must render an honest, DISTINCT message -- never
# silently identical to "no ledger rows at all", and never a fabricated/empty <table>.
MEGADIR4="$MROOT/outcomeonlymega"; mkdir -p "$MEGADIR4/goals"
cat > "$MEGADIR4/ROADMAP.md" <<'EOF'
# Mega-goal: outcomeonlymega
## Sub-goals
- [x] 01-outcomeonly OUTCOME markers with no GATE row, auto, PR #__
EOF
printf '# 01-outcomeonly\n**Branch:** feat/outcomeonlymega-01-outcomeonly\n' > "$MEGADIR4/goals/01-outcomeonly.md"
cat > "$DWARVES_KIT_LOG_DIR/runs/outcomeonlymega-01-outcomeonly.log" <<'EOF'
2026-07-05T12:06:42Z | OUTCOME | build | start | at=1783253202
2026-07-05T12:06:42Z | OUTCOME | build | end | at=1783253202 caught=false dur_s=0
EOF
OUT4="$TMP/out4.html"
run_review outcomeonlymega --out "$OUT4" > "$TMP/run4.out" 2>&1
rc4=$?
[ "$rc4" = 0 ] && ok "OUTCOME-only ledger: review still exits 0" || no "OUTCOME-only ledger: nonzero exit (rc=$rc4)"
grep -q 'no GATE rows recorded for this sub-goal -- OUTCOME markers exist' "$OUT4" \
  && ok "OUTCOME-only ledger: renders the DISTINCT 'OUTCOME markers exist, no GATE row' message" \
  || { no "OUTCOME-only ledger: distinct message missing"; cat "$OUT4"; }
if grep -q '(no ledger rows for this sub-goal)' "$OUT4"; then
  no "OUTCOME-only ledger: wrongly rendered the plain 'no ledger rows' message (OUTCOME data DOES exist)"
else
  ok "OUTCOME-only ledger: did NOT collapse into the plain 'no ledger rows' message"
fi
if grep -q '<table>' "$OUT4"; then no "OUTCOME-only ledger: fabricated a <table> with no real GATE rows"; else ok "OUTCOME-only ledger: no fabricated table"; fi

# ---- summary --------------------------------------------------------------------------------------
echo "----"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
