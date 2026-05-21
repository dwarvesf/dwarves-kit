# Spec: Guardrail hardening (secrets-read guard, commit-format gate, phantom-impl check)

Generated: 2026-05-21
Status: VALIDATED
Source: maintainer request 2026-05-21 ("anything in hooks/skills/agents we can adopt from those repos"). Cross-repo survey of obra/superpowers, gstack, claudekit, Trail of Bits, GSD, SuperClaude, BMAD, agent-os, claude-flow, oh-my-claudecode, ouroboros, doraemonkeys. Of ~90 candidate components, three cleared the PHILOSOPHY bars; all are ADAPT (reimplement in bash), none ADOPT-as-shipped. Bundled here the way SPEC-002 bundled the upstream-audit absorption.
Depends on: the existing `safety-gate.sh` (P1 shares its PreToolUse/Bash style; P2 is a sibling) and `anti-rationalization.sh` (P3 augments it, the same way SPEC-013 added the guess-fix guard). Produces a new ADR-0014 for the read-side secrets guard (a genuinely new safety axis).
Lane: full. Adds a hook and touches two hooks; security surface.

## Problem

The cross-repo survey found the kit's enforcement layer has three real gaps, each backed by a proven external implementation:

1. **No read-side secrets protection.** The kit's entire safety story is *write/exec* destruction (`safety-gate` blocks `rm -rf`, push-to-main, force-push). Nothing stops the agent from *reading* `~/.ssh/id_rsa`, `~/.aws/credentials`, `.env`, keychains, or wallet dirs and surfacing them into a log, a PR, or a tool call. For a kit that runs autonomously and ships to contractors, read-exfiltration of secrets is unguarded. This is the biggest hole. (Sources: Trail of Bits `claude-code-config` deny-list; claudekit `file-guard`.)

2. **No commit-message format enforcement.** `safety-gate` blocks dangerous git ops but never lints the commit *subject*. The maintainer's rules (Conventional Commits, subject <=72 chars, no spec IDs / ticket numbers / phase markers in the subject) are violated constantly by LLM-authored commits, and nothing catches it before the commit lands. (Source: GSD `gsd-validate-commit.sh`.)

3. **No phantom-implementation check.** `anti-rationalization` blocks premature "done" by language smell, and `slop-cleaner` flags bloat, but neither catches the specific failure of code that *claims* completeness while containing `NotImplementedError`, "not implemented" stubs, or `TODO: implement` placeholders in the just-changed diff. This is the kit's own "No phantom features" rule, currently unenforced. (Source: claudekit `self-review.ts` + `check-comment-replacement.ts`.)

These are independent but share one theme (harden the enforcement layer) and ship together as one review pass.

## Solution

### P1: Secrets-read guard (new hook `secrets-guard.sh`)

**Approaches considered**
1. **`settings.json` `permissions.deny` block.** Declarative, native Claude Code. Tradeoff: only the bash-install path ships `settings.json`; the plugin path (hooks.json) cannot set permissions, so the protection would be absent for plugin users. Also does not catch `cat ~/.ssh/id_rsa` via Bash (deny matchers are tool-scoped).
2. **A new bash PreToolUse hook on Read|Edit|Bash (CHOSEN).** Works on BOTH install paths (both register hooks), and covers BOTH surfaces: deny Read/Edit of a secret path, AND deny Bash commands that read secret paths (`cat`/`less`/`head`/`xxd`/`cp` on `~/.ssh` etc.) or pipe `find`/`ls` into a reader (the exfil pattern). Tradeoff: a 13th hook file.
3. **Extend `safety-gate.sh`.** Tradeoff: `safety-gate` is registered for Bash only and is single-purpose (block destructive *writes/commands*); adding Read/Edit matchers + a read-deny concern muddies it. Rejected for separation of concerns.

