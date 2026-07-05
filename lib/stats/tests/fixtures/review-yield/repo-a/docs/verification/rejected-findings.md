# Rejected findings ledger (fixture)

## Format

| date | lens | finding-key | verdict | reason |
|---|---|---|---|---|
| YYYY-MM-DD | \<lens\> | `<defect-slug>:<file-path>` | rejected | \<reason\> |

## Rows

| date | lens | finding-key | verdict | reason |
|---|---|---|---|---|
| 2026-01-01 | security | sql-injection:foo.py | rejected | parameterized already, false positive |
| 2026-01-05 | security | xss:bar.py | rejected | output is escaped downstream |
| 2026-01-10 | architecture | god-object:baz.py | rejected | intentional single-file design |
| 2026-01-11 | architecture | too-few-cells |
| 2026-01-12 | test-coverage | flaky-test:qux.py | accepted | not actually rejected, wrong verdict |
| 2026-03-01 | test-coverage | missing-mock:a.py | rejected | mock intentionally omitted |
| 2026-03-02 | test-coverage | missing-mock:b.py | rejected | mock intentionally omitted |
| 2026-03-03 | test-coverage | missing-mock:c.py | rejected | mock intentionally omitted |
| 2026-03-04 | test-coverage | missing-mock:d.py | rejected | mock intentionally omitted |
| 2026-03-05 | test-coverage | missing-mock:e.py | rejected | mock intentionally omitted |
| 2026-03-06 | test-coverage | missing-mock:f.py | rejected | mock intentionally omitted |
