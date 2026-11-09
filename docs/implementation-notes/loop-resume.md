# loop-resume: delta from the brief

Design: `docs/briefs/DECISION-BRIEF-loop-resume.md`. Only decisions the brief leaves open are listed.

- **`resume` round = highest marker round plus one**, not marker count plus one. Streak is read in file order from the end.
- **`--section` heading match is exact** (`## Test plan critique`). The section runs to the next heading of equal or higher level, so `###` subsections stay inside it.
- **stats.sh keeps its own error line.** `ql-verdict.sh` prints `malformed QL-VERDICT in <file>: <line>` on stderr; stats.sh prefixes `stats.sh: ` and still exits 1. Output on the real corpus and on a malformed fixture is byte-identical to before.
- **`gate-ledger.sh actions` matches the ACTION text as a whole-word prefix** (equal, or starts with `<prefix> `). A short sha never matches a longer one. It prints the text, not the timestamp.
- **Greenlight appends before it retries**, so a crash between the two costs one retry, never an extra one.

## Open questions

- **ui-design marker home.** `visual-team` rewrites `## Visual critique` every round, so QL-VERDICT lines written there may not survive. Until the lead appends them somewhere durable (as it does for `### Deferred findings`), `resume` on that section can return `round=1`. The prose names the section; the persistence rule is not changed here.
- **verify has no section.** `commands/verify.md` says `<run record>`; the file is whatever the caller wrote the round markers to.