**Chosen + why:** Approach 2. A dedicated `secrets-guard.sh` is the only option that protects both install paths and both surfaces. Defense-in-depth: the bash-install `settings.json` ALSO gets a `permissions.deny` block (cheap, native) so secret reads are denied even before the hook fires; the hook is the cross-path backstop and the only thing that catches Bash exfil.

**Pattern set** (from Trail of Bits, vetted): `.env`/`.env.*`, `~/.ssh/**`, `~/.aws/**`, `~/.gnupg/**`, `~/.config/gh/**`, `~/.git-credentials`, `~/.docker/config.json`, `~/.kube/config`, `~/.npmrc`, `*.pem`/`*.key`/`*.p12`, login keychains, crypto-wallet dirs (metamask/exodus/phantom). Allow `.env.example`/`.env.sample`/`.env.template`.

### P2: Commit-format gate (new hook `commit-format.sh`)

**Approaches considered**
1. **New PreToolUse(Bash) hook intercepting `git commit -m` (CHOSEN).** Parses the subject, blocks (exit 2) on: not a Conventional Commit type (`feat|fix|docs|refactor|test|chore|build|ci|perf|style|revert`), subject >72 chars, or a spec-ID / ticket / phase marker in the subject (`SPEC-\d+`, `TASK-\d+`, `\bp[0-9]\b`, `phase-\d`). Tradeoff: another hook; serves mainly Ship.
2. **Fold into `safety-gate.sh`.** Tradeoff: mixes "block destruction" with "lint format"; muddies safety-gate's purpose. Rejected.

**Chosen + why:** Approach 1, single-purpose. Skips merge/fixup/squash commits and editor-based commits (no `-m`); only lints `-m`/`-F` subjects.

### P3: Phantom-implementation check (augment `anti-rationalization.sh`)

**Approaches considered**
1. **New Stop hook.** Tradeoff: a 14th hook duplicating anti-rationalization's Stop slot + completion-claim parsing.
2. **Augment `anti-rationalization.sh` (CHOSEN).** On Stop, when a completion claim is present, grep the ADDED lines of `git diff` (uncommitted) for STRONG phantom markers only and block. Reuses the hook that already owns "premature done," exactly as SPEC-013's guess-fix guard did. No new file.

**Chosen + why:** Approach 2. Scoped tightly to avoid false positives: only the diff's added lines (not whole files), only strong markers (`NotImplementedError`, `not implemented`, `TODO: implement`, `throw new Error\(['\"]not implemented`, `unimplemented!`), NOT bare `TODO`/`FIXME` (too common, legitimate). Gate on a "done/complete/ready" claim in the response.

### Extensibility & boundaries
- Each part is an independent unit: `secrets-guard.sh` (new), `commit-format.sh` (new), `anti-rationalization.sh` (edit). They share no state. The secret/format/marker pattern lists are the load-bearing dimensions; each grows by adding a pattern, not by restructuring.
- The merge-only refinements (gstack `careful` extra destructive patterns + build-artifact allowlist into `safety-gate`) are folded in as a small fourth part, not a new file.

### Architecture (diagram if it helps)
```
PreToolUse(Read|Edit|Bash) --> secrets-guard.sh  --> deny read of secret paths + Bash exfil (exit 2)   [P1, new hook]
PreToolUse(Bash)           --> safety-gate.sh     --> + DROP TABLE / git reset --hard / kubectl delete  [P4, merge-in]
                                                       + build-artifact safe-allowlist
PreToolUse(Bash)           --> commit-format.sh   --> block non-conventional / >72 / spec-ID subjects   [P2, new hook]
Stop                       --> anti-rationalization.sh --> + phantom-impl check on the diff (exit 2)     [P3, augment]
```

## Technical Design

