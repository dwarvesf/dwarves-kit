#!/usr/bin/env bash
# test-wrap-report-lint.sh -- the report-lint cases; split out of tests/test-wrap.sh.
# Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures, chk).
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-pull.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-log.sh lib/wrap/wrap-deploy.sh lib/wrap/wrap-rebase.sh lib/wrap/report-lint.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

# ------------------------------------------------------------- report lint
# The `Needs you` admission test, mechanised. The first case is the REAL defect that
# started this work: a green own PR parked behind "say go and I merge it".
echo
echo "=== report lint ==="
LINT="$KIT_DIR/lib/wrap/report-lint.sh"
# Every fixture carries a `**Built:**` and a `**Seam:**` line because commands/wrap.md makes
# both REQUIRED of any wrap report: step 7b must report which of built / NOTHING / SKIPPED
# happened, and step -1 owes the same three states for the before/after seams. The fixtures
# below exercise the `Needs you` lens, so they satisfy both rules and leave them alone. Each
# rule gets its own cases further down.
_report() { printf '## Wrap: t\n\n%s\n\n**Built:** NOTHING: no candidates\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- %s\n' "$1" "${2:-body}"; }

out="$(_report '🔴 **Needs you:**
a. REVIEW then merge #523. Say go and I merge it.' | bash "$LINT" 2>&1)"; rc=$?
chk "the original defect fails the lint" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the offending item" "$out" "asks permission instead of naming a blocker"

out="$(_report '✅ **Needs you:** NOTHING' 'say go and I merge it' | bash "$LINT" 2>&1)"; rc=$?
chk "NOTHING passes, and What happened is never judged" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '🔴 **Needs you:**
a. UNBLOCK the deploy. It is blocked on a credential only you can read.' | bash "$LINT" 2>&1)"; rc=$?
chk "a real blocker passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '🔴 **Needs you:**
a. RUN gh pr merge 12 --squash.' | bash "$LINT" 2>&1)"; rc=$?
chk "a self-runnable command with no blocker warns, does not fail" "$([ "$rc" -eq 0 ]; echo $?)"
chk_has "the warn names the command class" "$out" "names a command the kit can run"

out="$(_report '🔴 **Needs you:**
a. RUN gh pr merge 12 once security signs off; it is blocked on their approval.' | bash "$LINT" 2>&1)"; rc=$?
chk_no "a stated blocker clears the warn" "$out" "names a command the kit can run"

out="$(printf 'no needs-you section at all\n\n**Built:** SKIPPED: build_candidates knob is false\n\n**Seam:** SKIPPED: no seam\n' | bash "$LINT" 2>&1)"; rc=$?
chk "a report with no Needs you block is clean" "$([ "$rc" -eq 0 ]; echo $?)"

# The Built rule itself. commands/wrap.md: step 7b owes exactly one of built / NOTHING /
# SKIPPED, so a skipped 7b can never read as an empty one. The lint shipped with no test.
out="$(printf 'no needs-you section at all\n\n**Seam:** NOTHING: no seam configured\n' | bash "$LINT" 2>&1)"; rc=$?
chk "a report with no Built line fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names step 7b" "$out" "step 7b (build the candidates) owes an outcome"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's/^\*\*Built:\*\* .*/**Built:**/' | bash "$LINT" 2>&1)"; rc=$?
chk "an empty Built line fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding says it is empty" "$out" "is empty; name what was built"

# The three states must stay distinguishable, and a non-empty line must name the home it
# joins. `SKIPPED: nothing to build` (two states in one) appeared thirteen times in two weeks
# of real reports; `Built: <path> @ <sha>` with no ENHANCE/NEW was every "built" line in the
# same window, and each one was the session's own deliverable, not a 7b candidate.
out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** lib/wrap/report-lint.sh @ abc1234|' | bash "$LINT" 2>&1)"; rc=$?
chk "a Built line that is only a path and a commit fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding asks for the ENHANCE or NEW token" "$out" "no ENHANCE <home> or NEW (precedent: ...) token"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** SKIPPED: nothing to build|' | bash "$LINT" 2>&1)"; rc=$?
chk "SKIPPED: nothing to build fails (an empty scan is NOTHING)" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the two-states-in-one shape" "$out" "an empty scan is 'NOTHING: no candidates', not a skip"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** BUILT wake-probe ENHANCE tools/alert-triage: tests/live/wake-probe after the touch probe (a1b2c3d)|' | bash "$LINT" 2>&1)"; rc=$?
chk "an ENHANCE line naming the home and insertion point passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** REPORTED cron-fire NEW (precedent: nothing matched): tools/cron-fire (reported: needs a spec)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a NEW line carrying the precedent miss passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** SKIPPED: build_candidates knob is false|' | bash "$LINT" 2>&1)"; rc=$?
chk "a real SKIPPED reason passes" "$([ "$rc" -eq 0 ]; echo $?)"

