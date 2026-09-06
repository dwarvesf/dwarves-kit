# Implementation notes: SPEC-248 operator config overlay

## 2026-09-07 10:00 Test suites pin the operator layer at a nonexistent path

Context: the spec asked for operator-layer cases in `tests/test-config.sh`, `tests/test-wrap.sh`, and `tests/test-precedent.sh`. It did not say what the other cases in those files should see.

Decision: each of the three suites exports `KIT_CONFIG_OPERATOR` at a path that does not exist, before any case runs. Only the deliberate operator cases point it at a fixture.

Why: the default operator path is `${XDG_CONFIG_HOME:-$HOME/.config}/dwarves-kit/kit.toml`. Without the pin, a real file on the operator's machine reaches every case that reads a config key, and `tests/test-precedent.sh` already has cases that assert an EMPTY kit root produces no registry scan. Those would fail only on machines that carry the file, which is the worst failure shape.

Alternatives: unset `XDG_CONFIG_HOME` and rewrite `HOME` per case. Rejected: `HOME` is already load-bearing in the wrap log path checks.

Impact: three added export lines, no behavior change.

## 2026-09-07 10:05 The spec-nominated line citation in module-registry.md moved

Context: two existing registry rows cite `kit-config.sh:64-75` as the source for the root-only read model. The accessor moved when the operator layer landed.

Decision: both citations now read `kit-config.sh:75-90`, and the new `wrap.before` row uses the same range.

Why: a line citation that points at the wrong function is worse than none. The doc-drift audit reads these.

Impact: three citations changed in `lib/config/module-registry.md`.

## 2026-09-07 10:10 `tests/test-config.sh` was not edited

Context: the spec says the resolver cases go in `tests/test-config.sh`.

Decision: the cases went into the resolver's own `selftest` block in `lib/config/kit-config.sh`, which `tests/test-config.sh` invokes as its whole body.

Why: `tests/test-config.sh` is a four-line delegator with no case of its own. Adding a second, parallel case list there would split the resolver's test surface across two files.

Impact: `bash tests/test-config.sh` runs the new cases unchanged, and the required mutation still turns it RED.
