#!/usr/bin/env bash
mkdir -p /private/tmp/demo/project1/_meta
git -C /private/tmp/demo/project1 init -q >/dev/null 2>&1
cd /private/tmp/demo/project1
time \
  REPO_ROOT=/private/tmp/demo/project1 \
  HARVEST_EXTRACTOR=/private/tmp/demo/demo-extractor.sh \
  HARVEST_MIN_INTERVAL=0 \
  HARVEST_STATE_DIR=/private/tmp/demo/state1 \
  claude -p "Reply with exactly OK, no tools." --model haiku \
  --setting-sources project --settings /private/tmp/demo/settings-demo-prefix.json