# An operator's kit.toml can set the distill switch off (landing-only), so this report shape
# still occurs: both lines SKIPPED with the switch as the reason, and the lint must take it as
# a real skip.
out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** SKIPPED: distill off|; s|^\*\*Seam:\*\* .*|**Seam:** SKIPPED: distill off|' | bash "$LINT" 2>&1)"; rc=$?
chk "Built and Seam both SKIPPED: distill off passes" "$([ "$rc" -eq 0 ]; echo $?)"

# The lane suffix. commands/wrap.md step 7b routes every candidate through
# lib/classify/lane-classify.sh: a tiny-lane candidate is built here and carries the check
# that proved it, anything heavier is reported with a one-line why. Both shapes append to the
# same line, so the ENHANCE/NEW token must survive the suffix, and the suffix alone must never
# stand in for the token.
out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** BUILT wake-probe ENHANCE tools/alert-triage: tests/live/wake-probe after the touch probe (lane=tiny, verified: bash tests/test-alert.sh, a1b2c3d)|' | bash "$LINT" 2>&1)"; rc=$?
chk "an ENHANCE line carrying lane=tiny and its check passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** REPORTED cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=normal, reported: owes a review, too big for session close)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a NEW line carrying lane=normal and its reported why passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** REPORTED cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=normal, reported: build_candidates off)|' | bash "$LINT" 2>&1)"; rc=$?
chk "the knob-false shape, reported with the knob as the why, passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** lib/wrap/report-lint.sh (lane=tiny, verified: bash tests/test-wrap.sh, abc1234)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a lane suffix with no ENHANCE or NEW still fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding still asks for the ENHANCE or NEW token" "$out" "no ENHANCE <home> or NEW (precedent: ...) token"

# The verdict. Every candidate opens with BUILT, REPORTED, or NOTE; a line without one
# reads as built when it may only have been reported or noted.
out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** wake-probe ENHANCE tools/alert-triage: tests/live/wake-probe after the touch probe (lane=tiny, verified: bash tests/test-alert.sh, a1b2c3d)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a candidate with no leading verdict fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the three verdicts" "$out" "BUILT, REPORTED, or NOTE"

# STAGED and FILED are retired: step 7b never writes a staging block or mints a board row.
out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** STAGED cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=normal, staged + goal drafted: .claude/goals/cron-fire.md)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a STAGED verdict fails, staging is retired" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the retired verdict" "$out" "uses a retired verdict"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** FILED cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=full, filed: ops-toolkit ID-901, goal drafted: .claude/goals/cron-fire.md)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a FILED verdict fails, wrap never mints a board row" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the FILED finding names the retired verdict" "$out" "uses a retired verdict"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** NOTE remerge ENHANCE dwarves-kit bin/wrap merge: PROSE-ONLY: the verb already re-merges under the union driver, nothing was missing, memory note written|' | bash "$LINT" 2>&1)"; rc=$?
chk "a NOTE verdict on a prose-only candidate passes" "$([ "$rc" -eq 0 ]; echo $?)"

# A precedent hit that already does the whole job. Nothing is missing in the tool; the path
# to it is. REPORTED gave step 10 nothing to build, so the session after hand-rolled the same
# curl calls again. The item closes as NOTE with the pointer written in-session.
out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** REPORTED discord-readback ENHANCE tools/discord-pull: its --since, --channel and --embeds flags already read a channel latest embeds, nothing missing (lane=tiny, reported: the existing tool already covers it; this session wrote its own curl calls instead)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a REPORTED item whose tool already covers it fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding says close it as NOTE with the pointer" "$out" "close it as NOTE"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** REPORTED eb-sign ENHANCE _meta/eb-post: --stream signs and posts (lane=tiny, reported: Nothing Missing in the tool)|' | bash "$LINT" 2>&1)"; rc=$?
chk "the covered-reason match is case-insensitive" "$([ "$rc" -eq 1 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** NOTE discord-readback ENHANCE tools/discord-pull: covered, pointer added at skills/discord-post/SKILL.md (lane=tiny, verified: grep -q discord-pull skills/discord-post/SKILL.md, a1b2c3d)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a covered precedent closed as NOTE with its pointer passes" "$([ "$rc" -eq 0 ]; echo $?)"

