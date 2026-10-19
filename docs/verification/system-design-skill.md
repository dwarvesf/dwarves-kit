# Verification -- system-design-skill

The kit now ships the `system-design` skill (`skills/system-design/SKILL.md`) and its UML drawing-set engine (`lib/system-design/`); `/kit:design` and `docs/SYSTEM-DESIGN.md` treat it as a kit component, not an external dependency.

## Green run

Real flow: the engine builds the marketplace fixture against its base file and renders one PNG per sheet through headless Edge (no Chrome at the macOS default path, so `CHROME` points at Edge).

```
Command: CHROME="/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" lib/system-design/build --model lib/system-design/examples/marketplace/SYSTEM-DESIGN.md --base-file lib/system-design/examples/marketplace/SYSTEM-DESIGN.base.md --out $T/uml.html --shots $T/shots
Exit: 0
Output:
built $T/uml.html (title: Agent Marketplace UML, base: SYSTEM-DESIGN.base.md)
cover.png 65148 bytes md5 c1cc20d8
d-use-cases.png 195359 bytes md5 41b3f677
d-schema.png 196027 bytes md5 3478fa33
d-sm-order.png 97589 bytes md5 49a3637e
d-deployment.png 60582 bytes md5 a64efa8b
(17 PNGs in all, every one over 10 KB, no two sharing an md5; no headless browser left running afterwards)
Verdict: PASS
```

Suite run:

```
Command: bash tests/test-system-design.sh
Exit: 0
Output:
== system-design build ==
  PASS build exits 0 on the marketplace fixture with a base file
  PASS model title is non-empty
  PASS output contains the model title
  PASS output embeds the base model
  PASS no build placeholder survives
== refusals ==
  PASS a model containing </script is refused (non-zero exit)
  PASS the refusal names </script
  PASS no output file is written for a refused model
  PASS build without --out is refused
== engine smoke test (node test.mjs) ==
  PASS node lib/system-design/test.mjs exits 0

system-design: 10 passed, 0 failed (10 checks)
Verdict: PASS
```

Registration:

```
Command: bash tests/test-meta.sh
Exit: 0
Output:
Passed: 933 / 933 (README skills table rows == live skills, docs/FEATURES.md is fresh)
Verdict: PASS
```

The committed `docs/design/kit-uml.html`, rebuilt with the same base ref as before, differs from the old file only in the three lines that changed in `docs/SYSTEM-DESIGN.md`, so the copied engine renders the same as the personal one.

## Negative control

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-system-design.sh" "sed -i '' 's|^set -euo pipefail\$|set -euo pipefail; exit 1|' lib/system-design/build"
Exit: 1 (under mutation, RED expected)
Output:
    FAIL no build placeholder survives
    FAIL the refusal names </script
  system-design: 5 passed, 5 failed (10 checks)
  (the build-exit-0, output-title and embedded-base checks also go RED)
Verdict: PASS
```

The mutation made `lib/system-design/build` exit 1 before doing any work. The suite went RED (5 of 10 checks failed), negctl restored the file with `git checkout HEAD --`, and the suite was green again with a clean tree.

## Not proven
- `--shots` was run with Microsoft Edge, not Google Chrome; the code path is the same (`CHROME` override).
- `test.mjs` and `--shots` need network (js-yaml from cdnjs); the suite prints SKIP for `test.mjs` without node or network.
- A fresh `install.sh` into `~/.claude` was not run; the skill and lib layout follows the existing `skills/*/SKILL.md` and `lib/<name>/` deploy rules.
