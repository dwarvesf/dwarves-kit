---
name: ubuntu-latest-is-uutils
description: GitHub's ubuntu-latest now runs Ubuntu 26.04 with Rust uutils coreutils and a multibyte awk; byte-level awk and early-exit pipes that pass on 24.04 and macOS break there.
metadata:
  type: project
---

`ubuntu-latest` moved to Ubuntu 26.04 (the job log prints `Image: ubuntu-26.04`). Two behaviours differ from 24.04 and macOS. First, coreutils are uutils: `tr` writes eagerly and dies of SIGPIPE when `grep -q` exits early, so `cmd | tr | grep -q` under `pipefail` fails about three runs in four. Capture output, then match with `case`. Second, awk is multibyte-aware in a UTF-8 locale: `substr(line,1,3)` counts characters, so a 3-byte BOM compare never matches. Use `index(line, BOM) == 1` and `substr(line, 1+length(BOM))`. A 24.04 container reproduces neither; use a 26.04 image. Related: [[pin-uv-python-for-native-wheels]].
