---
name: ci-runner-has-no-procps
description: A CI runner image can lack kill, pgrep, ps and rsync, so a test that runs one passes on a laptop and fails in CI.
---

A slim CI runner image may ship no procps. `kill`, `pgrep` and `ps` then do not exist as programs (`which pgrep ps` exits 1), and `rsync` can be missing too. A test that ran one of them passed on a laptop and failed on the first runner run.

**Why:** a laptop always has these tools, so a local green run proves nothing about the runner.

**How to apply:** in a test, or a script a test runs, never run `kill`, `pgrep`, `ps` or `rsync` as a program. Use the shell built-in `kill -0 <pid>`, a marker file a surviving child would leave, or `cp -Rp` and `find`. A test that fails only in CI: suspect a missing tool first, then check the image.
