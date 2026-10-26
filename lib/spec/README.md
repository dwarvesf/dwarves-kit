# spec

Spec registry tools: find spec files, show them in one table, reserve the next free number, tick off tasks, and check the Depth line. They remove hand-edited spec bookkeeping and number collisions.

**Entry points**
- `lib/spec/spec.sh <verb>`: the dispatcher. `bin/spec` forwards to it.
- `spec index [list]`: the spec table, grouped by namespace (`spec-index.sh`).
- `spec next next|check <NNN>|reserve`: the next free number, a taken check, or an atomic claim (`spec-next.sh`).
- `spec task-done <spec> <TASK-ID> --commit <sha>`: check a task off and log its run. It never commits (`spec-task-done.sh`).
- `spec depth level|wants|check|size`: read and check the header `Depth:` line (`spec-depth.sh`).

**Layout**
- `spec-find.sh`: sourced resolver that maps a repo or slug to spec files. Other kit scripts source it. It has no verb.

**Tests**: root suites `tests/test-spec-*.sh`, plus `tests/test-meta-spec-depth.sh` and `tests/test-whole-spec-dispatch.sh`. Run `bash tests/run-all.sh --only spec`.
