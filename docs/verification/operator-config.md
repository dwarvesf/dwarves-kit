# Verification log: SPEC-248 operator config overlay

Spec: `docs/specs/SPEC-248-operator-config.md`. Branch `feat/operator-config`, base 364a29e (origin/master at start), master merged in at f025f74.

## Green run (30cac18)

Command: `bash tests/test-config.sh && bash tests/test-wrap.sh && bash tests/test-precedent.sh && bash tests/test-meta.sh && bash tests/test-config-registry.sh && bash tests/test-command-emit-sweep.sh`
Exit: 0 for each suite
Output (excerpt): `PASS kit-config selftest` (16 cases, 5 for the operator file); `test-wrap: all 134 passed`; `48/48 passed`; `Passed: 840 / 840`; config-registry `19/19 passed`; command-emit-sweep all passed
Verdict: PASS

Task-verifier (fresh context): every precedence probe reproduced on scratch files. `kit_config_get_root` returns the operator value over the kit root, the kit-root value when the operator file is missing, and never a project value; `kit_config_get` resolves project, then operator, then kit root, then the default, verified by removing each higher file in turn; `KIT_CONFIG_OPERATOR` at a nonexistent dir behaves as no file; the default path is `$HOME/.config/dwarves-kit/kit.toml` and `XDG_CONFIG_HOME` redirects it. Seams: `wrap log` with the operator file setting `[wrap] activity_log` prepends to that file; `precedent find --surface inventory` with `[precedent] registry` in the operator file scans it; `commands/wrap.md` names `wrap.before`, the resolution one-liner, and the fold-after-FYI rule; the description carries the wrap-up trigger phrases. Security: the operator path derives from env only (`KIT_CONFIG_OPERATOR`, `XDG_CONFIG_HOME`, `HOME`), never from a TOML value, so a committed `.kit.toml` cannot move it. One finding, fixed in 30cac18: two module-registry rows and a precedent.sh comment still said "kit-root only".

## NEGATIVE CONTROL (lead, throwaway worktree at 30cac18)

Command: `bash lib/gate/negctl.sh <throwaway> "bash tests/test-config.sh" "sed -i '' '85s/kit_config_operator/kit_config_root/' lib/config/kit-config.sh"` (`kit_config_get_root` stops reading the operator file)
Exit: 0 green before; 1 under mutation; 0 after `git checkout HEAD -- lib/config/kit-config.sh`
Output (excerpt): negctl `Verdict: PASS`; under mutation the cases `operator wins kit-root on _root` and `project never reaches _root past operator` go RED
Verdict: RED-as-expected; the throwaway worktree was removed, the shared worktree never mutated
