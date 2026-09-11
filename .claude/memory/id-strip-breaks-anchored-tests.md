---
name: id-strip-breaks-anchored-tests
description: An id inside a test is the test's input, not decoration; stripping that id from the doc the test reads breaks the test, and only the full suite catches it.
metadata:
  type: reference
---

The scattered-id cleanup removed `(ID-484)` from a heading in `skills/web-drift/SKILL.md`. `tests/test-web-drift-refusal-guard.sh` extracts the guard line with an awk anchored on that exact literal, so the extraction returned empty and the suite went red. The same batch added `bin/lint` without adding it to the `EXPECTED` census in `tests/test-bin-forwarders.sh`.

**Why:** `lib/lint/scattered-ids.sh` exempts `tests/` from the strip, so a test may hold an id. It cannot see the reverse case: a test that ANCHORS on an id living in a file the strip does touch. The lint reports clean and CI still fails.

**How to apply:** before stripping an id from prose or a comment, grep `tests/` for that id and for the heading text around it. After stripping, run the full suite, never the lint alone. A new test anchors on stable prose, never on an id. Adding a `bin/` entry means updating the census in the same commit.
