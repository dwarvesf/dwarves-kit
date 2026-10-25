---
name: ci-verdict-reads-job-conclusion
description: Call a CI failure fixed only from each job's conclusion plus every TIMED OUT and FAIL line; a filtered or truncated log excerpt once hid a timeout and produced a false all-clear.
metadata:
  type: feedback
---

A `--log-failed` excerpt piped through a filter and `head` showed two new failures and cut off before the `run-all: TIMED OUT` line. The report then said a hang was gone; the next run showed it was not. **Why:** a partial log answers "what else failed", never "did this failure stop". **How to apply:** read `gh run view <id> --json jobs` for each job's conclusion first. Then grep the full failed log for `TIMED OUT`, `TIMEOUT (` and `FAIL (rc` without a line cap before claiming any suite is fixed. The test workflow runs only on dispatch and `v*` tags, so the README badge shows the last such run, not master. Related: [[pipe-tail-swallows-ci-exit-codes]] (ops-toolkit).
