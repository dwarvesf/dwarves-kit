# loop

Position of a bounded loop, derived from the record the loop already writes. No state store.

**Entry points**
- `lib/loop/ql-verdict.sh parse <file> [--section <heading>]`: one `round clean findings` line per `[[QL-VERDICT round=N clean=BOOL findings=K]]` marker, in file order. Backtick-wrapped markers count.
- `lib/loop/ql-verdict.sh resume <file> [--section <heading>]`: prints `round=<next> clean_streak=<consecutive clean rounds at the end> last_findings=<K or ->`. A missing file or no markers prints `round=1 clean_streak=0 last_findings=-`.

`--section` limits the scan to one markdown section, for example `--section '## Test plan critique'`. A line that names QL-VERDICT but breaks the grammar is a loud error (exit 65). Read-only.

**Callers**: `lib/gauntlet/stats.sh` (marker grammar), and the round loops in `commands/gauntlet.md`, `commands/test-plan-review-team.md`, `commands/ui-design.md`, `commands/verify.md`.

**Tests**: `bash tests/test-ql-verdict.sh`. **Design**: `docs/briefs/DECISION-BRIEF-loop-resume.md`.
