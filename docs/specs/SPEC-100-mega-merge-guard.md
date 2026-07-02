# SPEC-100: code-level gate/held-final exclusion in mega-merge

Status: VALIDATED
Date: 2026-07-02
Lane: full (a merge-enforcement guard on lib/mega-merge.sh; security defense-in-depth)
Type: feature
Relates-to: ADR-0028 (auto-merge enforcement), kit-hardening SG-08 (mega-merge), SPEC-097 (durable log)
Board: dwarves-kit ID-083 (TIER-4 security LOW from the kit-hardening close); kit-telemetry mega-goal SG-05

## Problem
`lib/mega-merge.sh` auto-merges an `auto`-tagged sub-goal PR once its gates pass. The rule
"never auto-merge a `gate`-tagged sub-goal PR or the held final PR under `gated-final`" was
enforced ONLY in `commands/mega.md`'s prompt text (the routing that keeps those PRs away
from `merge`). A prompt-rationalizing model that calls `mega-merge.sh merge <held-pr> ...
--execute` directly merges past the exclusion, because the code never checked (ID-083,
TIER-4 security LOW).

## Decision
Add a CODE-LEVEL exclusion in `mega-merge.sh`, checked BEFORE the gate so a held PR is
refused even if its gates pass. It reads PR STATE (never conversation intent):
- `_pr_info <pr>` -> `<isDraft><US><comma-labels><US><title>` via `gh pr view --json`
  (US = ASCII Unit Separator \037, a non-whitespace delimiter so an empty labels field is
  preserved by `read`). Overridable via `MEGA_MERGE_PR_INFO_CMD` for offline tests.
- `_merge_exclusion <pr>`:
  - return 0 + reason -> refuse: the PR is a DRAFT, carries a hold LABEL
    (`do-not-merge`/`gated-final`/`hold`/`blocked`/`wip`/`no-merge`, case-insensitive), or its
    TITLE has a bracketed marker (`[HOLD]`, `[gated-final]`, `[do not merge]`, `[WIP]`, `[final]`).
  - return 1 -> clear (a normal `auto` PR).
  - return 2 -> UNCLASSIFIABLE (state unreadable / gh offline): the caller FAILS CLOSED and
    refuses (never merges on benefit-of-the-doubt).
`merge()` calls it right after posture resolution; a refusal prints the reason, logs it, and
returns nonzero without touching `gh`.

## Acceptance criteria
- AC1 [positive control]: a clear, gate-passing PR still reaches the merge (dry-run prints `gh pr merge`).
- AC2 [NC]: a hold-labelled PR is refused even with a passing gate; the refusal names the label.
- AC3 [NC]: a draft PR is refused.
- AC4 [NC]: a bracketed-title-marker PR is refused.
- AC5 [NC, fail-closed]: unreadable PR state is refused with a reason; no merge command is printed.
- AC6: a hold label among multiple labels still blocks.
- AC7 [gate preserved]: a clear PR with a FAILING gate is still blocked by the gate (exclusion did not bypass it).
- AC8 [no regression]: `test-mega-reconcile.sh` (35), `test-meta.sh` (578), `test-hooks.sh` (438) stay green.

## Tasks
- T1: `lib/mega-merge.sh` -- `_pr_info` + `_merge_exclusion` + wire into `merge()` before the gate; header comment.
- T2: `tests/test-mega-merge.sh` (new) -- AC1-AC7, fully offline (inject gate-ledger + PR-state).
- T3: `tests/test-mega-reconcile.sh` -- inject a CLEAR PR-state stub so its fake-PR merge tests keep testing the gate/posture path (the exclusion would otherwise fail-close on a fake PR).
- T4: `docs/verification/mega-merge-guard.md` -- table-first proof.
- T5: `.github/workflows/test.yml` -- wire the new suite into CI.

## Verification
```
bash tests/test-mega-merge.sh       # AC1-AC7, 12 pins
bash tests/test-mega-reconcile.sh   # stays green (35)
bash tests/test-meta.sh ; bash tests/test-hooks.sh
```

## Out of Scope
- The auto-merge flow itself (shipped, SG-08); merge-mode semantics; the gated-final behavior.
- New merge modes; GitHub branch-protection config.
- The prompt-level routing in commands/mega.md (kept; this is defense-in-depth, not a replacement).

## Decision Log
- DEC-001: check STATE (draft/label/title), never conversation intent -- a prompt-rationalizing
  model cannot argue past a label it did not set.
- DEC-002: fail CLOSED on unreadable state -- an un-classifiable PR is refused, matching the
  "never merge on benefit-of-the-doubt" requirement; a real merge always has gh, so this only
  bites offline / bogus-PR cases (which should not auto-merge anyway).
- DEC-003: exclusion BEFORE the gate -- a held PR is refused regardless of gate status; the
  gate still runs for a clear PR (AC7).
- DEC-004: Unit-Separator delimiter, not tab -- tab is whitespace, so `read` collapses an
  empty labels field and mis-assigns the title; \037 (non-whitespace) preserves empty fields.