# The lane closure rule. `wrap.build_lanes` lets an operator list heavier lanes for step 7b to
# build inline, so `lane=normal`, `lane=bug` and `lane=backfill` are legal on a verified item
# and the lint can no longer treat `tiny` as the only buildable lane. What it does enforce is
# the pairing: a lane token says the candidate was sized and nothing about what became of it,
# so every item naming a lane owes `verified:` or `reported:`. The retired closures
# (`staged`, `filed:`, `capture failed:`) no longer close a lane.
out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** BUILT wake-probe ENHANCE tools/alert-triage: tests/live/wake-probe after the touch probe (lane=normal, verified: bash tests/test-alert.sh, #418)|' | bash "$LINT" 2>&1)"; rc=$?
chk "an ENHANCE line carrying lane=normal and its check passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** BUILT cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=bug, verified: bash tests/test-cron.sh, a1b2c3d)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a NEW line carrying lane=bug and its check passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** BUILT cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=backfill, verified: bash tests/test-cron.sh, b2c3d4e)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a NEW line carrying lane=backfill and its check passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** REPORTED cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=full, reported: owes a spec and a review)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a full lane reported with its why passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** REPORTED cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=full, filed: ops-toolkit ID-901)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a retired filed: closure no longer closes a lane" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the retired closure reads as no closure" "$out" "names a lane with no closure"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** REPORTED cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=normal, staged: build_candidates off)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a retired staged closure no longer closes a lane" "$([ "$rc" -eq 1 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** BUILT cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=full, verified: bash tests/test-cron.sh, a1b2c3d)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a full lane closed as built fails, full is never built at session close" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the full-lane rule" "$out" "closes a full-lane candidate as built"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** BUILT cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=tiny, reported: nope)|' | bash "$LINT" 2>&1)"; rc=$?
chk "BUILT closed as reported fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the verdict and closure mismatch" "$out" "pairs its verdict with the wrong closure"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** REPORTED cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=normal, verified: bash tests/test-cron.sh, a1b2c3d)|' | bash "$LINT" 2>&1)"; rc=$?
chk "REPORTED closed as verified fails" "$([ "$rc" -eq 1 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** REPORTED cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=normal, unreported: x)|' | bash "$LINT" 2>&1)"; rc=$?
chk "an unanchored closure token (unreported:) does not close a lane" "$([ "$rc" -eq 1 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** REPORTED cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=normal)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a lane with neither a check nor a reported why fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the missing closure" "$out" "names a lane with no closure"

