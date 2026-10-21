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
- Security review fold (DEC-11 to DEC-13). G0 rejects a backslash or control byte in pass A and again in pass B, as an awk check before the path ERE, not inside `_HL_sqli_testpath`. G7 is an inline awk regex, as before. G4 swaps `\$\{` for `\$` in `_HL_sqli_join`, a superset.
- Dropping the `test_`/`test-` basename arm keeps the #4630 sample exempt: its path has a `test/` segment. Checked on the real commit before and after the change.
- Existing rows the tightening flipped. AC6 `tests/é.sh` moved its multibyte text after the span (`for b in ...; do # é`); the old `é=1; for b in ...` line is now an AC7 hit row. AC2 `.js` rows use a bare `for b in` header, so they still isolate the G9 opener. AC9 `tests/a<TAB>b.sh` now hits with the literal too. `floor-data-loss-sqli-long-line` puts its 20,000 quoted words after the span, since words before the `for` now fail G7.
- New case `floor-data-loss-sqli-review-repros` builds the four review repro shapes from files. The echojoin repro holds a bare `$`, so G4 also catches it; the isolated G7 row `psql -c select x in "..."` in `floor-data-loss-sqli-guards` carries the fix-2 negative control.
