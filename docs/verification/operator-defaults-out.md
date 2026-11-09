# Verification: operator-defaults-out

The kit ships neutral defaults; the operator's values live in `~/.config/dwarves-kit/kit.toml`. Covers K2 (defaults to keys), K4 (neutral fixtures), K5 (one boards-registry setting). Notes: `docs/implementation-notes/operator-defaults-out.md`.

## Green run

New and extended suites, run on this branch:

```
Command: bash tests/test-board-registry-env.sh && bash tests/test-boundary-lint.sh && bash lib/session/observe/tests/test-vps-report.sh && bash lib/stats/tests/test-home-repo.sh && bash tests/test-config-registry.sh && bash tests/test-meta-docs-registry.sh
Exit: 0
Output:
  test-board-registry-env: all 13 passed
  === 16/16 passed ===
  vps-report: all 13 passed
  6 passed, 0 failed
  === 60/60 passed ===
  Passed: 120 / 120
Verdict: PASS
```

The diff-scoped regression run (`tests/run-all.sh --changed --time`, 111 suites). It failed once, on `test-meta-docs-registry`: the new test files moved the counts in `docs/reference/FEATURES.md`. Regenerated with `feature-registry.sh check --fix`, suite re-run above (120/120):

```
Command: bash tests/run-all.sh --changed --time
Exit: 1 (before the FEATURES.md regeneration; every other suite ok)
Output:
  lib-session-observe-test-vps-report            ok (2s)
  lib-stats-test-home-repo                       ok (0s)
  run-all: FAILED -> test-meta-docs-registry
  run-all: 111 suites run, 0 skipped for missing tooling
Verdict: PASS (after regeneration, test-meta-docs-registry 120/120)
```

The lint on the branch, then on a planted `han-ws` host in a new `lib/` file (the file was moved away after):

```
Command: bash lib/gate/boundary-lint.sh   (clean tree, then with lib/planted-probe.py holding the host token)
Exit: 0, then 1
Output:
  boundary-lint: PASS
  boundary-lint: operator identity in code: lib/planted-probe.py:1: URL = "https://mon-ingest.<host-token>.workers.dev"
Verdict: PASS
```

## Review

One `kit:code-reviewer` pass (security and architecture lenses) on the diff: no blockers. Should-fix taken: the new lint printed PASS when its scan could not run (no python3, a crash); it now fails, pinned by `tests/test-boundary-lint.sh` AC6. Also taken: a failing token command is named on stderr, and `host_id` resolves once. Not taken: scanning `git ls-files` (the negative-control fixtures are plain directories), scanning `commands/*.md` (the brief scopes the deny list to executable code), a registry-path helper in `board.sh` (five identical one-line reads).

## NEGATIVE CONTROL

Each control mutates the guarded line, expects RED, restores with `git checkout HEAD --`, expects green (`lib/gate/negctl.sh`).

### K5: every boards-registry reader honors KIT_BOARDS_REGISTRY

```
## Negative control (negctl)
Command: bash tests/test-board-registry-env.sh
Exit: 0 (green before mutation)
Output:
    PASS R4 names the env registry path
  === R5: board-mirror-cleanup.py --registry default ===
    PASS R5 reads the env registry
    PASS R5 falls back to the repo default
  === R6: reflect/propose.py cockpit source ===
    PASS R6 env beats the repo default
    PASS R6 LEARN_PROPOSE_COCKPIT still beats the env
    PASS R6 repo default when neither is set
  
  test-board-registry-env: all 13 passed

Mutation: sed -i.orig 's|${KIT_BOARDS_REGISTRY:-$repo_root/_meta/boards.txt}|$repo_root/_meta/boards.txt|' lib/board/board.sh && command mv -f lib/board/board.sh.orig /tmp/board.sh.orig
Changed: lib/board/board.sh
Exit: 1 (under mutation, RED expected)
Output:
    FAIL R4 names the env registry path: queue: 0 rows
  === R5: board-mirror-cleanup.py --registry default ===
    PASS R5 reads the env registry
    PASS R5 falls back to the repo default
  === R6: reflect/propose.py cockpit source ===
    PASS R6 env beats the repo default
    PASS R6 LEARN_PROPOSE_COCKPIT still beats the env
    PASS R6 repo default when neither is set
  
  test-board-registry-env: 4 FAILED, 9 passed

Restore: git checkout HEAD -- lib/board/board.sh
Exit: 0 (green after restore)
Verdict: PASS
```