out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- BUILT alpha ENHANCE tools/x: file.sh (lane=normal, verified: bash tests/test-x.sh, #12)\n- REPORTED beta NEW (precedent: nothing matched): tools/beta (lane=bug)\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "one unclosed lane among good bullets fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the offending bullet by index" "$out" "item 2"

chk_has "commands/wrap.md classifies each candidate's lane" "$(cat "$KIT_DIR/commands/wrap.md")" "lib/classify/lane-classify.sh risk"
chk_has "commands/wrap.md names the worker model tiers" "$(cat "$KIT_DIR/commands/wrap.md")" "Sonnet is the default worker"
chk_has "commands/wrap.md reads the build_lanes knob" "$(cat "$KIT_DIR/commands/wrap.md")" "kit_config_get_root wrap.build_lanes"
chk_has "kit.toml ships build_lanes defaulting to tiny" "$(cat "$KIT_DIR/kit.toml")" 'build_lanes = "tiny"'
chk_no "commands/wrap.md no longer files a candidate with board capture" "$(cat "$KIT_DIR/commands/wrap.md")" "bin/board capture"
chk_no "commands/wrap.md no longer stages a candidate" "$(cat "$KIT_DIR/commands/wrap.md")" "bin/wrap stage \"<title>\""
chk_no "commands/wrap.md dropped the staged-exclusion form" "$(cat "$KIT_DIR/commands/wrap.md")" "build_lanes excludes"
chk_no "kit.toml dropped the staged-exclusion form" "$(cat "$KIT_DIR/kit.toml")" "build_lanes excludes"
# The LIST form: a bare `**Built:**` header followed by `- ` bullets, one candidate per
# line. Added after a real report crammed three candidates onto one unreadable line. Each
# bullet owes the same ENHANCE/NEW token as the inline form, checked per bullet, so one bare
# item among several good ones cannot hide the way it did when the whole line was one string.
out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- REPORTED untracked-blocks-ff-pull NEW (precedent: nothing matched): dwarvesf/dwarves-kit lib/wrap, the pull path in wrap apply (reported: needs a spec)\n- BUILT mini-script-run-loop ENHANCE ops-toolkit tools/mac-mini-substrate/mini-run (no change needed, precedent hit is the helper itself)\n- BUILT sandbox-overlap-probe ENHANCE dwarvesf/foundation-ops fleet/knowledge-guard (already homed as OPS-16)\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "a three-bullet Built list passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- BUILT alpha ENHANCE tools/x: file.sh (abc1234)\n- lib/wrap/report-lint.sh @ def5678\n- REPORTED gamma NEW (precedent: nothing matched): tools/gamma (reported: needs a spec)\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "a list with one bare path-and-commit bullet fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the offending bullet by index" "$out" "bullet 2"
chk_has "the finding quotes the bare bullet" "$out" "lib/wrap/report-lint.sh @ def5678"

out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "a bare Built header with no bullets and no inline content fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding says it is empty" "$out" "is empty"

out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:** NOTHING: no candidates\n- BUILT stray ENHANCE tools/x: file.sh (abc1234)\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "NOTHING inline mixed with bullets fails, the two grammars never combine" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the mixed-grammar shape" "$out" "both inline content and bullets"

out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:** NOTHING: no candidates\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "NOTHING inline alone still passes" "$([ "$rc" -eq 0 ]; echo $?)"

# The prose rule. `bin/precedent` indexes memory notes and research files as hit kinds, so a
# step 7b whose top hit is a note turns a build into a write and still carries the ENHANCE
# token. On 2026-09-10 a procedure run six times by hand, which had already cost a bad
# production deploy, produced two memory notes and one research note and zero mechanism, and
# the report linted clean. The same precedent output named `lib/wrap/wrap.sh` one line below
# the note, and the real fix landed there later: a code home beats a prose home.
out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- BUILT pull-lesson ENHANCE ops-toolkit .claude/memory/ff-pull-trap.md (abc1234)\n- BUILT pull-context ENHANCE ops-toolkit research/2026-09-10-ff-pull.md (def5678)\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "an all-prose Built list fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the prose rule" "$out" "a precedent hit on a note is not a build"
chk_has "the finding says the code home wins" "$out" "the code home wins"

out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- BUILT pull-lesson ENHANCE ops-toolkit .claude/memory/ff-pull-trap.md (abc1234)\n- BUILT pull-context ENHANCE ops-toolkit research/2026-09-10-ff-pull.md (def5678)\n- PROSE-ONLY: the call is one human judgment per run, no mechanism fits it\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "the same all-prose Built passes with a real PROSE-ONLY reason" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- BUILT pull-lesson ENHANCE ops-toolkit .claude/memory/ff-pull-trap.md (abc1234)\n- PROSE-ONLY: none\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "a too-short PROSE-ONLY reason cannot silence the rule" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding still names the prose rule" "$out" "a precedent hit on a note is not a build"

out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- BUILT pull-guard ENHANCE dwarvesf/dwarves-kit lib/wrap/wrap.sh (abc1234)\n- BUILT pull-lesson ENHANCE ops-toolkit .claude/memory/ff-pull-trap.md (def5678)\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "a mixed Built passes, because something was built" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** BUILT pull-lesson ENHANCE ops-toolkit .claude/memory/ff-pull-trap.md (abc1234)|' | bash "$LINT" 2>&1)"; rc=$?
chk "an inline Built naming a single memory note fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the inline finding names the prose rule" "$out" "a precedent hit on a note is not a build"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** BUILT pull-lesson ENHANCE ops-toolkit .claude/memory/ff-pull-trap.md (abc1234) PROSE-ONLY: the pull path already guards itself, only the trap was new|' | bash "$LINT" 2>&1)"; rc=$?
chk "an inline PROSE-ONLY token with a real reason passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** BUILT pull-guard ENHANCE dwarvesf/dwarves-kit lib/wrap/wrap.sh (abc1234)|' | bash "$LINT" 2>&1)"; rc=$?
chk "an inline Built naming a code path still passes" "$([ "$rc" -eq 0 ]; echo $?)"

# The harness-shape check: a `NEW (precedent: nothing matched)` candidate that turns out to
# speak CDP already has a home (browser-harness-js learnings), so it warns instead of passing
# clean, but it never fails the lint (the precedent check itself was still honest).
HARNESS_FIX="$TMPD/harness-fixture"; mkdir -p "$HARNESS_FIX"
printf "await session.Runtime.evaluate({ expression: '1+1' });\n" > "$HARNESS_FIX/probe.js"

out="$(_report '✅ **Needs you:** NOTHING' | sed "s|^\*\*Built:\*\* .*|**Built:** REPORTED site-probe NEW (precedent: nothing matched): ${HARNESS_FIX} (reported: needs a spec)|" | bash "$LINT" 2>&1)"; rc=$?
chk "a NEW item whose files call the CDP harness warns, not fails" "$([ "$rc" -eq 0 ]; echo $?)"
chk_has "the warn names the harness home" "$out" "browser-harness-js skills/cdp/learnings"

out="$(_report '✅ **Needs you:** NOTHING' | sed "s|^\*\*Built:\*\* .*|**Built:** BUILT wake-probe ENHANCE tools/alert-triage: ${HARNESS_FIX} (a1b2c3d)|" | bash "$LINT" 2>&1)"; rc=$?
chk "an ENHANCE item is never checked for harness shape, even over the same CDP content" "$([ "$rc" -eq 0 ]; echo $?)"
chk_no "no harness warn on an ENHANCE line" "$out" "browser-harness-js skills/cdp/learnings"

# The harness-shape check on a LIST-form bullet: the same token match, on a `- ` line.
LIST_HARNESS_FIX="$TMPD/harness-fixture-list"; mkdir -p "$LIST_HARNESS_FIX"
printf "await session.Runtime.evaluate({ expression: '1+1' });\n" > "$LIST_HARNESS_FIX/probe.js"
out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- REPORTED site-probe NEW (precedent: nothing matched): %s (reported: needs a spec)\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' "$LIST_HARNESS_FIX" | bash "$LINT" 2>&1)"; rc=$?
chk "a NEW bullet whose files call the CDP harness warns, not fails" "$([ "$rc" -eq 0 ]; echo $?)"
chk_has "the warn names the harness home for a bullet item" "$out" "browser-harness-js skills/cdp/learnings"

printf 'echo "plain shell content, no CDP calls here"\n' > "$HARNESS_FIX/probe.js"
out="$(_report '✅ **Needs you:** NOTHING' | sed "s|^\*\*Built:\*\* .*|**Built:** REPORTED site-probe NEW (precedent: nothing matched): ${HARNESS_FIX} (reported: needs a spec)|" | bash "$LINT" 2>&1)"; rc=$?
chk "the same NEW path with plain content does not warn" "$([ "$rc" -eq 0 ]; echo $?)"
chk_no "no harness warn printed" "$out" "browser-harness-js skills/cdp/learnings"

# The Seam rule. Same three states as Built, for the same reason one level up: a seam that was
# never configured and a seam that was silently dropped read identically without the line, and
# the seam is where an operator's whole distill half lives.
out="$(printf 'no needs-you section at all\n\n**Built:** NOTHING: no candidates\n' | bash "$LINT" 2>&1)"; rc=$?
chk "a report with no Seam line fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names step -1" "$out" "step -1 (the before/after seams) owes an outcome"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's/^\*\*Seam:\*\* .*/**Seam:**/' | bash "$LINT" 2>&1)"; rc=$?
chk "an empty Seam line fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding says it is empty" "$out" "is empty; name the side and skill that ran"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Seam:\*\* .*|**Seam:** after learning-ledger ran: KEPT 2 of 7 queued|' | bash "$LINT" 2>&1)"; rc=$?
chk "a Seam line naming the side and skill passes" "$([ "$rc" -eq 0 ]; echo $?)"

