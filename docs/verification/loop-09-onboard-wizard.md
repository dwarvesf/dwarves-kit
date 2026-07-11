# Proof-of-done: SPEC-199 onboard-wizard (harness-loop sub-goal 09)

Spec: `docs/specs/SPEC-199-onboard-wizard.md`. Goal file:
`_meta/megagoals/harness-loop/goals/09-onboard-wizard.md`. Machine, 2026-07-12, branch
`feat/loop-09-onboard-wizard` (based on `origin/feat/loop-08-config-surface`, stacked PR).
Rung 3: the transcripts are backed by a committed re-execution harness
(`tests/proof-loop-09-scenario-b.sh`) that a fresh-context recheck-verifier ran live; its first
run caught a real defect (AC9) that was fixed before this record (see Recheck below).

## Run table

| # | Check | Command | Result |
|---|---|---|---|
| 1 | Detector suite (AC1-9) | `bash tests/test-onboard-detect.sh` | 19/19: four modes classified from fixture `$CLAUDE_DIR`s, explain non-empty, third-party-hook NC not misread, read-only tree-hash proof, install.sh signal drift pin, no-hardcoded-roster pin |
| 2 | Scenario-(b) re-execution harness | `bash tests/proof-loop-09-scenario-b.sh` | 19/19: every transcript claim reproduced live (detect=bash, not-adopted, dry-run previews 5 writes + writes nothing, decline leaves porcelain 0, 12-module registry roster, ONE `adopt --with` seeds `bridge=true`, `prose_rag` honestly not seedable, `PROSE_RAG_INJECT` env-only + inert default) |
| 3 | Transcript (a): fresh plugin-only machine | fixture captures | `docs/proof/loop-09-onboard-wizard/a-fresh-plugin-machine.md` , detect=`plugin`, dry-run preview, baseline accepted, one adopt call, plugin-gap disclosure, five-leg tour |
| 4 | Transcript (b): bash machine + unadopted repo | fixture captures | `docs/proof/loop-09-onboard-wizard/b-bash-unadopted-repo.md` , detect=`bash`, `--with` genuinely seeds a toggled module, registry-only add-on disclosed honestly with registry-generated knob guidance |
| 5 | Transcript (c): already-adopted repo | fixture captures | `docs/proof/loop-09-onboard-wizard/c-already-adopted-repo.md` , adopted branch reports healthy, calls adopt zero times, file-set hash byte-identical before/after |
| 6 | Decline-NC | fixture captures | `docs/proof/loop-09-onboard-wizard/decline-nc.md` , every prompt declined: `git status --porcelain` 0/0 lines, git tree `d1f694d2...` == `d1f694d2...`, file-set sha `650791aa...` == `650791aa...`, byte-identical |
| 7 | Rung-3 recheck (fresh context) | recheck-verifier re-executes #1 + #2 | Round 1: FAIL:fixable , caught AC9 red (the honest-caveat prose hardcoded module names, contradicting the transcript's "never a hardcoded list" claim). Fixed (caveat now derives adopt's seedable set at runtime). Round 2: PASS (both harnesses re-executed fresh, 19/19 + 19/19) |
| 8 | Advisor P5 critique on transcripts | advisor, critique mode | see "Advisor pass" below |
| 9 | Multi-lens review (SPEC-069: lib/ touched) | security + architecture code-reviewer lenses | Security: SHIP (0 critical/major; read-only contract of the detector verified line-by-line + by AC7; 1 pre-existing repo-wide MINOR noted, unguarded mktemp convention). Architecture: see below |
| 10 | Emit-coverage sweep | `bash tests/test-command-emit-sweep.sh` | 19/19 (31 command files, 10 exempt incl. onboard) |
| 11 | Outcome-emit sweep | `bash tests/test-outcome-emit-sweep.sh` | 51/51 |
| 12 | Full suite regression | `bash tests/test-meta.sh` | 685/685 (README/architecture/MANUAL parity holds with the new command) |
| 13 | Full suite regression | `bash tests/test-hooks.sh` | 453/453 |
| 14 | Adjacent regression | `bash tests/test-e2e.sh`; `bash tests/test-install-modules.sh`; `bash tests/test-adopt.sh`; `bash tests/test-config-registry.sh` | 20/20; 37/37; 21 PASS 0 FAIL; 19/19 |

## Fence check (ADR-0034 decision 4)

