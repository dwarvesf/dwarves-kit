#!/usr/bin/env python3
"""Mutator for the wrap-step0-scope negative controls (SPEC-383).

Usage: wrap-step0-scope-negctl.py <nc1|nc2|nc3|nc4>

Run through negctl, from the repo root, after the change is committed:
  bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap-apply.sh" \
    "python3 docs/verification/wrap-step0-scope-negctl.py nc1"
nc4 pairs with tests/test-wrap-carry.sh. Each mutation must match exactly once.
"""
import sys

MUTATIONS = {
    "nc1": ("lib/wrap/wrap-apply.sh",
            '"-- pull:"\n  if [ "$NO_PULL" = 1 ]; then',
            '"-- pull:"\n  if [ "$NO_PULL" = 99 ]; then'),
    "nc2": ("lib/wrap/wrap-apply.sh",
            '    if [ "$NO_PULL" = 1 ]; then\n      echo "-- stray commits:"',
            '    if [ "$NO_PULL" = 99 ]; then\n      echo "-- stray commits:"'),
    "nc3": ("lib/wrap/wrap-apply.sh",
            '  if [ "$PULL_ONLY" = 1 ] && [ "$NO_PULL" = 1 ]; then',
            '  if [ "$PULL_ONLY" = 99 ] && [ "$NO_PULL" = 1 ]; then'),
    "nc4": ("lib/wrap/wrap-carry.sh",
            '  [ "$NO_PULL" != 1 ] || return 1',
            '  :'),
}

name = sys.argv[1] if len(sys.argv) > 1 else ""
if name not in MUTATIONS:
    sys.exit("usage: wrap-step0-scope-negctl.py nc1|nc2|nc3|nc4")
path, old, new = MUTATIONS[name]
text = open(path).read()
if text.count(old) != 1:
    sys.exit("match count %d for %s, expected 1" % (text.count(old), name))
open(path, "w").write(text.replace(old, new))