rc=0; bash "$LINT" /nonexistent-report-file >/dev/null 2>&1 || rc=$?
chk "a missing file exits 2" "$([ "$rc" -eq 2 ]; echo $?)"

# The FYI rule. The block used to mix a skipped step, a state, an incident, and an ask under
# one header, so an operator told to "follow the FYI" read nine ambiguous lines. Each bullet
# now opens with SKIPPED, STATE, or INCIDENT, and an ask belongs in `Needs you` instead.
_fyi() { printf '✅ **Needs you:** NOTHING\n\n**FYI:**\n%s\n\n**Built:** NOTHING: no candidates\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' "$1"; }

out="$(_fyi '- SKIPPED step 7b, its scan output went to the scratch file
- STATE wrap.pull_past_dirty is false, the ops-toolkit checkout stayed behind
- INCIDENT the first merge raced CI, the retry landed it' | bash "$LINT" 2>&1)"; rc=$?
chk "an FYI block whose bullets are all tagged passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_fyi '- the ops-toolkit checkout stayed behind' | bash "$LINT" 2>&1)"; rc=$?
chk "an untagged FYI bullet fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the three tags" "$out" "SKIPPED (a step that did not run), STATE"

out="$(_fyi '- STATE wrap.pull_past_dirty is false, turning the knob on now works cleanly' | bash "$LINT" 2>&1)"; rc=$?
chk "a tagged FYI bullet carrying an ask fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding sends the ask to Needs you" "$out" "that is an ask; move it to Needs you as DECIDE or RUN"

