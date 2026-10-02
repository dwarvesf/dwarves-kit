#!/usr/bin/env python3
"""Mutator for the wrap-step0-scope negative controls (SPEC-383).

Usage: wrap-step0-scope-negctl.py <nc1|nc2|nc3|nc4|nc5|nc6|nc7|nc8>

Run through negctl, from the repo root, after the change is committed:
  bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap-apply.sh" \
    "python3 docs/verification/wrap-step0-scope-negctl.py nc1"
nc4 and nc8 pair with tests/test-wrap-carry.sh, nc5 and nc6 with tests/test-wrap-merge.sh, nc1 to nc3 and nc7 with tests/test-wrap-apply.sh. Each mutation must match exactly once.
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
            '      if [ "$NO_PULL" = 1 ]; then\n        # A step 0 stop: these lines',
            '      if [ "$NO_PULL" = 99 ]; then\n        # A step 0 stop: these lines'),
    "nc5": ("lib/wrap/wrap-merge.sh",
            '    if [ "$NO_PULL" = 1 ] && [ -n "$head" ] && _main_holds_branch "$repo" "$head"; then',
            '    if [ "$NO_PULL" = 99 ] && [ -n "$head" ] && _main_holds_branch "$repo" "$head"; then'),
    "nc6": ("lib/wrap/wrap-merge.sh",
            '      if [ -n "$pr_head" ] && _main_holds_branch "$repo" "$pr_head"; then',
            '      if false && [ -n "$pr_head" ] && _main_holds_branch "$repo" "$pr_head"; then'),
    "nc7": ("lib/wrap/wrap-apply.sh",
            '    if [ "$NO_PULL" = 1 ] && [ -z "$OWN_SET" ]; then\n      echo "-- branches:"',
            '    if [ "$NO_PULL" = 99 ] && [ -z "$OWN_SET" ]; then\n      echo "-- branches:"'),
    "nc8": ("lib/wrap/wrap-carry.sh",
            'git -C "$repo" diff-index --name-only -z HEAD',
            'git -C "$repo" diff HEAD --name-only -z'),
}

name = sys.argv[1] if len(sys.argv) > 1 else ""
if name not in MUTATIONS:
    sys.exit("usage: wrap-step0-scope-negctl.py nc1|nc2|nc3|nc4|nc5|nc6|nc7|nc8")
path, old, new = MUTATIONS[name]
text = open(path).read()
if text.count(old) != 1:
    sys.exit("match count %d for %s, expected 1" % (text.count(old), name))
open(path, "w").write(text.replace(old, new))
