# Proof of done: harvest sweep extractor model and Codex fallback (SPEC-357 DEC-92)

Verdict: PASS. The sweep extractor runs `claude -p --model sonnet` with every safety flag. A Claude failure that is not auth-shaped runs the same prompt once through `codex exec --sandbox read-only`. A Claude limit that the fallback cannot cover still holds with rc 0. Feature commit: `1b10c44f`.

## Acceptance -> confirmation

| Requirement | Test (`tests/test-harvest-sweep.sh`) | Result |
|---|---|---|
| Primary argv is `-p --model sonnet` plus `--setting-sources project --tools '' --strict-mcp-config --no-session-persistence` | `fallback: the default primary is sonnet with every safety flag` | PASS |
| `harvest.extractor_model` sets the model (root-only) | `fallback: harvest.extractor_model sets the primary model` | PASS |
| A limit-shaped Claude failure calls the fallback once and succeeds, with the STATE row | `fallback: a limit-shaped primary succeeds through Codex`, `... the report carries the fallback STATE row`, `... one primary call, one Codex call, no probe` | PASS |
| A generic Claude failure also falls back; an auth-shaped one never does | `fallback: a generic primary failure falls back too`, `fallback: an auth-shaped primary failure never calls Codex` | PASS |
| `extractor_fallback = "none"` makes no Codex call | `fallback: extractor_fallback = none makes no Codex call` | PASS |
| Both limit-shaped: a hold, rc 0, no fail count | `fallback: a limit on both is a hold`, `fallback: a limit on both extractors is a hold, rc 0, no page` | PASS |
| A limit-shaped probe holds instead of paging | `fallback: a limit-shaped probe holds instead of paging`, `... raises no INCIDENT` | PASS |
| Fallback reply with credential shapes is redacted | `fallback: a Codex reply with credential shapes is redacted` | PASS |
| Codex argv carries `exec --sandbox read-only --skip-git-repo-check --ephemeral --ignore-user-config -o <file> -`, prompt on stdin only, empty 0700 cwd under the sweep state dir, removed after | `fallback: codex argv carries ...`, `... reads the prompt on stdin ...`, `... never rides the command line`, `... cwd is empty and 0700`, `... temp dir is removed` | PASS |
| The fallback STATE row renders and the report lints clean | `fallback: the fallback STATE row renders in the report`, `... lints clean` | PASS |

Every test stubs both binaries. The whole suite puts a failing `codex` stub first on PATH, so no test reaches a real model or a real Codex.

## Confirmation run-table

| Command | Exit | Result |
|---|---|---|
| `bash tests/test-harvest-sweep.sh` | 0 | 632/632 |
| `bash tests/test-meta.sh` | 0 | 887/887, `docs/FEATURES.md` fresh (no regeneration needed) |
| `bash tests/test-install-modules.sh` | 0 | 42 passed, 0 failed |
| `KIT_CONFIG_OPERATOR=<empty dir> bash tests/test-kit-foldin-hooks.sh` | 0 | 97/97 |
| `bash tests/test-kit-foldin-hooks.sh` (Mini operator config) | 1 | 85/97, the same 12 rows fail on unchanged `master` 64e442d0: the Mini's operator `kit.toml` has `harvest.enable = true` and the host has the `installed` marker, so `harvest.sh` stands down by design (DEC-9) |
| `bash tests/test-config-registry.sh` | 1 | 55/56, orphan `MEGA_ROOT` from `lib/board/work.sh` (#834, on `master`); this change adds no env var |
| `codex exec --sandbox read-only --skip-git-repo-check --ephemeral --ignore-user-config -o <file> - < PROBE_PROMPT` (live, no transcript) | 0 | `{"learnings": [], "sightings": []}` in about 9 s; flags checked in `codex exec --help`, codex-cli 0.158.0 |

## Negative controls

Each ran `lib/gate/negctl.sh "$PWD" "bash tests/test-harvest-sweep.sh" "<mutation>"` on the committed tree.

| Mutation (on `hooks/harvest_sweep.py`) | Green before | Red under mutation | Green after restore | Verdict |
|---|---|---|---|---|
| Drop the fallback call (`run_fallback_extractor` replaced by a constant failure) | 0 | 1 | 0 | PASS |
| Drop `--sandbox read-only` from `CODEX_FALLBACK` | 0 | 1 | 0 | PASS |
| Remove the limit-shaped probe hold (`if False:`) | 0 | 1 | 0 | PASS |
| Primary model back to `haiku` | 0 | 1 | 0 | PASS |
| Remove the auth skip (`if ok or False and AUTH_RE...`) | 0 | 1 | 0 | PASS |

```
## Negative control (negctl)
Command: bash tests/test-harvest-sweep.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' 's/f_ok, f_out, f_err = run_fallback_extractor(prompt)/f_ok, f_out, f_err = False, "", ""/' hooks/harvest_sweep.py
Changed: hooks/harvest_sweep.py
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- hooks/harvest_sweep.py
Exit: 0 (green after restore)
Verdict: PASS
```

## Rollback

| Want | Do |
|---|---|
| Stop the fallback on one host, keep Sonnet | operator `kit.toml` `[harvest] extractor_fallback = "none"` |
| Back to Haiku | operator `kit.toml` `[harvest] extractor_model = "haiku"` |
| Revert the change | `git revert` the squash commit of this PR; no state migration: the cursor, ledgers, and `extract/` cache formats are unchanged, and a leftover `sweep/codex-*` temp dir from a killed run holds no state |
