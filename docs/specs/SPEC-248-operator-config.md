# Spec: the operator config overlay

Generated: 2026-09-07
Status: SHIPPED
Lane: normal
Type: spec-feature
File: `docs/specs/SPEC-248-operator-config.md`
References: `lib/config/kit-config.sh` (the single TOML resolver, ADR-0034 decision 4); `lib/config/module-registry.md` (the env-to-key registry both `bin/config` and the drift lint parse); SPEC-246 (`/kit:wrap`, which owns `wrap.activity_log`); SPEC-245 (`precedent find`, which owns `precedent.registry`).

## Problem

The resolver reads two files: a per-project `.kit.toml` and the kit-root `kit.toml`. Consumer keys such as `wrap.activity_log` and `precedent.registry` name paths belonging to one operator, not to a project and not to the kit. Today the only home for them is the kit-root `kit.toml`, which is a file inside the kit checkout. A kit upgrade replaces that checkout, so every per-operator path an adopter set is a merge conflict or a silent loss. The project layer cannot hold them either: a project toml rides inside an untrusted pull request, which is exactly why `kit_config_get_root` skips it.

## Solution

### Approaches considered

1. **A third file the operator owns, read between the project and the kit root.** `kit_config_operator()` prints `${KIT_CONFIG_OPERATOR:-${XDG_CONFIG_HOME:-$HOME/.config}/dwarves-kit}/kit.toml`. `kit_config_get` resolves project > operator > kit-root > default; `kit_config_get_root` resolves operator > kit-root > default. Tradeoff: one more file to explain and one more layer in every read.
2. **A per-key env var for each operator path.** Tradeoff: every new consumer key needs a new env var, a new registry row, and a shell that exports it before any command runs. That is the ad-hoc pattern ADR-0034 decision 4 removed.

### Chosen approach + why

Approach 1. The operator file is the layer the two-file model was missing: the project layer is untrusted, the kit-root layer is disposable on upgrade, and per-operator paths belong to neither. One resolver change serves every current and future consumer key.

### Extensibility & boundaries

- Load-bearing dimension: the number of layers, which is now fixed at three. A fourth layer would need its own trust argument.
- Units: `lib/config/kit-config.sh` (the resolver and its selftest), `lib/config/module-registry.md` (the `KIT_CONFIG_OPERATOR` row plus the `wrap.before` row), `commands/wrap.md` (the before seam), `kit.toml` (the `wrap.before` declaration).
- Out of the closed set: no hook reads the operator file, and no installer writes it. The operator creates it by hand.

## Design

obvious: three layers, one resolver, precedence by trust and by ownership.

### Diagram

```
kit_config_get <key>                     kit_config_get_root <key>
   │                                        │
   ├─ project  $KIT_PROJECT_ROOT/.kit.toml  │   (SKIPPED: rides inside an untrusted PR)
   ├─ operator $KIT_CONFIG_OPERATOR/kit.toml├─ operator  (on the operator's machine, never in a PR)
   ├─ kit-root $KIT_CONFIG_ROOT/kit.toml    ├─ kit-root  (replaced on every kit upgrade)
   └─ caller default                        └─ caller default
        a missing file at any layer is skipped silently
```

## Interfaces

| Name | Shape | Contract |
|---|---|---|
| `kit_config_operator` | `kit_config_operator` -> path | Prints `${KIT_CONFIG_OPERATOR:-${XDG_CONFIG_HOME:-$HOME/.config}/dwarves-kit}/kit.toml`. No read, no side effect. |
| `kit_config_get` | `kit_config_get <section.key> [default]` | project > operator > kit-root > default. |
| `kit_config_get_root` | `kit_config_get_root <section.key> [default]` | operator > kit-root > default. The project layer never participates. |
| `[wrap] before` | `kit.toml` key, string | Names a skill `/kit:wrap` invokes before step 0. Resolved with `kit_config_get_root`. Empty means no skill runs. |

## Task Breakdown

**TASK-001: the operator overlay, its `wrap.before` consumer, and the tests.** Add `kit_config_operator` and wire it into both accessors; declare `[wrap] before` in `kit.toml` and document the seam in `commands/wrap.md`; add the `KIT_CONFIG_OPERATOR` and `wrap.before` rows to `lib/config/module-registry.md`; extend the resolver selftest, `tests/test-wrap.sh`, and `tests/test-precedent.sh`.

## After state

An operator keeps `wrap.activity_log`, `precedent.registry`, and `wrap.before` in one file under their own config directory. A kit upgrade replaces the kit checkout and touches none of it. An adopter who never creates the file sees no behavior change, because a missing file is skipped silently.

## Verification

| Check | Command | Expect |
|---|---|---|
| resolver precedence | `bash tests/test-config.sh` | PASS, including the five operator cases |
| wrap consumer key | `bash tests/test-wrap.sh` | all pass, including the operator activity-log case |
| precedent consumer key | `bash tests/test-precedent.sh` | all pass, including the operator registry case |
| command + registry lints | `bash tests/test-meta.sh`, `bash tests/test-command-emit-sweep.sh`, `bash tests/test-docs-wiring.sh`, `bash tests/test-config-registry.sh` | all pass |
| mutation | swap the operator and kit-root order inside `kit_config_get_root` in a throwaway copy, then run `tests/test-config.sh` | RED |

## Edge Cases

- **No operator file.** Every read skips the layer and behaves exactly as before.
- **An empty value in the operator file.** `_kit_toml_get` prints nothing, so the read falls through to the kit root, matching how the project layer already behaves.
- **A test running on a live machine.** The operator's real file would leak into a fixture, so `tests/test-wrap.sh`, `tests/test-precedent.sh`, and the resolver selftest each pin `KIT_CONFIG_OPERATOR` at a path that does not exist.
- **`XDG_CONFIG_HOME` set to a shared directory.** The operator owns that directory by definition; the kit adds no second trust check.

## Decision Log

- **Precedence is project > operator > kit-root for `kit_config_get`.** A project setting is the most specific statement about that project, so it still wins. The operator file sits above the kit root because the kit root is the shipped default and gets replaced on upgrade.
- **`kit_config_get_root` reads the operator file.** The name says root, but the property the accessor actually enforces is "not from a pull request." The operator file satisfies that property: it lives on the operator's machine and no PR can add or edit it. Skipping it would leave the security-bearing keys stranded in the disposable kit checkout, which is the problem this spec exists to fix.
- **`wrap.before` resolves with `kit_config_get_root`.** The key names code the command runs, so a project toml must never set it.
