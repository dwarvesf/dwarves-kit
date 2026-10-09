# Implementation notes: shipgate-fixture-hardpath

Delta from `docs/specs/SPEC-400-shipgate-fixture-hardpath.md`. The validate round closed APPROVED with 0 critical and 27 warnings across 7 reviewers. The warnings below are for the builder. They do not change the spec unless a build decision says so here.

## Warnings to resolve during the build (consensus first)

1. `classify --files` reads the exemption at HEAD (TASK-3). Reviewers 1, 2, 3 and 5 flagged it: a PR that commits its own exemption gets lane `normal` from classify, `risk` and significance. Prefer one resolver that takes a rev and read at the merge base for both `_floor_scan` and `_path_kind`. If HEAD stays, add an AC proving the floor still blocks and state that the classify lane is advisory.
2. Over-broad entries pass the empty-match guard (`.`, `.+`, `x|.`). Reviewers 1, 2 and 3. Add a guard: reject an entry that matches a canary path such as `src/auth/login.ts` or `.env`, and validate each `|` alternative.
3. One exemption skips every kind (`secret`, `ci`, `infra`, `migration`), not only `auth`. Reviewers 1, 2, 3 and 5. Either key the exemption by kind or document the all-kinds scope in Edge Cases with the secret risk named.
4. Stderr capture in `ship_rule_floor` (`lib/gate/ship-rules.sh:116-117` drops it and returns before logging on an empty hit). Reviewers 2, 3 and 6. Write the `EXEMPT` log line before the early return, filter by prefix so rejected-ERE lines never log as exempt, add a regression case.
5. TOML escaping: `"\.mjs$"` is an invalid TOML escape. Reviewers 2 and 3. Document `[.]` in TASK-5 and test an entry with a dot.
6. Task wiring (Reviewer 4): TASK-2 and TASK-3 depend on TASK-1, TASK-4 on TASK-2; the Terms and Design text point at TASK-4 where TASK-5 owns docs and the ADR; AC9 and the `--files` path need AC rows.
7. Picture drift (Reviewers 4 and 6): add the `--files` read point and the stderr to `ship-gate.log` arrow.
8. Stale base after an exemption is removed on main (Reviewer 2): state how `<base>` is derived and add a failure-mode row.
9. Hostile ERE complexity (Reviewer 1): low risk because the base file was reviewed; note it.

## Decisions made during the build

- Item 1: one resolver, `lane_hard_path_exempt <root> <rev>` in `lib/gate/lane-data.sh`. The floor passes `<base>`. `classify --files` passes the merge base of the project root (`_deesc_resolve_base`), not HEAD as the spec's TASK-3 said. A PR that commits its own exemption gets `full` from classify. Pinned by `classify-files-exempt` (branch-only exemption gives `full`).
- Item 2: the reader rejects an entry that matches the empty string (tested on one empty line: `printf '' | grep` never matches, so the spec's empty-input idea was vacuous) or any canary path: `src/auth/login.ts`, `lib/session.ts`, `app/auth.py`, `.env`, `config/secrets/prod.txt`, `db/migrations/0001_init.sql`, `.github/workflows/ci.yml`, `Dockerfile`. The canary test runs on the whole ERE, so any `|` alternative that matches a canary rejects the entry. No separate split on `|`: a naive split breaks grouped alternation. `.kit.toml` is not a canary, so the kit-config immunity is tested on its own path.
- Item 3: kept all-kinds scope (except kit-config) and documented it in `docs/WORKFLOW.md`, the `kit.toml` comment and ADR-0039, with the secret and CI risk named. Keying by kind adds syntax for no observed need.
- Item 4: `ship_rule_floor` captures the floor's stderr in a temp file and logs `EXEMPT | floor | <rid> (<kind>: <path>)` before the empty-hit return. Only lines starting `floor: exempt ` log. Pinned by `ship-exempt-logged`, which also checks a rejected entry (`.`) leaves no EXEMPT line.
- Item 5: the `[.]` form is documented in `docs/WORKFLOW.md`, the `kit.toml` comment and the reader's header comment; `floor-exempt-fixture-quiet` runs an entry with `[.]`.
- The exempt-path notice runs one grep per kind over the exempt paths only, so cost stays flat as the exempt directory grows. Exempt lines are blanked, not removed, so the submodule line index stays valid.
- Item 6 to 7: the spec text was not edited after validation; the AC rows added for `--files` and data loss are `classify-files-exempt` and `floor-exempt-data-loss-still-hits`. ADR and docs landed under TASK-5.
- Item 8: `<base>` is the merge base of the pushed head and the remote default branch (`ship_rules_merge_base`). An entry removed on the default branch reaches a branch only after it rebases or merges the default branch. Recorded in ADR-0039 Consequences.
- Item 9: hostile ERE complexity is left untimed; the base file passed a full-lane review. Listed under Not proven in the verification record.
- AC3 landed as two new paths in the existing `floor-paths` hit list (`src/auth/login.ts`, `lib/session.ts`).
- AC6 uses the entry `^[.]kit[.]toml$`, which passes the reader, so the test proves the kit-config immunity, not the reader rejection.
