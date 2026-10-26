# mega

Read-only views over a mega-goal. A roadmap's own `[x]` boxes can lie, so these verbs check each sub-goal against git and `gh` and render the result.

**Entry points**
- `bin/mega` forwards to `lib/mega/mega.sh`.
- `mega.sh status <slug>`: reconcile `ROADMAP.md` sub-goal claims against branches, commit counts and PR state, and flag drift. `--rollup-only` prints the one summary line.
- `mega.sh review <slug> --html`: one self-contained sign-off page from the reconcile, the gate and run ledger, and PR state (`mega-review.py`).
- `mega.sh report <slug>`: the RUN_REPORT telemetry skeleton, with the gate matrix read from the rid ledgers (`mega-report.py`). `--out` writes a file.
- `mega.sh runs`: one static HTML page of run cards over every registered repo (`runs-dashboard.py`).

**Roots**: `--megagoals-root` (or `MEGAGOALS_ROOT`) is where `<slug>/ROADMAP.md` lives. `--code-root` (or `CODE_ROOT`) is the repo whose branches and PRs are the git truth.

**Tests**: `tests/test-mega.sh`, `tests/test-mega-review.sh`, `tests/test-mega-report.sh`, `tests/test-mega-reconcile.sh`, `tests/test-mega-gate-head.sh`, `tests/test-mega-gate-parity.sh` and `tests/test-runs-dashboard.sh`. Run `bash tests/run-all.sh --only mega`.

**Spec and docs**: `docs/specs/SPEC-096-mega-reconcile.md`, `docs/specs/SPEC-197-mega-review-dashboard.md`, `docs/specs/SPEC-215-runs-dashboard.md`.
