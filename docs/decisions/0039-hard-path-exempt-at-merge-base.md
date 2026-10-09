# 0039. Per-kind hard-path exemptions, read at the merge base

Date: 2026-10-09
Status: Accepted (operator decision on the reworked spec)
Relates-to: ADR-0037 (lanes as data and the diff floor), `docs/specs/SPEC-400-shipgate-fixture-hardpath.md`, `docs/WORKFLOW.md`, `SECURITY.md`

## Context

The auth hard path matches any basename that contains `login`, `password`, `passwd` or `jwt`, and any auth-shaped directory. A consumer repo pushed a test oracle, `experiments/qa-runner/cases/oracle/sd-login-locked.mjs`, that checks the login page of a public practice site. The floor demanded every full-lane gate: twelve overrides for a file with no auth code. ADR-0037 let config add hard paths only, so overrides were the one way through.

A first build added one per-repo ERE that skipped every built-in kind except kit config. Review rejected it as a default for an open-source kit:

- One entry also hid `secret`, `ci` and `infra` paths.
- An ERE over-matches easily (`.` is any character, the match is unanchored), and TOML rejects `\.`.
- The entry carried no reason, and the skip showed only in the log.
- The false positive itself lives in the default matcher, so every adopter still hit it with no config.

That key was never released. It is dropped with no migration and no reader.

## Decision

1. **Auth skips test paths by default.** A path with a directory `tests`, `__tests__`, `fixtures` or `cases`, or a basename containing `.test.` or `.spec.`, is not kind `auth`. The list is fixed in code, case-sensitive, and no config extends it. Every other kind still matches test paths.
2. **A repo may add per-kind exemptions** as `[[gate.hard_path_exempt]]` tables in its committed `.kit.toml`. Each table has `paths` (globs), `kinds` and a non-empty `reason`.
3. **Only `auth` and `migration` are exemptable.** `secret`, `ci`, `infra` and `kit-config` never are. The kind check is an allowlist, so a typo or a new kind fails closed. Data-loss lines, submodules and `[lanes] extra_hard_paths` ignore every exemption.
4. **Globs, not EREs.** The kit translates each glob to one anchored ERE in a single pass. `*` and `?` stay inside one path segment, `**` is a whole segment that crosses directories, and a glob with no wildcard matches the whole path only. A glob made only of `*` and `**` is invalid.
5. **Read at the merge base only.** The floor and `classify --files` read `git show <base>:.kit.toml`. The working tree, HEAD, the operator overlay and the kit root never count. With no real merge base, `--files` applies no exemption.
6. **Any invalid entry refuses the whole config.** No entry applies, and every push prints a `WARNING` line per problem. One bad entry means the full-lane review of that `.kit.toml` missed something, so the other entries from the same review are not trusted either. The cost of refusing too much is extra overrides, never a hidden hard path.
7. **Canaries stay.** A glob that matches a built-in canary path (`src/auth/login.ts`, `lib/session.ts`, `.env` and others) is invalid. A repo may add literal paths with `[gate] hard_path_canaries`, read at the same merge base. No config removes a built-in canary. Canaries guard listed paths only: a glob such as `**/*.mjs` passes them, so human review of the `.kit.toml` PR stays the main guard.
8. **Every skip is visible.** A reason is required and prints with each skip. The test-path default is steerable by a PR (name a directory `fixtures/`), so it prints too. Notices are TAB-separated with the path last, so a wildcard-matched path cannot forge an entry number or a reason. Control bytes, non-ASCII bytes and `|` in a printed path fold to `?`.
9. **Notices ride exit-0 hook JSON.** Claude Code drops a hook's stderr on exit 0, so stderr alone reaches neither the operator nor the model. On an allowed push `hooks/ship-gate.sh` prints one JSON object (`systemMessage` plus `additionalContext`), framed as data and cut at 300 characters per notice. On a blocked push the notices stay on stderr. Test-path notices cap at 20 per push; entry notices and refusals never cap.
10. **Mega-goal auto-merge refuses any PR that touches `.kit.toml`.** The guard is `_merge_config_guard` in `lib/goal/mega-merge.sh`, called from `merge()` only. It is a file-level rule because an entry spans several lines: a match on key names misses an edit to only a `paths =` line. It stays out of `_merge_exclusion`, which `mark` re-runs to confirm a hold and so must stay state-only. An unreadable or empty file list refuses as unclassifiable.

```
 .kit.toml at <merge base> --> lane_hard_path_exempt --> records (or none, whole config refused)
                                      |
 push --> hooks/ship-gate.sh --> ship_rule_floor --> lane-classify.sh floor
              |                        |                  auth: skip test paths + auth entries
              |                        |                  migration: skip migration entries
              |                        |                  other kinds, extras, submodules, data-loss: full path list
              |                        v
              |             "[advisory]" / "WARNING" lines, SR_NOTICES, ship-gate.log
              v
   exit 0: one JSON object (systemMessage + additionalContext)     exit 2: notices on stderr

 mega-goal merge --> _merge_config_guard --> refuses when the PR touches .kit.toml
```

## Consequences

This reverses the ADR-0037 rule that config only adds hard paths, limited to `auth` and `migration`. The guard is that creating an exemption edits `.kit.toml`, which is the `kit-config` hard path that no entry can exempt. A human reviews each exemption once in a full-lane PR, and no PR can use its own entry: the PR that adds an entry still blocks on `kit-config`.

What the change costs:

- **A narrower default for every adopter.** Fewer `auth` hits, which flips a battery RUN to SKIP for a diff of login-named tests only, and changes the negative-control answer in `proof-ledger.sh` for such a diff. Real auth code under a test directory (`src/auth/fixtures/keys.ts`) also skips `auth`. A repo that wants strict `auth` on a test directory sets `[lanes] extra_hard_paths`, which adds a hard path and never removes one. `secret` still catches key-, credential- and `.env`-shaped names there, and the review gate still sees the diff.
- **One heavy PR per repo per exemption.** The `.kit.toml` change takes the full lane and a human merge.
- **A stale merge base keeps old entries.** The base comes from local remote-tracking refs. A branch cut from an old default branch reads that commit's exemptions, and revoking an entry reaches a branch only after it moves its merge base. The same holds for `[gate] lane_gates`.
- **Silent `--files` skips.** `classify --files` and `risk --files` print no notice, yet `risk` sizes the `/kit:wrap` auto-merge. The push still shows every skip.
- **Fail-open trust model.** The ship-gate is a quality gate that runs inside the agent harness. Merge paths other than the mega-goal one (`stack-merge.sh`, `wrap-land.sh`, `wrap merge --apply`, a direct `gh pr merge`) are not guarded, and `mega-merge` passes no `--match-head-commit`. Under Codex the adapter drops exit-0 output, so notices reach only `ship-gate.log`. `SECURITY.md` states this.
