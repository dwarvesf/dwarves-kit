#!/usr/bin/env python3
"""One mutation per negative control for docs/verification/wrap-merge-stacked-ci.md.

Usage: python3 docs/verification/wrap-merge-stacked-ci/negctl-mutations.py NC<n>
Run from the repo root (negctl runs it in its throwaway copy). Each control replaces one
exact string in lib/wrap/wrap-merge.sh and fails loudly when the string is not found exactly
once, so a mutation can never be a silent no-op.
"""
import sys

F = "lib/wrap/wrap-merge.sh"

MUTATIONS = {
    # The cut point: replay every commit above the merge base instead of only the child's own.
    "NC1": ('rebase --onto "origin/${def}" "$parent" >/dev/null',
            'rebase "origin/${def}" >/dev/null'),
    # The lease: a plain force overwrites whatever another writer pushed.
    "NC2": ('"--force-with-lease=refs/heads/${branch}:${head_oid}" origin',
            '--force origin'),
    # The conflict abort: leave the rebase stopped in the checkout.
    "NC3": ("sed 's/,/, /g')\"\n    git -C \"$wt\" rebase --abort >/dev/null 2>&1\n    if [",
            "sed 's/,/, /g')\"\n    if ["),
    # The opt-in: run the stacked recovery without --rebase-stacked.
    "NC4": ('if [ "$stacked" = 1 ] && [ "$verdict" = "SKIP not mergeable (CONFLICTING)" ]; then',
            'if [ "$verdict" = "SKIP not mergeable (CONFLICTING)" ]; then'),
    # The dependents guard: rewrite a branch other PRs still target.
    "NC5": ('  if [ -n "$dep" ]; then', '  if false; then'),
    # The fork and auto-merge guard.
    "NC6": ('.isCrossRepository == false and has("autoMergeRequest") and .autoMergeRequest == null',
            'true'),
    # The chain tip: take the first merged parent instead of the tip-most one.
    "NC7": ('[ "$ok" = 1 ] && { best="$i"; break; }', 'best="$i"; break'),
    # The zero-check label sync: the call never happens.
    "NC8": ('  _ci_label_sync "$url" "$n"; rc=$?\n  case "$rc" in\n    0)\n      _ci_checks_wait',
            '  rc=1\n  case "$rc" in\n    0)\n      _ci_checks_wait'),
    # One sync under --with-ci: the armed flag never reaches the gate-on block.
    "NC9": ('      PREP_ARMED=1\n', '      PREP_ARMED=\n'),
}

if len(sys.argv) != 2 or sys.argv[1] not in MUTATIONS:
    sys.exit("usage: negctl-mutations.py " + "|".join(MUTATIONS))
old, new = MUTATIONS[sys.argv[1]]
src = open(F).read()
if src.count(old) != 1:
    sys.exit("%s: expected exactly one match in %s, found %d" % (sys.argv[1], F, src.count(old)))
open(F, "w").write(src.replace(old, new))
