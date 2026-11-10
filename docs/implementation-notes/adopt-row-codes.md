# Implementation notes -- adopt-row-codes

Delta from the brief.

- Three codes, no more: `ok`, `skip`, `fail`. The summary needs no finer split, so none was added.
- `ADOPT_CODE` defaults to `fail`. A row built without a code fails the exit status, never passes it.
- `_adopt_row <code> <text>` sets both together at each producer in `_adopt_one`. `cmd_adopt` sets a local `code` beside its own five rows: `not run`, `refused: gh is`, `skip`, `refused:`, `would adopt`.
- `adopted; <FAILED line>` is now an explicit `fail`. It failed before only because the string differed from `adopted`. Exit status is the same.
- The INT/TERM trap sets no code. It prints the summary and exits 1 itself.
- Test file: new `tests/test-wrap-adopt-codes.sh`, not a new section in `test-wrap-adopt.sh`. That suite takes about four minutes; the new one takes about 90 seconds and stays runnable alone. It copies `adopt_clone` and `adopt_apply`; sharing them would mean editing the old suite.
- `reword_adopt` in `tests/lib/wrap-stub.sh` rewords the producers only. It skips the `case "$row" in ... esac` block, so a reader that still compares words stays on the old phrases and goes red. In the fixed code that block holds no phrases, so the skip is inert.
- "Failure count" is the number of scenarios that exit non-zero. The verb exits 0 or 1, so a per-scenario comparison is the finest signal it gives.
- No existing pin changed. The 210 cases in `test-wrap-adopt.sh` pass unedited.
- Not covered by the reword: `not run` and `interrupted`. The existing signal cases (34a, 34b) cover those and are timing-heavy.
