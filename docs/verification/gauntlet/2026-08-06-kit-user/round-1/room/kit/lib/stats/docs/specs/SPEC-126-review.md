# Review: SPEC-126 ledger-event schema

Date: 2026-07-04
Diff: `main..feat/lo-01-schema` (8 files, +823/-0, additive only)

### Verdict: SHIP

### Findings

**Security**, no findings. No secrets, tokens, or credential-shaped strings anywhere
in the diff (`grep -rn "op://\|api[_-]key\|AKIA\|ghp_\|sk-"` clean). The tg-cleanup
sample record is verified synthetic (no real title/id from the live JSON files, checked
programmatically before commit). `test-schema-conform.sh` writes only to a `mktemp -d`
scratch dir via `DWARVES_KIT_LOG_DIR` override, it never touches
`~/.local/state/dwarves-kit/logs/` (the live ledger), matching the mega-goal's
read-only-over-ledgers Quality bar even though 01 does no querying.

**Architecture**, no findings. Additive-only diff (no existing file modified or
deleted); consistent with the repo's co-location rule (tool docs/tests under
`tools/ledger-observatory/`, not central `docs/specs/`). The schema doc is honest about
the real shape of the kit's logs (documents Tier B's exceptions, `mega-merge.log`'s
non-verb 2nd field, multi-line trailing fields, rather than rounding to a uniform
grammar that doesn't exist), satisfying the goal's "names it, does not invent it"
quality bar.

**Test coverage**, no findings. `test-schema-conform.sh` covers all 4 required cases
(real conforming line, planned DEBT/TOKENS shapes, malformed-line negative control, 3
outlier samples) plus an extra START-missing-token negative case. 11/11 green,
shellcheck clean on both scripts.

### TODOs (non-blocking, for 02+)

- 02's ETL should reuse this doc's edge-case list (GATE's embedded pipes, DEBT's `=`
  neutering, Tier B's multi-line trailing fields) rather than rediscovering them.
