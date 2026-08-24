# Proof of done: memsweep-oserror

Scope: `memory_lens._classify_and_test` crashed the whole `stats memory-sweep` with `PermissionError: [Errno 13] Permission denied: '/var/root/Library/Application'` when any note's inline code span named a path whose parent dir is unreadable on the host. Guard both path branches: OSError = untestable-here, token skipped (never reported dead).

## Green run

Command: bash tests/test-memory-lens.sh   (from lib/stats, with the fix + new regression fixture)
Exit: 0
Verdict: PASS, 40 passed, 0 failed; includes the new `unreadable-abs-path-note` fixture (inline span under /var/root/...) asserted NOT flagged dead and not crashing.

Command: uv run stats memory-sweep --json   (live, against the ops-toolkit real corpus that originally crashed)
Exit: 0
Verdict: PASS, sweep completes, 368 rows returned (pre-fix: PermissionError traceback at memory_lens.py `_classify_and_test` via `Path.exists()`).

## Negative control

Command: revert the abs-path OSError guard (restore bare `Path(token).exists()`), rerun bash tests/test-memory-lens.sh
Exit: 1
Verdict: RED as expected, 25 of 40 fail (the crash cascades through every sweep-dependent assertion).

Command: restore the guard, rerun bash tests/test-memory-lens.sh
Exit: 0
Verdict: PASS, 40/40 green again.

## Rationale

The module's own rule is that a false dead-ref costs trust more than a missed one; an unreadable-parent path is untestable on this host, not dead, so the token is skipped (`None`) rather than flagged. The `~user` branch already caught `RuntimeError` for unresolvable users; this adds the missing `OSError` shape on both branches.