out="$(_fyi '- NOTHING' | bash "$LINT" 2>&1)"; rc=$?
chk "the NOTHING sentinel needs no tag" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | bash "$LINT" 2>&1)"; rc=$?
chk "a report with no FYI block still passes, the block is optional" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(printf '✅ **Needs you:** NOTHING\n\n**FYI:**\n\n**Built:** NOTHING: no candidates\n\n**Seam:** NOTHING: no seam configured\n' | bash "$LINT" 2>&1)"; rc=$?
chk "an FYI header with no bullets is not a finding" "$([ "$rc" -eq 0 ]; echo $?)"

chk_has "commands/wrap.md names the three FYI tags" "$(cat "$KIT_DIR/commands/wrap.md")" "OPENS WITH ITS TAG"
chk_has "commands/wrap.md says FYI carries no ask" "$(cat "$KIT_DIR/commands/wrap.md")" '**`FYI` carries no ask.**'

chk_has "commands/wrap.md wires the lint into step 9" "$(cat "$KIT_DIR/commands/wrap.md")" "lib/wrap/report-lint.sh"
chk_has "the FYI contract keeps follow-ups in the report, no row minted for a home" "$(cat "$KIT_DIR/commands/wrap.md")" "it never mints a board row or a staging block"
chk_no "FYI is not described as never a task" "$(cat "$KIT_DIR/commands/wrap.md")" "never a task"