`install.sh`, `lib/adopt.sh`, `bin/config`, `lib/config/*` are untouched by this branch
(`git diff --stat origin/feat/loop-08-config-surface -- install.sh lib/adopt.sh bin/config
lib/config/` is empty). onboard ORCHESTRATES: the only writer it drives is `lib/adopt.sh`, the
only config reader it drives is `bin/config`, detection is the new read-only
`lib/onboard-detect.sh` (its read-only contract proven by AC7's tree-hash assertion).

## Recheck round (rung 3, the point of it)

The first fresh-context recheck FAILED the run honestly: `tests/test-onboard-detect.sh` AC9
(no-hardcoded-roster) was red because a late edit to `commands/onboard.md` (the "honest caveat"
paragraph) enumerated module names literally, exactly the drift class AC9 exists to catch, and it
contradicted transcript (b)'s "never a hardcoded list" claim. The fix derives adopt's seedable set
at runtime (`grep '^KIT_KNOWN_MODULES=' lib/adopt.sh`) so the caveat self-heals when adopt's set is
widened. The recheck's second round re-executed both harnesses fresh: PASS.

## Advisor pass (P5: misleading copy, fence violations)

Verdict: FINDINGS(1 critical, 1 major, 0 minor), both applied before this record:

- **CRITICAL, dead hook paths on plugin machines.** Evidence chain verified by the advisor against
  `settings.json` (hook commands hardcode `$HOME/.claude/dwarves-kit/hooks/...`), `lib/adopt.sh`
  251-336 (verbatim copy, no path templating), and `install.sh:334` (the plugin compat shim symlinks
  lib/bin but NOT hooks/), so on a plugin-only machine the adopt-wired per-repo module hooks never
  fire, and transcript (a)'s success copy over-claimed ("hooks are wired"). Fix applied within the
  fence (no adopt.sh change): section E gained a fourth disclosure bullet, the plugin-path adopt
  success copy now says the wired entries will not fire yet, transcript (a) re-cut. The
  path-templating fix itself is an adopt.sh follow-up for the lead.
- **MAJOR, false "no must-set knob" claim.** `stats` has four `**no-default-consumer**` source vars
  the wizard's own section-D algorithm would surface; transcript (a) had skipped them with "no
  must-set knob to be useful." Fix applied: section D defines the `no-default-consumer` class
  (optional, skip-safe, presented with export shapes; "nothing you MUST set" instead of "nothing to
  configure"), transcript (a)'s D section re-cut with the real `bin/config list` stats rows.
- Clean on: fence discipline (no reimplementation, every write behind dry-run + confirm), the
  decline invariant, the already-adopted zero-write branch, and the accuracy of the three original
  ADR-0009 disclosure bullets.

## Architecture lens

Verdict: DO-NOT-SHIP on 2 CRITICALs, both resolved; SHIP criteria met after fixes:

- **CRITICAL 1 = the same AC9 red the recheck caught** (reviewed pre-fix); resolved by the
  derive-at-runtime caveat rewrite; suite green 19/19.
- **CRITICAL 2, the leg promise.** State C promised each module's "owning leg" but `bin/config`
  cannot emit it (its parser is fenced to the env<->key registry section; the leg lives in the
  Module-legs table it never reads), verified empirically by the reviewer. Resolved by dropping the
  leg from the wizard's presentation (spec + command re-worded); the alternative (enriching registry
  Doc cells) was rejected as an SG-08 surface edit this sub-goal does not own.
- MEDIUM (adopted-branch read mechanism now pinned to `bin/config list`) and MINOR (help-text sed
  range) also applied.
- Passed: seam choice (single orphan script per adopt.sh/explain.sh precedent), AC8 drift pin real,
  adopt-exactly-once sequencing unambiguous and live-verified, fences hold, doc syncs internally
  consistent, no bloat. Pre-existing stale prose in `docs/architecture.md` ("25 commands + 15
  agents") flagged as adjacent, not caused by this diff (also in the impl notes).

## Security lens

Verdict: SHIP. 0 critical/major. The detector's read-only claim verified line-by-line (no write
syscall anywhere) and independently by AC7's tree-hash proof; no unquoted expansion on
attacker-influenced paths; no injection surface; `commands/onboard.md` never writes outside the
target repo and echoes no secrets. One MINOR: the unguarded `mktemp -d` convention in the two new
test harnesses, which matches the whole suite's pre-existing pattern; noted for a future suite-wide
pass, not a regression of this PR.

## Known adjacent defect (flagged, out of scope)

`lib/adopt.sh`'s `KIT_KNOWN_MODULES` (9 entries) is stale versus `install.sh`'s (12): `worktree`,
`money_gate`, `prose_rag` are missing, so `adopt --with` cannot seed them. The goal forbids
adopt.sh changes, so the wizard discloses the gap honestly (transcript b) instead of fixing it;
harness claim 6 pins the behavior so a future adopt.sh sync will flip that assertion and force the
caveat's removal. Follow-up for the lead: sync adopt.sh's module list (one-line fix + its tests).

## Done= check

Per the goal file: "three transcripts + decline-NC committed + advisor pass recorded + PR open and
HELD for Han." Transcripts #3-#5 + NC #6 committed under `docs/proof/loop-09-onboard-wizard/`;
advisor pass recorded above; the PR is opened GATED (never merged) per the sub-goal's merge policy.
