# Spec: add `spm --version` flag
Generated: 2026-04-21
Status: VALIDATED

## Problem

`spm` has no way to report its installed version. Users debugging issues with `pip install spm` can't easily confirm which release they have. Common ask in install-help threads.

## Solution

Add a `--version` flag to the top-level CLI. Reports the version string from `importlib.metadata.version("spm")`. No new dependency; uses Python 3.12 stdlib.

## Technical Design

### Data model changes
None.

### CLI changes
- `spm --version` prints `spm <version>` and exits 0.
- `spm -V` works as a short alias.
- Both work before any subcommand parsing (so `spm --version install` still prints the version, not an install error).

### Infrastructure changes
None.

## Task Breakdown

### Phase 1: Implement and test

- [ ] **TASK-001: Add --version flag to argparse setup**
  - Files: `src/spm/cli.py`
  - Use `parser.add_argument("--version", "-V", action="version", version=...)` with the version pulled from `importlib.metadata.version("spm")`.
  - Acceptance criteria:
    - [ ] `spm --version` prints `spm <semver>` and exits 0
    - [ ] `spm -V` produces identical output
    - [ ] `spm --version install foo` prints version (does not attempt the install subcommand)
    - [ ] `spm --help` lists `--version` in the options block

- [ ] **TASK-002: Test coverage**
  - Files: `tests/test_cli.py` (extend)
  - Acceptance criteria:
    - [ ] Test that captures stdout and asserts the format `spm <semver>`
    - [ ] Test that asserts exit code is 0
    - [ ] Test that asserts `-V` short form behaves identically to `--version`
    - [ ] All existing tests still pass

## Acceptance Criteria (global)

- [ ] Both task ACs met
- [ ] `uv run pytest` exits 0
- [ ] `uv run ruff check .` exits 0
- [ ] No new runtime dependencies in `pyproject.toml`
- [ ] README updated with the new flag in the usage examples

## Edge Cases

1. **`spm` is run from source (not installed)**: `importlib.metadata.version("spm")` raises `PackageNotFoundError`. Catch it and print `spm (development build)` instead of crashing. Acceptance criterion includes a test for this case.
2. **User passes both `--version` and `-V`**: argparse handles this naturally (last one wins, both produce the same output). No special handling needed.
3. **User passes `--version` after a subcommand**: argparse's `action="version"` only fires for the top-level parser, so `spm install --version` would NOT print the version (it would attempt to install a package named `--version`). Documented in the help text. Out of scope for v1.

## Out of Scope

- Per-subcommand version flags (`spm install --version`). Not a real user need.
- Version comparison utility (`spm version --check-newer`). Future, separate spec.
- Auto-update on outdated version detected. Belongs in a separate `spm self-update` feature.

## Decision Log

- **DEC-001**: Use `importlib.metadata.version` rather than hardcoding the version string in `__init__.py`.
  - **Rationale**: single source of truth (`pyproject.toml`); avoids the "release script forgot to bump `__init__.py`" bug class.
  - **Rejected alternative**: `__version__ = "1.2.3"` in `src/spm/__init__.py`. Common pattern but creates two places that must agree on the version.

- **DEC-002**: Keep both `--version` and `-V` (don't enforce single form).
  - **Rationale**: `-V` is the de-facto short form across CLIs (`python -V`, `git -V` doesn't exist, `pip -V` works). Cheap to support both via argparse's positional-args feature.
