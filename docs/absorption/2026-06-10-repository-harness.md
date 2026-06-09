# Absorption proposal: hoangnb24/repository-harness

Date: 2026-06-10. Proposal-only (per `docs/ABSORPTION.md`). Source read from the README +
`docs/FEATURE_INTAKE.md` + `scripts/install-harness.sh` behavior (WebFetch, 2026-06-10).

## Source in one line

A tool-agnostic "context-engineering" harness: a curl-able installer injects an `AGENTS.md` shim +
a `docs/` scaffold (HARNESS, FEATURE_INTAKE, ARCHITECTURE, TEST_MATRIX, stories/, decisions/,
templates/) + a prebuilt Rust `harness-cli` into any repo. It SHAPES agent work (intent ->
contract -> feature intake -> story packet -> validation -> implementation -> decision capture).
**No enforcement/blocking gates** (confirmed: no hooks/CI-block in the README). The opposite axis
from dwarves-kit, which is enforcing-but-Claude-Code-only.

## Candidates (prioritized)

| # | Candidate | Why | Effort/Risk | Call |
|---|---|---|---|---|
| A1 | CLAUDE.md `@AGENTS.md` import instead of a prose "read AGENTS.md" pointer (their `--claude` shim) | The import actually loads the contract into context; a pointer only hopes the agent reads it | Low/Low | **ABSORBED in this PR** |
| A2 | adopt `--dry-run` (preview) + `--refresh` (re-sync the managed block) (their installer modes) | adopt was merge-only; preview-before-write + re-sync-after-a-kit-update are everyday needs | Low/Low | **ABSORBED in this PR** |
| A3 | Explicit 10-flag risk checklist + count-based decision tree (0-1/2-3/4+ flags, hard gates) for lane classification | Our `lane-classify` is keyword-prose and under-classified the adopt command as `normal` this cycle; a flag-count tree is auditable and would catch kit-machinery changes | Med/Med | **ABSORBED** (PR #26, SPEC-050; flag-scoring + `explain` + kit-machinery hard-gate) |
| A4 | Decision-capture as a routine terminal lane step (their `docs/decisions/` flow) | Make the reflect gate emit a short structured decision file, not just narrative | Med/Low | **ABSORBED (lite)** (PR #27, SPEC-051; advisory `/kit:retro` nudge, NOT a forced emission, the kit already has ADRs + retro + Build-decisions and PHILOSOPHY rejects hard-gating completeness) |
| A5 | `--directory` + `--override` adopt modes | Round out the mode set; `--directory` is covered by our positional arg | Low | DEFER (low value) |
| B1 | Prebuilt Rust `harness-cli` + sha256 + CI version-bump | Compiled binary + release burden for no enforcement gain on our single-platform bash + CC surface | High | **SKIP** |
| B2 | PowerShell installer / Windows | We are macOS + CC only | Med | **SKIP** |
| B3 | Rich in-repo scaffold (stories/, product/, demo/, templates/, HARNESS_BACKLOG.md) | Against our deliberate thin-contract design (engine stays in the install) | High | **SKIP** (maybe steal `templates/` later) |
| C1 | Tool-agnostic enforcement (AGENTS.md shim for any runtime) | Their advisory model is portable for free; ours enforces and is CC-coupled | High | **WATCH** (v3.x multi-runtime) |

## Absorbed here (A1 + A2)

`lib/adopt.sh`: the CLAUDE.md loader now emits `@AGENTS.md` (a real import) inside paired markers
`<!-- kit:adopt -->` / `<!-- /kit:adopt -->`; new `--dry-run` (prints the plan, writes nothing)
and `--refresh` (re-syncs the WORKFLOW pointer + the CLAUDE.md managed block; AGENTS.md + the
proof marker are still never overwritten). Verified: `tests/test-adopt.sh` 8/8 (5 prior + @-import,
dry-run, refresh), meta 392/392.

## The honest framing

We are not converging with the harness; we are the enforcing dual of it. The right absorptions are
the *packaging ergonomics* (A1, A2) and the *classification rigor* (A3), not the philosophy (their
advisory + tool-agnostic + heavy-scaffold model is a different bet from our enforcing + CC-only +
thin-contract one).

## Footer (seed tracking)

repository-harness is a non-Credits external source. If we keep tracking it, add it to
`docs/ABSORPTION.md` `## Seed list`. Source HEAD not pinned (read via README, not a clone).
