# Implementation notes: SPEC-412 data-loss sqli carve-out

Deltas from `docs/specs/SPEC-412-data-loss-hardpath-scope.md` only.

- AC1, AC6 and AC7 rows live in their own cases (`floor-data-loss-sqli-paths`, `floor-data-loss-sqli-canonical`, `floor-data-loss-sqli-guards`), not in `case_floor_data_loss`. They need the carve-out flag, and `case_floor_data_loss` runs without it. The Verification command already names the new cases.
- AC2 adds one control row per language (`tests/c.sh`, `c.py`, `c.js`, `c.rs`, `c.rb`, want `miss`). They show that each `hit` row hits because of its G9 opener line, not because of G1 or a line guard.
- AC10 leg 1: the awk shim keys on the `sqli-allow` argument of pass B, not on an `ENVIRON` variable. The self-test shares the variables, so an `ENVIRON` key would fail the self-test first. The leg now asserts `rewrite failed` exactly.
- NC2 as written (whole-line replace) goes red, but through `floor-data-loss-sqli-canonical`: the self-test catches the mutation and sends the scan to raw. NC2b adds the same mutation with the self-test stop removed, and then `floor-data-loss-sqli-payload` (AC8) goes red. Both results are in `docs/verification/data-loss-hardpath-scope.md`.
- The producer awk always runs under `LC_ALL=C` and always writes `$tmp/plen`, flag or not. One extra print per added line; `floor-non-ascii` and both timing cases stay green.
- G9 Ruby pattern is `%[qQ]?[({<[]`.
- AC12 big head image is 5,888,925 bytes (600,000 lines).
- Touches the spec did not list: `lib/config/module-registry.md` gains a `KIT_FLOOR_SQLI_CARVEOUT` row (the config-registry drift lint requires it), and `docs/FEATURES.md` was regenerated (`feature-registry.sh check --fix`), because the new spec changes the reference counts.
- The spec's Grounding used a home-relative ops-toolkit path; it now reads `<ops-toolkit checkout>` (the no-personal-paths lint).
