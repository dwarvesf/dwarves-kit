# Security

## Reporting a vulnerability

Report a bypass or a vulnerability through GitHub private vulnerability reporting on `dwarvesf/dwarves-kit` (the Security tab, "Report a vulnerability"). Never open a public issue for it.

## Trust model

The ship-gate is a quality gate, not a security boundary. It runs as a hook inside the agent harness and fails open on any ambiguity: no repo, no spec, no lane, missing tooling, an unreadable config. A bug in the gate must never block unrelated work, so a bypass is possible by design. Specifically:

- **Client-side only.** The gate runs on the operator's machine. `git push --no-verify`, a push from another tool, or a harness with hooks off skips it.
- **Local merge base.** The gate reads project config from the merge base of the pushed head and the remote default branch. It resolves that base from local remote-tracking refs (`origin/HEAD`, `origin/main`, `origin/master`). A local agent can rewrite those refs.
- **Stale base.** A branch cut from an old default branch reads that commit's config. Revoking an exemption reaches a branch only after it moves its merge base. The same holds for `[gate] lane_gates`.
- **Unguarded merge paths.** Only the mega-goal auto-merge (`lib/goal/mega-merge.sh merge`) refuses a PR that touches `.kit.toml`. `stack-merge.sh`, `wrap-land.sh`, `wrap merge --apply` and a direct `gh pr merge` have no such guard. The mega-goal merge pins the head it read with `--match-head-commit`, which covers the guards that read the PR through `gh`. The gate's diff rules read the orchestrator checkout's local `HEAD`, not the PR head, so the pin does not cover them.
- **Codex visibility gap.** Under Codex the hook adapter drops a policy's stdout and stderr on exit 0. The hard-path skip notices reach only `ship-gate.log`, not the operator or the model. Under Claude Code they ride the hook's exit-0 JSON.

## Security-relevant configuration

The hard-path floor forces the full lane's gates on a diff that touches migrations, auth, secrets, CI workflows, infra, kit config or data loss, whatever the spec's lane says.

- **Auth test-path default.** A path with a directory `tests`, `__tests__`, `fixtures` or `cases`, or a basename containing `.test.` or `.spec.`, does not count as `auth`. The list is fixed, case-sensitive and not configurable. A PR can steer it by naming a directory `fixtures/`, and real auth code under such a directory skips `auth` (for example `src/auth/fixtures/keys.ts`). Every skip prints an `[advisory] hard-path skip auth` line on the push and logs an `EXEMPT` line. Every other kind still matches test paths, so `secret` still catches key-, credential- and `.env`-shaped names there.
- **Keep strict `auth` on a test directory.** Add it to `[lanes] extra_hard_paths` in `.kit.toml`. That key only adds hard paths and never removes one.
- **Per-repo exemptions.** `[[gate.hard_path_exempt]]` tables in the committed `.kit.toml` name `paths` (globs), `kinds` and a non-empty `reason`. Only `auth` and `migration` can be exempted. `secret`, `ci`, `infra` and `kit-config` are never exemptable. Data-loss lines, submodules and `extra_hard_paths` ignore every exemption.
- **Read at the merge base only.** The working tree, HEAD, the operator overlay and the kit root never count. The PR that adds an entry edits `.kit.toml`, which is the `kit-config` hard path, so that PR still meets the full lane and cannot use its own entry. A human should review each such PR.
- **Whole-config refusal.** One invalid entry (a forbidden or unknown kind, a missing reason, a malformed glob, a glob that matches a canary) makes no entry apply. Each push prints `WARNING: hard-path exemptions refused` until the base `.kit.toml` is fixed.
- **Canaries.** A glob that matches a built-in canary path (such as `src/auth/login.ts`, `lib/session.ts`, `.env`) is invalid. `[gate] hard_path_canaries` adds literal paths of your own. No config removes a built-in canary. Canaries guard listed paths only, so a broad glob such as `**/*.mjs` or `**/*.go` passes them and can exempt `auth` or `migration` across a whole language. Review of the `.kit.toml` PR is the main guard: reject any glob that starts with a wildcard unless the reason explains why the whole tree is safe, and add a canary for each real auth file in your stack.
- **Visible skips.** Every exempted path prints an `[advisory] hard-path exempt` line with the entry, globs and reason. On an allowed push that line rides the hook's exit-0 JSON (Claude Code only, see above). On a blocked push it appears on stderr.

The reasoning is in `docs/decisions/0039-hard-path-exempt-at-merge-base.md`.
