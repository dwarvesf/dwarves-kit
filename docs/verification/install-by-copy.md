# Proof of done: install-by-copy (SPEC-066)

Behavioral change: install.sh deploys copies instead of symlinks; INSTALL-STAMP with a
managed= list; uninstall removes copies; kit-health staleness probe.

## Green run

Command: `bash tests/test-hooks.sh`
Exit: 0
Output (tail): `Passed: 301 / 301` , includes the 13 SPEC-066 assertions: fresh-install
real-file asserts (hooks executable, lib real dir, contracts real), stamp content
(version=, sha=, managed=WORKFLOW.md when the user owns AGENTS.md), idempotent re-run,
the two-run user-file durability probe, and 4 uninstall asserts (lib + managed contract +
stamp removed, user file untouched).

Command: `bash tests/test-meta.sh`
Exit: 0
Output (tail): `Passed: 423 / 423`

## NEGATIVE CONTROL

In-suite, runs on every suite execution: an installed hook is hand-edited (`# drift`
appended) and install.sh re-run; the assertion REQUIRES the drift line to be gone
(`assert_output_not_contains`). Reverting the cp-based deploy to the old `ln -s` would
flip this control (a symlink cannot drift from its target) AND flip the
`install: hooks are real files, not symlinks` assert RED.

Review-driven live control: with the FIRST draft (stamp-presence guarding), the two-run
user-file probe destroyed the sentinel (`# MY OWN AGENTS` replaced by the kit file) ,
observed live during review; the managed-list fix turned it GREEN.

## Reproduce

```bash
cd dwarves-kit
bash tests/test-hooks.sh   # 301/301
```

VERDICT: PASS