### Interfaces (I/O contract)
- **P1 inputs:** PreToolUse JSON (`tool_name`, `tool_input.file_path` for Read/Edit, `tool_input.command` for Bash). **Outputs:** exit 2 + `{"decision":"block","reason":...}` on a secret-path read; exit 0 otherwise. **Invariants:** the path is canonicalized before matching (`realpath -m`, expand `~`/`$HOME`, resolve `..`) so alternate spellings of the same file cannot bypass the denylist (DEC-006); fail-**closed** when a secret pattern matches, fail-**open** + log on unparseable input so a parse error never bricks the session (DEC-007); `.env.example`/sample/template are allowed; never blocks writes (that is safety-gate's job); the block log records the attempted path + tool, never file contents.
- **P2 inputs:** PreToolUse(Bash) `tool_input.command`. **Outputs:** exit 2 + reason on a bad `git commit -m` subject; exit 0 for non-commit commands, merge/fixup, or editor commits. **Invariant:** only the subject (first line) is linted.
- **P3 inputs:** Stop JSON (`assistant_response`, `stop_hook_active`). **Outputs:** exit 2 + reason when a completion claim coincides with a strong phantom marker in the diff's added lines. **Invariant:** scoped to `git diff` added lines + strong markers only; respects `stop_hook_active`.
- All three: bash + jq only, <500ms, no new dependency.

### Data model changes
None. P1 may write a block log to `~/.claude/dwarves-kit/logs/secrets-guard.log` (same pattern as the other logging hooks).

### API / UI / Infrastructure changes
- New: `hooks/secrets-guard.sh`, `hooks/commit-format.sh`; registrations in `settings.json` + `hooks/hooks.json` (PreToolUse matchers); a `permissions.deny` block in `settings.json` (bash-install defense-in-depth).
- Edit: `hooks/anti-rationalization.sh` (phantom-impl check), `hooks/safety-gate.sh` (extra destructive patterns + allowlist).
- Tests: behavior cases in `tests/test-hooks.sh`; structural assertions in `tests/test-meta.sh` (hook count parity bumps from 12 to 14).
- Docs: README/MANUAL/architecture/CHANGELOG/CLAUDE; ADR-0014 (read-side secrets guard).

## Task Breakdown

**P1 (full lane): secrets-read guard** (TASK-1 split per DEC-009)
- [x] **TASK-1: `hooks/secrets-guard.sh` + behavior tests.** New PreToolUse(Read|Edit|Bash) hook. Secret-glob list as a clearly-marked editable array at the top of the script (ToB pattern set). Canonicalize the path first (`realpath -m`, expand `~`/`$HOME`, resolve `..`) before matching (DEC-006); fail-closed on a secret match, fail-open + log on parse error (DEC-007); log path + tool, never contents. Bash-surface check (`cat/less/more/head/tail/xxd/strings/od/cp` + `find|xargs cat` + `< redirect`) is best-effort defense-in-depth (DEC-008). Tests: deny `Read(~/.ssh/id_rsa)`, deny `Read($HOME/.ssh/id_rsa)` and a `..` spelling (normalization), deny `cat .env`, allow `.env.example`, allow normal reads, allow on malformed input.
  - Acceptance: `bash tests/test-hooks.sh` green incl. the normalization-bypass cases; hook <500ms; fail-open verified on malformed JSON.
- [x] **TASK-1b: register secrets-guard + `permissions.deny` + ADR-0014.** Register the hook in `settings.json` + `hooks/hooks.json` (PreToolUse Read|Edit|Bash); add a `permissions.deny` block to `settings.json` (bash-install defense-in-depth, the primary tool-surface protection); update `tests/test-meta.sh` hook-count parity (12 -> 13 here, 14 after TASK-2); write ADR-0014.
  - Acceptance: `bash tests/test-meta.sh` green with updated parity; ADR-0014 exists and cites ToB + claudekit; `permissions.deny` present in `settings.json`.

**P2 (full lane): commit-format gate**
- [x] **TASK-2: `hooks/commit-format.sh` + registration + tests.** New PreToolUse(Bash) hook linting the commit SUBJECT only: extract the first line of the first `-m` (ignore subsequent `-m` body args and `-F`-file bodies so a long body never trips the <=72 check); lint conventional type, <=72, no SPEC-/TASK-/phase markers; skip merge/fixup/squash/editor commits. Behavior tests (block `git commit -m "stuff"`, block `feat: ... SPEC-014 ...`, block a >72 subject, allow `feat(debug): add lane`, allow `git commit -m "feat: x" -m "a very long body line over seventy-two chars..."`, allow `git commit` with no -m).
  - Acceptance: `bash tests/test-hooks.sh` green; hook <500ms; multi-`-m` body + merge/fixup/no-m cases pass through (no false block).

**P3 (full lane): phantom-implementation check**
- [x] **TASK-3: augment `anti-rationalization.sh` + tests.** On Stop with a completion claim, grep `git diff` added lines for strong phantom markers; block with a reason. Behavior tests (block when diff adds `raise NotImplementedError` + "done"; no-block when diff is clean; no-block when no completion claim).
  - Acceptance: `bash tests/test-hooks.sh` green with 3 new cases; no false positive on a bare `TODO`; hook stays <500ms.

**P4 (normal lane): safety-gate merge-ins**
- [x] **TASK-4: extend `safety-gate.sh` + tests.** Add `DROP TABLE`, `git reset --hard`, `kubectl delete` patterns and a build-artifact safe-allowlist (do not flag `rm -rf node_modules/dist/.next/target`); behavior tests.
  - Acceptance: new patterns blocked; allowlisted build-artifact deletes pass; existing safety-gate tests still green.

**P5: docs**
- [x] **TASK-5: README / MANUAL / architecture / CHANGELOG / CLAUDE.** Document the 2 new hooks (hooks 12 -> 14), the secrets log path, the ADR; bump counts consistently; CHANGELOG suite totals match real counts. (`.gitignore` already covers `.claude/` per SPEC-013 DEC-008; no change needed there.)
  - Acceptance: counts consistent across all docs; `bash tests/test-meta.sh && bash tests/test-hooks.sh` green; no em-dash introduced.

## Acceptance Criteria (global)
- [x] `secrets-guard.sh` blocks accidental/naive secret reads (Read/Edit tool surface + best-effort Bash) on both install paths, canonicalizing the path first so alternate spellings cannot bypass; allows `.env.example`; the tool-surface deny + `permissions.deny` is the primary layer, the Bash check is defense-in-depth (determined exfil is out of scope, Known limitation 4)
- [x] `commit-format.sh` blocks non-conventional / >72-char / spec-ID-in-subject commits; passes merge/fixup/editor commits
- [x] `anti-rationalization.sh` blocks a completion claim when the diff's added lines contain a strong phantom marker; no false positive on bare TODO
- [x] `safety-gate.sh` blocks the new destructive patterns and respects the build-artifact allowlist
- [x] All hooks <500ms; `bash tests/test-hooks.sh` and `bash tests/test-meta.sh` both green; hook count 12 -> 14 reflected everywhere
- [x] ADR-0014 records the read-side secrets guard; no em-dash introduced; counts consistent across docs

## Verification
`bash tests/test-hooks.sh && bash tests/test-meta.sh`. Spot-checks: `printf '{"tool_name":"Read","tool_input":{"file_path":"~/.ssh/id_rsa"}}' | bash hooks/secrets-guard.sh; echo $?` returns 2; `printf '{"tool_input":{"command":"git commit -m \"random message\""}}' | bash hooks/commit-format.sh; echo $?` returns 2; the same with `feat(x): y` returns 0.

## Edge Cases
1. **`.env.example` / sample / template** read -> allowed (allowlist), so onboarding docs work.
2. **Secret path inside a legit command** (e.g. `grep KEY .env.example`) -> allowed; only real secret targets blocked.
3. **Commit via editor** (`git commit` with no `-m`) -> commit-format passes through (cannot see the subject pre-write); not a regression.
4. **Merge / revert / fixup commits** -> commit-format skips (their subjects are tool-generated).
5. **Legitimate `TODO` in new code** -> phantom-impl does NOT block (only strong markers like `NotImplementedError`).
6. **Phantom marker but no completion claim** -> phantom-impl does not block (the agent is mid-work, not claiming done).
7. **`rm -rf node_modules`** -> safety-gate allows (build-artifact allowlist); `rm -rf ~/project` -> still blocked.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| secrets-guard false-positive on a non-secret path | a normal read is blocked | tight glob set + `.env.example` allowlist; behavior tests assert normal reads pass |
| secrets-guard bypass via alternate path spelling | `$HOME/.ssh` / `..` / symlink read slips through | canonicalize with `realpath -m` + expand `~`/`$HOME` before matching (DEC-006); tests assert the normalized spellings are blocked |
| secrets-guard errors on malformed input | hook crashes or blocks everything | fail-open + log on parse/realpath error, fail-closed only on a confirmed secret match (DEC-007); tested with malformed JSON |
| secrets-guard missed a Bash exfil form | a `c''at ~/.ssh/...` / `python -c` read slips through | the Bash check is best-effort defense-in-depth (DEC-008); the Read/Edit deny + `permissions.deny` is the primary layer; determined exfil is out of scope (Known limitation 4) |
| commit-format blocks a legitimate non-`-m` commit | editor commit refused | hook only inspects `-m`/`-F` subjects; no-m path is a tested pass-through |
| phantom-impl false-positive (bare TODO) | a clean "done" is blocked | only strong markers, only diff added lines, only with a completion claim; tested |
| hook latency over budget | slow PreToolUse/Stop | each hook is grep/jq over small inputs; `git diff` in P3 is bounded to added lines; `time` spot-check in acceptance |
| permissions.deny absent on plugin path | plugin users unprotected at the tool surface | the hook (registered on both paths) is the cross-path backstop; deny-block is bash-install defense-in-depth only |
| stale hook count in docs | README says 12, suite reports 14 | TASK-5 pins counts + CHANGELOG totals to the real numbers |

## Out of Scope
- **GSD read-injection scanner** (19 prompt-injection regexes + invisible-Unicode): Node-only and advisory; will not survive the <500ms / 30-second-readable bar in bash. Noted as a future idea, not built.
- **confidence-check / pre-build readiness gate** (SuperClaude): overlaps `/think` + `/spec-validate` which already gate entry to building; skipped.
- **`freeze` directory edit-lock** (gstack): useful but situational/opt-in; deferred to a later spec if blast-radius control becomes a real need.
- **enforce-package-manager** (ToB npm->pnpm / pip->uv): clean but narrow (Build/Ship only); deferred.
- **All persona/swarm agents and Node/Python hooks** from the survey: rejected by the bash bar + no-persona/no-swarm boundaries.

## Decision Log
- **DEC-001**: Secrets-read guard is a dedicated bash PreToolUse hook (Read|Edit|Bash), not a `settings.json permissions.deny` block alone. Rationale: the hook works on both install paths and catches Bash exfil; the deny-block only covers the bash-install tool surface. Ship both (hook primary, deny-block as bash-install defense-in-depth).
- **DEC-002**: Commit-format and secrets-guard are new single-purpose hooks, not folded into `safety-gate`. Rationale: `safety-gate`'s purpose is "block destruction"; mixing in read-deny and lint concerns muddies it. (The destructive-pattern *additions* in P4 DO belong in safety-gate, because they are the same concern.)
- **DEC-003**: Phantom-impl check augments `anti-rationalization` (no new file), scoped to diff added lines + strong markers + a completion claim. Rationale: reuses the hook that owns "premature done" (as SPEC-013 did), and the tight scope keeps false positives near zero.
- **DEC-004**: All three are ADAPT (bash reimplementations), never ADOPT-as-shipped. Rationale: every external source is TS/Node/Python or persona/swarm; "synthesize, don't originate" + the bash bar require a kit-native rewrite, citing the source.
- **DEC-005**: P2 (commit-format) is borderline on the 2+ phase rule (serves mainly Ship). Included anyway because it directly enforces the maintainer's documented commit rules that LLMs violate constantly; R4 ruled KEEP (weakest part, but high personal value), with the option to split to its own spec if SPEC-014 needs trimming.
- **DEC-006 (validation, R1+R2)**: secrets-guard canonicalizes the path (`realpath -m`, expand `~`/`$HOME`, resolve `..`) before matching. Without it the denylist is bypassable by alternate spellings of the same file (security theater). Found by Security + Failure-mode reviewers.
- **DEC-007 (validation, R2)**: fail-closed on a confirmed secret match, fail-open + log on unparseable input. A security hook that silently fails-open gives false assurance; one that fails-closed on any error bricks the session. This split keeps both honest.
- **DEC-008 (validation, R1+R3)**: the Bash-surface check is best-effort defense-in-depth, NOT exfil-proof (a reader denylist is bypassable: `c''at`, `< redirect`, `python -c`, var indirection). Primary protection is the Read/Edit tool-surface deny + `permissions.deny`. The value prop is "prevent accidental/naive secret reads," reframed in the AC + Known limitations so the kit ships no false security claim ("no phantom features").
- **DEC-009 (validation, R4)**: TASK-1 split into TASK-1 (hook + tests) and TASK-1b (registration + `permissions.deny` + ADR) for atomicity; the original was >5 files in one task.
- **DEC-010 (code review, C-1)**: the safety-gate build-artifact allowlist rejects any token containing `..` before the artifact match, so `rm -rf node_modules/../..` cannot escape upward. Without it the allowlist was a destructive regression (matched the literal string).
- **DEC-011 (code review, H-1)**: secrets-guard resolves symlinks via `realpath` when the path exists and matches both the lexical and resolved forms, closing the symlink bypass the spec already claimed to cover. Dangling/nonexistent paths fall back to the lexical form (Known limitation 5).
- **DEC-012 (code review, H-2)**: secrets-guard emits its block JSON via `jq -cn --arg` (not raw `printf`), so an attacker/agent-controlled path containing `"` cannot produce invalid JSON that the harness fails to honor. Matches the pattern `commit-format.sh` already used.

## Known limitations
1. **Commit-format only sees `-m`/`-F` subjects.** Editor-based commits bypass it (the subject is written after the hook fires). Acceptable: the LLM almost always uses `-m`.
2. **Phantom-impl enforces marker-absence, not real completeness.** It catches `NotImplementedError`-style stubs, not subtly incomplete logic; that remains the task-verifier's and human's job.
3. **secrets-guard is a denylist, not a labeler.** A secret in a non-standard path it does not know about is not caught; the pattern set is the coverage boundary and grows over time.
4. **The Bash-surface check is not exfil-proof.** It raises the bar against accidental and naive secret reads; a determined bypass (obfuscated reader, `python -c`, base64, indirect tooling) is possible and explicitly out of scope. The honest claim is "prevents accidental/naive reads," with the Read/Edit deny + `permissions.deny` as the stronger tool-surface layer (DEC-008).
5. **Symlink resolution requires the path to exist.** secrets-guard resolves a symlink to its target via `realpath` only when the target exists (DEC-011); a dangling symlink falls back to lexical matching, so a symlink to a not-yet-created secret path is matched only if its lexical name hits a glob.

## Open questions
(none blocking; DEC-005's commit-format phase-fit is the live question for `/spec-validate` R4. A `/goal` loop hitting an uncovered decision appends here, then stops.)

## Source citations
- Survey: this session, 2026-05-21 (two research agents across 11 repos).
- P1: Trail of Bits `claude-code-config/settings.json` deny-list (https://github.com/trailofbits/claude-code-config) + claudekit `cli/hooks/file-guard` (https://github.com/carlrannaberg/claudekit).
- P2: GSD `hooks/gsd-validate-commit.sh` (https://github.com/glittercowboy/get-shit-done).
- P3: claudekit `cli/hooks/self-review.ts` + `check-comment-replacement.ts`.
- P4: gstack `careful` (https://github.com/garrytan/gstack).
- Philosophy bars: `docs/PHILOSOPHY.md` ("Guardrails over guidance", "Bash over binaries", "Synthesize, don't originate", "every file justifies its existence", no vendor-skill sprawl / persona theater / swarm).

## Validation
5 reviewers run 2026-05-21 (security, failure-mode, assumption-destroyer, scope-critic, solution-design), dogfooding `/user:spec-validate`. Verdict: NEEDS REVISION -> 4 critical findings folded in -> VALIDATED. Remaining warnings are acknowledged/owner-accepted.
- Security (R1): the spec IS largely a security feature, so this was central. Two criticals: path-normalization bypass -> canonicalize before matching (DEC-006); false exfil-proof claim -> reframed as best-effort defense-in-depth, primary = tool-surface deny (DEC-008). Plus: log paths not contents (folded into the P1 invariant).
- Failure-mode (R2): fail-open vs fail-closed was undefined -> made explicit (DEC-007); `realpath -m` for nonexistent paths; commit-format must isolate the subject line only -> folded into TASK-2.
- Assumption-destroyer (R3): destroyed "the hook prevents exfiltration" -> the determined-bypass reality is now Known limitation 4 + DEC-008; the value prop is "prevent accidental/naive reads."
- Scope-critic (R4): TASK-1 was too big -> split (DEC-009); ruled DEC-005 KEEP (commit-format is the weakest part but high personal value, splittable later); the 3-concern breadth is an acceptable themed batch (SPEC-002 precedent).
- Solution-design (R5): the hook-not-just-deny-block design holds; secret-glob list to live as an editable array at the top of the hook (folded into TASK-1); a shared Bash-matcher is YAGNI until a third such hook appears.
Status flipped to VALIDATED after the four criticals were folded into Tasks / I-O invariants / Failure modes / Known limitations / Decision Log.

### Code review (post-implementation, fresh-context reviewer)
A fresh-context paranoid review of the built diff (the kit's "verify with a fresh window" thesis) found what self-verification missed. Verdict was FIX-THEN-SHIP; all blockers fixed and re-tested (hooks 92, meta 178 green) before commit:
- **C-1 (CRITICAL, fixed)**: the safety-gate build-artifact allowlist matched the literal string, so `rm -rf node_modules/../..` was ALLOWED (would delete cwd's parent). Fix: reject any token containing `..` before the artifact match (DEC-010). Regression tests added.
- **H-1 (HIGH, fixed)**: `normpath` was lexical only, so a symlink with an innocuous name pointing at a secret bypassed the Read deny. Fix: resolve symlinks via `realpath` when the path exists and match both the lexical and resolved forms (DEC-011). The spec's symlink claim is now true; dangling symlinks fall back to lexical (Known limitation 5).
- **H-2 (HIGH, fixed)**: the block JSON was built with raw `printf`, so a path containing `"` produced invalid JSON (the harness might not honor the block). Fix: emit via `jq -cn --arg` like `commit-format.sh` (DEC-012).
- **M-1 (MEDIUM, fixed)**: the phantom-guard reason advertised `TODO: implement`, which `PHANTOM_RE` does not match (the kit's own "no phantom features" violated by the guard). Fix: reason now lists only the markers actually detected.
- **M-2 (MEDIUM, fixed)**: globs `*.key`, `*_rsa`, `*_ed25519` were over-broad (blocked `messages.key`, `ca-bundle` was a noted edge). Fix: dropped bare `*.key`, tightened to `*/id_rsa` / `*/id_ed25519`; kept `*.pem`/`*.p12`/`*.pfx`. Also dropped the noisy bare `<` from the Bash reader set (L-2).
