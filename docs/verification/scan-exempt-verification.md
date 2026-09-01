# Proof of done: exempt docs/verification from the operating-surface scans

Follow-up to ID-640 (#476). That fix scoped the stale-phases scan to `git ls-files`, which then correctly saw its OWN proof doc (`docs/verification/test-meta-scan-scope.md`, now tracked), and that proof quotes the "8 phases" string it documents fixing. Same class bit the earlier drift-repair proof (a `/user:` literal). Root cause: `docs/verification/` is a point-in-time proof-record dir that legitimately quotes the strings under discussion, exactly like `docs/retro/` and `docs/handoff/`, but neither the stale-phases scan nor the SPEC-029 dead-prefix scan exempted it. Fix: add `docs/verification/` to both exclusion lists.

## Recorded run

```
Command: bash tests/test-meta.sh   (tracked proof doc with 3x "8 phases" present)
Exit: 0
Verdict: PASS   # 823 / 823, All meta tests passed
```

## NEGATIVE CONTROL

A TRACKED live-surface doc outside docs/verification/ carrying the string must still fail (the scan keeps its teeth):

```
Command: printf 'the kit has 8 phases now\n' > docs/CONTROL-live-surface.md ; git add ; bash tests/test-meta.sh
Exit: 1
Verdict: PASS   # exactly 1 "stale '8 phases' string found" FAIL, on the live-surface doc; docs/verification/ stayed exempt
```

So docs/verification/ is exempt (the proof doc no longer trips it) while a real operating-surface doc under docs/ still fails. Both the stale-phases scan and the dead-prefix (/user:) scan gained the exemption, so a future proof may quote either forbidden string.

Rollback: two single-token additions to grep exclusion lists in `tests/test-meta.sh`; `git revert`.

## Reproduce

```
bash tests/test-meta.sh
```
