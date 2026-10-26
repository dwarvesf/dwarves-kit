# adopt

Adopts a repo into the kit's operate-contract. It injects a small `AGENTS.md` pointer, a proof marker, and a `CLAUDE.md` loader, so an agent classifies its work and the ship gate engages. It never copies the engine into the target and never overwrites a repo's own `AGENTS.md`.

**Entry points**
- `lib/adopt.sh [--check | --dry-run | --refresh [--swap-agents]] [--single-source | --no-single-source] [--with <a,b,c>] <target-dir>`: the `/kit:adopt` driver. It sits at the lib root, outside this directory. `--check` reports status and writes nothing. `--refresh` re-syncs the kit-managed pieces.
- `lib/adopt/known-hashes.sh`: regenerates `agents-known.sha256` from git history. Refuses in a shallow clone.
- `lib/adopt/onboarding-cost.sh <transcript.jsonl>`: prints turns, tokens, and whether the agent read the full contract. Reads omp and Claude Code transcripts.

**Layout**
- `AGENTS.pointer.md`: the pointer template that adopt writes.
- `agents-known.sha256`: hashes of every old kit `AGENTS.md` and pointer. `--refresh --swap-agents` replaces only a file that matches one.

**Tests**: `bash tests/test-adopt.sh` and `bash tests/test-wrap-adopt.sh` (the wrap-side adopt step).

**Spec and docs**: `docs/specs/SPEC-047-kit-adopt.md`, `docs/specs/SPEC-371-adopt-pointer-onboarding.md`, `commands/adopt.md`.
