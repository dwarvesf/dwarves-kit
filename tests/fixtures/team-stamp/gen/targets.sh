#!/usr/bin/env bash
# Fixture generator: prints the merged target list of every group.
printf '# Targets\n\n'
sed 's/^/- /' "$STAMP_ALL_TARGETS_FILE"