### boundary-lint deny list

```
## Negative control (negctl)
Command: bash tests/test-boundary-lint.sh
Exit: 0 (green before mutation)
Output:
    PASS planted repo token names the file and the check
    PASS planted vault token in a lib/ .py file exits non-zero
    PASS planted vault token names the file and the check
    PASS a token in a module the PATH check excludes is still caught
  
  === AC5: provenance prose and the marker stay green ===
    PASS comment lines, docstrings, markdown, docs/ and a boundary-ok line pass (rc=0)
    PASS code after a docstring is still scanned
  
  === 16/16 passed ===

Mutation: sed -i.orig 's|done < <(deny_scan)|done < <(true)|' lib/gate/boundary-lint.sh && command mv -f lib/gate/boundary-lint.sh.orig /tmp/bl.orig
Changed: lib/gate/boundary-lint.sh
Exit: 1 (under mutation, RED expected)
Output:
    FAIL planted repo token names the file and the check boundary-lint: PASS
    FAIL planted vault token in a lib/ .py file exits non-zero 
    FAIL planted vault token names the file and the check boundary-lint: PASS
    FAIL a token in a module the PATH check excludes is still caught boundary-lint: PASS
  
  === AC5: provenance prose and the marker stay green ===
    PASS comment lines, docstrings, markdown, docs/ and a boundary-ok line pass (rc=0)
    FAIL code after a docstring is still scanned boundary-lint: PASS
  
  === 6/16 passed ===

Restore: git checkout HEAD -- lib/gate/boundary-lint.sh
Exit: 0 (green after restore)
Verdict: PASS
```

### session-report: no built-in URL

```
## Negative control (negctl)
Command: bash lib/session/observe/tests/test-vps-report.sh
Exit: 0 (green before mutation)
Output:
    ok: message is one line
  [8] URL from the operator config passes the gate; missing token degrades to a message
    ok: URL accepted, token message
  [9] hb_token_cmd supplies the token; the unreachable URL fails soft
    ok: token from command, soft failure
  [10] host id: config key wins, else the local hostname
    ok: host_id from config
    ok: host_id defaults to the short hostname
  
  vps-report: all 13 passed

Mutation: sed -i.orig 's|    return flag or os.environ.get("SESSION_REPORT_URL") or kit_root_get("session_report.url")|    return flag or "https://example.invalid"|' lib/session/observe/bin/session-report && command mv -f lib/session/observe/bin/session-report.orig /tmp/sr.orig
Changed: lib/session/observe/bin/session-report
Exit: 1 (under mutation, RED expected)
Output:
    ok: message is one line
  [8] URL from the operator config passes the gate; missing token degrades to a message
    ok: URL accepted, token message
  [9] hb_token_cmd supplies the token; the unreachable URL fails soft
    ok: token from command, soft failure
  [10] host id: config key wins, else the local hostname
    ok: host_id from config
    ok: host_id defaults to the short hostname
  
  vps-report: 12 passed, 1 FAILED

Restore: git checkout HEAD -- lib/session/observe/bin/session-report
Exit: 0 (green after restore)
Verdict: PASS
```

### stats: home repo from operator config

```
## Negative control (negctl)
Command: bash lib/stats/tests/test-home-repo.sh
Exit: 0 (green before mutation)
Output:
  PASS  H1 unset -> empty
  PASS  H2 operator toml sets it
  PASS  H3 project toml ignored
  PASS  H4 block staged with empty home
  PASS  H4 no Home line
  PASS  H5 Home line carries the value
  6 passed, 0 failed

Mutation: sed -i.orig 's|r.stdout.strip() if r.returncode == 0 else ""$|"ops-x"|' lib/stats/src/stats/config.py && command mv -f lib/stats/src/stats/config.py.orig /tmp/cfg.orig
Changed: lib/stats/src/stats/config.py
Exit: 1 (under mutation, RED expected)
Output:
  FAIL  H1 unset -> empty
  FAIL  H2 operator toml sets it
  FAIL  H3 project toml ignored
  PASS  H4 block staged with empty home
  PASS  H4 no Home line
  PASS  H5 Home line carries the value
  3 passed, 3 failed

Restore: git checkout HEAD -- lib/stats/src/stats/config.py
Exit: 0 (green after restore)
Verdict: PASS
```