# The follow-through report (step 10). It is the second report of one pass: no Seam line (the
# seams ran in the first report), and the one place a full-lane item may close as built, only
# when a `REVIEW #<pr>` item in Needs you names its PR, because wrap never merges that PR.
_follow() { printf '## Follow-through: t\n\n%s\n\n**What happened**\n- body\n\n**Built:**\n%s\n' "$1" "$2"; }
FT_OK='- BUILT beta ENHANCE lib/wrap: wrap.sh (lane=normal, verified: bash tests/test-wrap.sh, #41)'
out="$(_follow '✅ **Needs you:** NOTHING' "$FT_OK" | bash "$LINT" 2>&1)"; rc=$?
chk "a follow-through report with no Seam line passes" "$([ "$rc" -eq 0 ]; echo $?)"
out="$(_follow '✅ **Needs you:** NOTHING' "$FT_OK" | sed 's/^## Follow-through: t/## Wrap: t/' | bash "$LINT" 2>&1)"; rc=$?
chk "the same body under a Wrap heading still owes a Seam line" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the Wrap finding names step -1" "$out" "step -1 (the before/after seams) owes an outcome"
out="$(printf '## Follow-through: t\n\n✅ **Needs you:** NOTHING\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "a follow-through report still owes a Built line" "$([ "$rc" -eq 1 ]; echo $?)"
FT_FULL='- BUILT gamma NEW (precedent: nothing matched): lib/gamma (lane=full, verified: bash tests/test-gamma.sh, #71 DRAFT)'
out="$(_follow '🔴 **Needs you:**
a. REVIEW #71: full-lane design for gamma, the operator reviews the spec before it lands.' "$FT_FULL" | bash "$LINT" 2>&1)"; rc=$?
chk "a full-lane build paired with a REVIEW item for its PR passes" "$([ "$rc" -eq 0 ]; echo $?)"
out="$(_follow '✅ **Needs you:** NOTHING' "$FT_FULL" | bash "$LINT" 2>&1)"; rc=$?
chk "a full-lane build with no REVIEW item fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding says wrap never merges a full-lane PR" "$out" "wrap never merges a full-lane PR"
out="$(_follow '🔴 **Needs you:**
a. REVIEW #7: full-lane design for another candidate, blocked on your design call.' "$FT_FULL" | bash "$LINT" 2>&1)"; rc=$?
chk "a REVIEW item naming #7 does not cover PR #71" "$([ "$rc" -eq 1 ]; echo $?)"
out="$(_follow '🔴 **Needs you:**
a. DECIDE #71: full-lane design for gamma, blocked on your design call.' "$FT_FULL" | bash "$LINT" 2>&1)"; rc=$?
chk "only a REVIEW item covers a full-lane build" "$([ "$rc" -eq 1 ]; echo $?)"
out="$(_report '🔴 **Needs you:**
a. REVIEW #71: full-lane design for gamma, blocked on your design call.' | sed "s|^\*\*Built:\*\* .*|**Built:** ${FT_FULL#- }|" | bash "$LINT" 2>&1)"; rc=$?
chk "a full-lane build in a first Wrap report still fails, REVIEW or not" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the Wrap finding says a full lane is never built at session close" "$out" "a full lane is never built at session close"
out="$(_follow '🔴 **Needs you:**
a. REVIEW #71: full-lane design for gamma, blocked on your design call.' "${FT_FULL/ DRAFT/ OPEN}" | bash "$LINT" 2>&1)"; rc=$?
chk "a full-lane build not closed as a DRAFT fails, REVIEW or not" "$([ "$rc" -eq 1 ]; echo $?)"
out="$(_follow '✅ **Needs you:** NOTHING' "$FT_FULL" | sed 's/^- body$/- REVIEW #71: gamma waits for the operator/' | bash "$LINT" 2>&1)"; rc=$?
chk "a REVIEW line outside Needs you does not cover a full-lane build" "$([ "$rc" -eq 1 ]; echo $?)"
out="$(_follow '🔴 **Needs you:**
a. REVIEW #71: full-lane design for gamma. Say go and I merge it.' "$FT_FULL" | bash "$LINT" 2>&1)"; rc=$?
chk "a paired REVIEW item still fails the permission rule" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the permission finding fires on the REVIEW item" "$out" "asks permission instead of naming a blocker"
out="$(printf '[kit:wrap] follow-through: 1 builds, 0 follow-ups, 0 full-lane, running in background\n\n' | cat - <(_follow '✅ **Needs you:** NOTHING' "$FT_OK") | bash "$LINT" 2>&1)"; rc=$?
chk "a preamble line before the Follow-through heading still reads as a follow-through report" "$([ "$rc" -eq 0 ]; echo $?)"
out="$(_report '✅ **Needs you:** NOTHING' | sed '/^\*\*Seam:\*\*/d' | sed 's/^- body$/- the follow-through phase ran; see ## Follow-through: t below/' | bash "$LINT" 2>&1)"; rc=$?
chk "a Wrap report that mentions a follow-through heading later still owes a Seam line" "$([ "$rc" -eq 1 ]; echo $?)"
out="$(_follow '🔴 **Needs you:**
a. RUN the deploy. Want me to dispatch it?' "$FT_OK" | bash "$LINT" 2>&1)"; rc=$?
chk "a follow-through report keeps the permission rule" "$([ "$rc" -eq 1 ]; echo $?)"
out="$(_follow '✅ **Needs you:** NOTHING' "$FT_OK" | sed 's/^- body$/- body\n\n**FYI:**\n- the checkout stayed behind/' | bash "$LINT" 2>&1)"; rc=$?
chk "a follow-through report keeps the FYI tag rule" "$([ "$rc" -eq 1 ]; echo $?)"
FT_DECOY='- BUILT gamma NEW (precedent: nothing matched): lib/gamma (lane=full, verified: bash tests/test-gamma.sh after #99, #71 DRAFT)'
out="$(_follow '🔴 **Needs you:**
a. REVIEW #99: an earlier PR, blocked on your design call.' "$FT_DECOY" | bash "$LINT" 2>&1)"; rc=$?
chk "a decoy PR number in the verified text does not satisfy the pairing" "$([ "$rc" -eq 1 ]; echo $?)"
out="$(_follow '🔴 **Needs you:**
a. REVIEW #71: gamma, blocked on your design call.' "$FT_DECOY" | bash "$LINT" 2>&1)"; rc=$?
chk "only the DRAFT number pairs" "$([ "$rc" -eq 0 ]; echo $?)"
out="$(_follow '🔴 **Needs you:**
a. REVIEW #12: another design, see #71 for context, blocked on your call.' "$FT_FULL" | bash "$LINT" 2>&1)"; rc=$?
chk "a second number later in a REVIEW item does not cover a PR" "$([ "$rc" -eq 1 ]; echo $?)"
out="$(_follow '🔴 **Needs you:**
a. REVIEWED #71: already looked at, blocked on nothing.' "$FT_FULL" | bash "$LINT" 2>&1)"; rc=$?
chk "REVIEWED is not REVIEW" "$([ "$rc" -eq 1 ]; echo $?)"
out="$(_follow '🔴 **Needs you:**
a. REVIEW #71: gamma, blocked on your design call.' "$FT_FULL
- BUILT delta NEW (precedent: nothing matched): lib/delta (lane=full, verified: bash tests/test-delta.sh, #72 DRAFT)" | bash "$LINT" 2>&1)"; rc=$?
chk "two full-lane builds, one unpaired, fail" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the unpaired item" "$out" "item 2 is a full-lane build"
chk "exactly one finding for the unpaired item" "$([ "$(printf '%s\n' "$out" | grep -c 'is a full-lane build')" -eq 1 ]; echo $?)"
out="$(_fyi '- STATE wrap.follow_through is off, 3 in-lane items stay REPORTED; /kit:wrap follow builds them' | bash "$LINT" 2>&1)"; rc=$?
chk "the off-mode FYI row passes the ask rule" "$([ "$rc" -eq 0 ]; echo $?)"

# ------------------------------------------------------------- STE-lite prose
# commands/wrap.md step 9 "Prose is STE-lite": no semicolon, no sentence over 20 words,
# counted outside backtick spans, in Needs you, What happened, the FYI Fact cell, and the
# Left alone Why cell. A contraction only warns.
_ste() { printf '## Wrap: t\n\n✅ **Needs you:** NOTHING\n\n**Left alone:**\n| Repo | Item | Owner | Why |\n|---|---|---|---|\n| r | wt | this pass | %s |\n\n**Built:** NOTHING: no candidates\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- %s\n\n**FYI:**\n| Tag | Fact | Home |\n|---|---|---|\n| STATE | %s | |\n' "${2:-kept for review}" "$1" "${3:-the knob is false}"; }
W20="one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty"

out="$(_ste "Fixed the lint. It now fails a long sentence. Version v1.2.3 shipped in abc1234." | bash "$LINT" 2>&1)"; rc=$?
chk "an STE report passes" "$([ "$rc" -eq 0 ]; echo $?)"
out="$(_ste "$W20" | bash "$LINT" 2>&1)"; rc=$?
chk "a 20-word sentence passes" "$([ "$rc" -eq 0 ]; echo $?)"
out="$(_ste "Fixed the bug; it now passes." | bash "$LINT" 2>&1)"; rc=$?
chk "a semicolon in What happened fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the semicolon finding names the line" "$out" "line 15: semicolon in prose"
out="$(_ste "$W20 twentyone" | bash "$LINT" 2>&1)"; rc=$?
chk "a 21-word sentence fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the long-sentence finding names the count" "$out" "sentence of 21 words"
out="$(_ste 'Ran `a; b` and `one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen` clean.' | bash "$LINT" 2>&1)"; rc=$?
chk "a semicolon and long text inside backticks pass" "$([ "$rc" -eq 0 ]; echo $?)"
out="$(_ste "Fixed. $W20. Done." | bash "$LINT" 2>&1)"; rc=$?
chk "sentences are split on a period and a space" "$([ "$rc" -eq 0 ]; echo $?)"
out="$(_ste "ok" "kept; for review" | bash "$LINT" 2>&1)"; rc=$?
chk "a semicolon in a Left alone Why cell fails" "$([ "$rc" -eq 1 ]; echo $?)"
out="$(_ste "ok" "ok" "$W20 twentyone" | bash "$LINT" 2>&1)"; rc=$?
chk "a 21-word FYI Fact cell fails" "$([ "$rc" -eq 1 ]; echo $?)"
out="$(printf '## Wrap: t\n\n🔴 **Needs you:**\na. RUN the deploy; it needs your 2FA.\n\n**Built:** NOTHING: no candidates\n\n**Seam:** NOTHING: no seam configured\n' | bash "$LINT" 2>&1)"; rc=$?
chk "a semicolon in a Needs you item fails" "$([ "$rc" -eq 1 ]; echo $?)"
out="$(_ste "It doesn't break." | bash "$LINT" 2>&1)"; rc=$?
chk "a contraction warns and still passes" "$([ "$rc" -eq 0 ]; echo $?)"
chk_has "the contraction warning names the line" "$out" "warn line 15: contraction"



echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-report-lint: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-report-lint: all $PASS passed"
