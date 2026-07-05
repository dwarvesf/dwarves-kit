# Proof of done: hook-precision (SPEC-064)

Behavioral change: hooks/safety-gate.sh rewritten parse-aware; hooks/ship-gate.sh
cd-target resolution; lib/spec/spec-next.sh added.

## Green run

Command: `bash tests/test-hooks.sh`
Exit: 0
Output (tail): `Passed: 282 / 282` , includes the 20 SPEC-064 assertions: 5 false-positive
allows (FP1 merge-by-SHA prose, FP2 push+base-edit compound, FP3 heredoc delete literal,
FP4 quoted commit prose, FP5 echo prose), 4 still-blocks (HEAD:master, +refspec, compound
rm, DROP TABLE via psql), 6 review-driven (quoted-ref block, quoted-allowlist allow,
bash -c / eval / xargs smuggles, ship-gate cd-target probe), 3 spec-next, 2 resurrected
assert_true assertions.

Command: `bash tests/test-meta.sh`
Exit: 0
Output (tail): `Passed: 421 / 421`

Live 17-case allow/block matrix (`/tmp/sg-matrix.sh`, 2026-06-10): all ALLOW rows exit 0,
all BLOCK rows exit 2, allowlist + force-with-lease intact.

## NEGATIVE CONTROL

Run live during build (recorded in SPEC-064 ## Test plan): the heredoc-stripper line in
hooks/safety-gate.sh was disabled (`marker = m; inhd = 1` replaced with a no-op), then the
FP3 fixture (`bash -s <<EOF` with a bare destructive-delete body line) was fed to the hook:

- Stripper disabled -> Exit: 2 (the pin would go RED)
- Stripper restored -> Exit: 0 (GREEN)

Note: the FIRST fixture draft hid the delete behind a `#` comment and could not flip
(exit 0 both ways); it was strengthened to a bare command line specifically so this
control is falsifiable.

## Reproduce

```bash
cd dwarves-kit
bash tests/test-hooks.sh          # 282/282
bash tests/test-meta.sh           # 421/421
```

VERDICT: PASS
