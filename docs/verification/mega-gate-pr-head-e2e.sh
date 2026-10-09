#!/usr/bin/env bash
# mega-gate-pr-head-e2e.sh -- end-to-end leg for the mega merge gate on the PR head.
# Real pieces: lib/goal/mega-merge.sh, the real gate-ledger, the real `git fetch` from a local bare
# origin that carries refs/pull/<n>/head and a mega/x base branch. Faked: only `gh`, which answers the
# PR reads (head, base, state, changed files) and records `pr merge`. Offline. The orchestrator
# checkout stays on main throughout, the situation the gate used to misread.
# Run: bash docs/verification/mega-gate-pr-head-e2e.sh   (exit 0 = every leg as expected)
set -uo pipefail
KIT="$(cd "$(dirname "$0")/../.." && pwd)"
MM="$KIT/lib/goal/mega-merge.sh"; GL="$KIT/lib/gate/gate-ledger.sh"
export KIT_CONFIG_OPERATOR="$KIT/tests/fixtures/gates-on"
T="$(mktemp -d)"; export DWARVES_KIT_LOG_DIR="$T/log"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.org GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.org
O="$T/origin.git"; W="$T/work"; FAIL=0
git init -q --bare -b main "$O" 2>/dev/null; git init -q -b main "$W" 2>/dev/null
printf 'hello\n' > "$W/README.md"; git -C "$W" add -A; git -C "$W" commit -qm init
git -C "$W" remote add origin "$O"; git -C "$W" push -q -u origin main 2>/dev/null; git -C "$W" remote set-head origin main >/dev/null 2>&1
mk() { # <branch> <from> <path> <content> -> commit sha; the checkout returns to main
  git -C "$W" switch -q -c "$1" "$2"; mkdir -p "$W/$(dirname "$3")"; printf '%s\n' "$4" > "$W/$3"
  git -C "$W" add -A; git -C "$W" commit -qm "$1"; git -C "$W" rev-parse HEAD; git -C "$W" switch -q main
}
M="$(mk mega/x main db/migrations/0001.sql 'create table t;')"
git -C "$W" push -q origin "$M:refs/heads/mega/x" 2>/dev/null
A="$(mk pr-auth main src/auth/login.ts 'export const x = 1')"   # PR 7: a hard path, base main
R="$(mk pr-readme mega/x README.md 'wave change')"              # PR 8: README only, base mega/x
git -C "$W" push -q origin "$A:refs/pull/7/head" "$R:refs/pull/8/head" 2>/dev/null

# fake gh: answers the PR reads from per-PR tables, records `pr merge`
mkdir -p "$T/bin"; GHLOG="$T/gh.log"
cat > "$T/bin/gh" <<SH
#!/usr/bin/env bash
case "\$1 \$2 \$3" in
  "pr view 7"|"pr view 8")
    case "\$*" in
      *headRefOid*) [ "\$3" = 7 ] && echo $A || echo $R ;;
      *baseRefName*) [ "\$3" = 7 ] && echo main || echo mega/x ;;
      *isDraft*) printf 'false\037\037clear PR\n' ;;
    esac ;;
  "pr merge "*) echo "\$*" >> "$GHLOG" ;;
  *) case "\$1 \$2" in
       "api repos/{owner}/{repo}/pulls/7/files") echo src/auth/login.ts ;;
       "api repos/{owner}/{repo}/pulls/8/files") echo README.md ;;
     esac ;;
esac
SH
chmod +x "$T/bin/gh"

# the real ledger: a normal-lane run with every normal gate recorded (no full-lane gates)
RID=e2e-rid
bash "$GL" start "$RID" normal normal feature feature testrepo >/dev/null 2>&1
while IFS= read -r g; do [ -n "$g" ] && bash "$GL" record "$RID" "$g" ran e2e >/dev/null 2>&1; done < <(bash "$GL" required normal)

leg() { # <label> <pr> <expect-exit> <expect-text> [expect-merge 0|1]
  local out rc; : > "$GHLOG"
  out="$(cd "$W" && PATH="$T/bin:$PATH" MEGA_MERGE_ROOT="$W" bash "$MM" merge "$2" "$RID" normal --execute 2>&1)"; rc=$?
  local merged=0; grep -q "^pr merge $2 " "$GHLOG" && merged=1
  if [ "$rc" = "$3" ] && printf '%s' "$out" | grep -qF -- "$4" && [ "$merged" = "${5:-0}" ]; then echo "ok - $1 (exit $rc, merged=$merged)"
  else echo "NOT ok - $1: exit $rc merged=$merged"; FAIL=1; fi
  printf '%s\n' "$out" | sed 's/^/    | /' | head -8
}
echo "checkout on: $(git -C "$W" rev-parse --abbrev-ref HEAD); origin carries: $(git -C "$O" for-each-ref --format='%(refname)' refs/pull refs/heads | tr '\n' ' ')"
leg "PR 7 touches src/auth, base main: refused on the hard path" 7 1 'hard path (auth: src/auth/login.ts'
leg "PR 8 README-only on mega/x: merges despite mega/x's earlier migration" 8 0 "EXECUTING: gh pr merge 8 --squash --delete-branch --match-head-commit $R" 1
echo "private refs left: [$(git -C "$W" for-each-ref refs/kit)]"
git -C "$W" push -q -f origin "$A:refs/pull/8/head" 2>/dev/null
leg "PR 8 head moves after the pin: refused" 8 1 'head moved after it was pinned'
exit "$FAIL"
