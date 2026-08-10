# Proof of done: test-meta self-heal + doc-count drift

Profile: feature   Proof class: behavioral

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Pristine `master` runs `bash tests/test-meta.sh` at 809/809 | PASS | R1 |
| 2 | Command counts in README.md / docs/architecture.md match the live `commands/` tree (36), with the missing `gauntlet` row added, not hardcoded | PASS | R1, diff below |
| 3 | `docs/FEATURES.md` regenerated and fresh | PASS | R1 (SPEC-219 pin green) |
| 4 | Running the suite never mutates the working tree it runs in | PASS | R2 (checksums identical pre/post) |
| 5 | Negative control: reintroducing a count drift fails the suite AND does not rewrite any file | PASS | R3 |
| 6 | Existing suites stay green (test-hooks.sh unaffected) | PASS | R4 |

## 2. Root cause

`tests/test-meta.sh`'s SPEC-219 freshness pin calls `lib/registry/feature-registry.sh generate
"$REG_TMP"` (a throwaway temp path) twice, purely to diff the regenerated content against the
committed `docs/FEATURES.md`. But `generate()` unconditionally called `sync_counts()` at the end,
regardless of the `$out` argument -- and `sync_counts()` always patches the REAL `README.md` and
`docs/architecture.md` in place (`docs/verification/port-map-count-sync.md` shows this was a
deliberate feature for the bare, human-invoked `generate` case: run it, it auto-heals the
hand-typed counts). The read-only freshness CHECK inherited that write path as an unintended side
effect: every `bash tests/test-meta.sh` run silently rewrote the two count lines in whatever
checkout it ran in, masking the exact drift it had just flagged RED.

## 3. Implementation

| Aspect | Detail |
|---|---|
| What | Gate `sync_counts()` behind an explicit check: only fires when `generate` is writing the REAL `docs/FEATURES.md` in place, never when writing to a caller-supplied temp path |
| Where | `lib/registry/feature-registry.sh` `generate()` |
| How it runs | `if [ "$out" = "$KIT_DIR/docs/FEATURES.md" ]; then sync_counts; fi` (explicit `if`, not a bare `[ ] && cmd` list -- the latter aborts the whole script under `set -e` when the test is false, since the exemption only covers `if`/`while`/`until` conditions) |
| Content drift fix | Added the missing `/kit:gauntlet` row to README's Commands table, docs/architecture.md's Static-quality-gates inventory table, and README's five-stage table (`gauntlet` module under Check/Govern); then ran `bash lib/registry/feature-registry.sh generate` bare once to let the (now-honest) auto-heal path sync every count number + regenerate `docs/FEATURES.md` |
| Reversibility | `git revert` (no schema/deploy/data surface touched, a doc-generator + two doc files) |

## 4. Confirmation (runs)

| Run | When | Command | Exit | Verdict |
|---|---|---|---|---|
| R1 | 2026-08-10 | `bash tests/test-meta.sh` | 0 | PASS -- 809/809 |
| R2 | 2026-08-10 | `shasum README.md docs/architecture.md docs/FEATURES.md` before and after `bash tests/test-meta.sh` | 0 | PASS -- identical checksums both sides |
| R3 | 2026-08-10 | negative control: add throwaway `commands/zzz-throwaway-negctrl.md`, run suite, checksum, remove | 0 | RED-as-expected -- 9 failures, checksums unchanged |
| R4 | 2026-08-10 | `bash tests/test-hooks.sh` | 0 | PASS -- 492/492, unaffected |

### R1 GREEN

Command: `bash tests/test-meta.sh`
Exit: 0
Output (excerpt):
```
=== Feature-registry freshness pin (SPEC-219) ===
  PASS docs/FEATURES.md is fresh (regenerate == committed, SPEC-219)
  PASS feature-registry generator is deterministic (double run byte-identical, SPEC-219)

=== Results ===
Passed: 809 / 809
All meta tests passed.
```

Diff produced by the fix (the ONLY changes on the branch):
```
-| Check (Govern) | `gate`, `money_gate`, `advisor` |
+| Check (Govern) | `gate`, `money_gate`, `advisor`, `gauntlet` |
-<summary><b>Commands</b> (35, manual, human-triggered)</summary>
+<summary><b>Commands</b> (36, manual, human-triggered)</summary>
+| /kit:gauntlet | Meta | Maintainer-only bounded-revise loop ... |
-  commands/                     (35 markdown command prompts)
+  commands/                     (36 markdown command prompts)
-Total: 35 commands + 28 agents = **63 entries**.
+Total: 36 commands + 28 agents = **64 entries**.
+| `/kit:gauntlet` | command | Contributor-surface convergence | gate | ... |
```
Plus `docs/FEATURES.md` regenerated (adds the `/kit:gauntlet` row) and
`lib/registry/feature-registry.sh` (the `sync_counts` gating fix).

### R2 GREEN -- pure-check proof (no mutation on a normal run)

Command:
```
shasum README.md docs/architecture.md docs/FEATURES.md
bash tests/test-meta.sh
shasum README.md docs/architecture.md docs/FEATURES.md
```
Exit: 0
Output (excerpt):
```
a76fc68270724c3a68c7b24db53e0fbe386d2586  README.md
220b4664440a26b61fdb4c70c79a1076fabeb0ac  docs/architecture.md
6904e224004ec8bcd5b633d3dba3b5b745ab8b8c  docs/FEATURES.md
Passed: 809 / 809
a76fc68270724c3a68c7b24db53e0fbe386d2586  README.md
220b4664440a26b61fdb4c70c79a1076fabeb0ac  docs/architecture.md
6904e224004ec8bcd5b633d3dba3b5b745ab8b8c  docs/FEATURES.md
```
Verdict: PASS -- byte-identical checksums before and after the run; `git status --short` showed
no new diff either.

### R3 NEGATIVE CONTROL

Command:
```
cat > commands/zzz-throwaway-negctrl.md << 'EOF'
---
description: "throwaway command for the report-only negative control"
---
x
EOF
shasum README.md docs/architecture.md docs/FEATURES.md
bash tests/test-meta.sh
shasum README.md docs/architecture.md docs/FEATURES.md
git clean -f commands/zzz-throwaway-negctrl.md
```
Exit: 0 (script), suite exit reflects 9 failures
Output (excerpt):
```
=== Results ===
Passed: 803 / 812
Failed: 9
```
Checksums of README.md / docs/architecture.md / docs/FEATURES.md before and after the failing
run were identical (`a76fc68270724c3a68c7b24db53e0fbe386d2586`,
`220b4664440a26b61fdb4c70c79a1076fabeb0ac`, `6904e224004ec8bcd5b633d3dba3b5b745ab8b8c`).
`git status --short` showed only the throwaway file as untracked; nothing else touched.
Verdict: RED-as-expected -- the drift is reported, not silently healed or hidden.

After removing the throwaway file, `bash tests/test-meta.sh` returned to 809/809 with the same
three checksums, confirming the restore.

### R4 GREEN -- sibling suite unaffected

Command: `bash tests/test-hooks.sh`
Exit: 0
Output (excerpt):
```
=== Results ===
Passed: 492 / 492
All tests passed.
```

## 5. Reproduce

```
bash tests/test-meta.sh   # 809/809, tree unchanged before/after
bash tests/test-hooks.sh  # 492/492
```
