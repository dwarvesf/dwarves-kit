# Negative-control mutations for SPEC-359 (wrap apply --pull-only), one per PULL_ONLY gate.
# Run from the repo root: bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap-pull.sh" "python3 docs/verification/wrap-pull-only-negctl.py N1"
# Each target must match exactly once, so a drifted line fails loudly instead of mutating nothing.
# The gates live in the wrap modules: N3 in wrap-common.sh (run()), the rest in wrap-apply.sh.
import sys
n=sys.argv[1]; p='lib/wrap/wrap-common.sh' if n=='N3' else 'lib/wrap/wrap-apply.sh'; s=open(p).read()
M={
 'N1':('if [ "$PULL_ONLY" != 1 ]; then','if [ "$PULL_ONLY" != 99 ]; then',1),
 'N2':('if [ "$PULL_ONLY" = 1 ] && [ "$fetch_ok" = 1 ]; then','if [ "$PULL_ONLY" = 99 ] && [ "$fetch_ok" = 1 ]; then',1),
 'N3':('[ "$PULL_ONLY" = 1 ] && [ "$APPLY" = 1 ] && FAILURES=1','[ "$PULL_ONLY" = 99 ] && [ "$APPLY" = 1 ] && FAILURES=1',1),
 'N4':('    [ "$PULL_ONLY" = 1 ] && FAILURES=1\n','    [ "$PULL_ONLY" = 99 ] && FAILURES=1\n',1),
 'N6':('(fetch failed; the pull below will likely fail too)','(fetch failed; every delete is skipped)',1),
}
if n=='N5':
    out=[]; c=0
    for line in s.split('\n'):
        if 'cannot combine with' in line and line.lstrip().startswith('if ['):
            line=line.replace('if [','if false && [',1); c+=1
        out.append(line)
    assert c==4, c; s='\n'.join(out)
else:
    a,b,k=M[n]; assert s.count(a)==k,(n,s.count(a)); s=s.replace(a,b)
open(p,'w').write(s)
