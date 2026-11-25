#!/usr/bin/env bash
# test-stamp-ci.sh -- the ci group of the team stamp: .github/workflows/ci.yml, scripts/check.sh and its
# generated test. Stamps the group into temp repos, then checks:
#   AC11  the workflow runs on [self-hosted] only, and its template text names no hosted runner label;
#         actionlint accepts the rendered file when it is installed
#   AC12  the twin set (the gate commands) is declared at the top of ci.yml and check.sh, is not empty,
#         and every member appears in both with the same inputs
#   the pins: every action by full commit sha with its tag, the shellcheck release by tag and by the
#         sha256 of each build in the scan-safe shape sha256=<hex>
#   the steps themselves, run from the rendered file: the shellcheck install (digest match, digest
#         mismatch, each platform, sha256sum or shasum -a 256), the gate scripts taken from the base
#         revision, the path filter
# Run one narrow suite: bash tests/test-stamp-ci.sh. STAMP_CI_ONLINE=1 also compares the pinned digests
# with the release metadata (needs gh and network).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
expect() { # expect <label> <command...>
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi
}
refute() { # refute <label> <command...>: the command must fail
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then no "$label"; else ok "$label"; fi
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-stamp-ci.XXXXXX")" || exit 1
KIT_PATTERN='\.claude/dwarves-kit|CLAUDE_PLUGIN_ROOT|KIT_ROOT|lib/gate/|/bin/(gate|classify|wrap|board)([^A-Za-z0-9_-]|$)|/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+'
TPL="$ROOT/templates/team-stamp/files/.github/workflows/ci.yml.tpl"
newrepo() { local d; d="$(mktemp -d "$WORK/r.XXXXXX")" && git -C "$d" init -q 2>/dev/null && echo "$d"; }
gi() { git -C "$1" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null "${@:2}"; }
have_shellcheck() { command -v shellcheck >/dev/null 2>&1; }
code_lines() { grep -Ev '^[[:space:]]*#' "$1"; } # a file without its comment lines

# ---- the checks, as functions: each runs on the real file and on a planted copy (negative control)
runner_labels_ok() { # every runs-on is [self-hosted] and nothing names a hosted runner
  local f="$1" cnt bad
  cnt="$(code_lines "$f" | grep -c 'runs-on:')"
  bad="$(code_lines "$f" | grep 'runs-on:' | grep -vc '^    runs-on: \[self-hosted\]$')"
  [ "$cnt" -ge 2 ] && [ "$bad" -eq 0 ] && ! grep -Eiq 'ubuntu-|macos-|windows-' "$f"
}
no_untrusted_in_script() { # a ${{ }} expression only ever sits in a "key: ${{ expr }}" entry
  ! code_lines "$1" | grep -F '${{' | grep -Evq '^[[:space:]]+[A-Za-z_][A-Za-z0-9_-]*: \$\{\{ [^}]+ \}\}$'
}
pins_ok() { # every uses: is owner/name@<40 hex> # <tag>
  local f="$1" cnt bad
  cnt="$(code_lines "$f" | grep -c 'uses:')"
  bad="$(code_lines "$f" | grep 'uses:' | grep -Evc '^      - uses: [A-Za-z0-9._/-]+@[0-9a-f]{40} # v[0-9][0-9.]*$')"
  [ "$cnt" -ge 2 ] && [ "$bad" -eq 0 ]
}
hex_ok() { # a 64-hex run only after sha256=; a 40-hex run only in a pinned uses: line
  local f="$1" rest
  rest="$(sed -E 's/sha256[=:] ?[0-9a-f]{64}//g' "$f" | grep -E '[0-9a-f]{40}' | grep -Evc '^      - uses: [A-Za-z0-9._/-]+@[0-9a-f]{40} # v')"
  [ "$rest" -eq 0 ]
}
twin_entries() { sed -n 's/^#   twin: //p' "$1"; } # the declared set of a file
# step_run <workflow> <step name>: the run: text of the step, with the block indent removed
step_run() {
  awk -v want="$2" '
    function indent(s) { match(s, /^ */); return RLENGTH }
    grab && length($0) > indent($0) && indent($0) <= 6 { exit }
    !grab && /^      - / { step = 0 }
    !grab && $0 == "      - name: " want { step = 1; next }
    step && /^        run: \|$/ { grab = 1; next }
    step && /^        run: / { sub(/^        run: /, ""); print; exit }
    grab { sub(/^          /, ""); print }' "$1"
}
# step_env <workflow> <step name>: the env entry names of the step
step_env() {
  awk -v want="$2" '
    function indent(s) { match(s, /^ */); return RLENGTH }
    /^      - / { if (grab) exit; step = 0 }
    $0 == "      - name: " want { step = 1; next }
    step && /^        env:$/ { grab = 1; next }
    grab && indent($0) == 10 { sub(/^ +/, ""); sub(/:.*/, ""); print; next }
    grab && indent($0) < 10 && length($0) > indent($0) { exit }' "$1"
}
# twin_ok <ci.yml> <check.sh>: the declared sets match, are not empty, and each member runs in both
twin_ok() {
  local ci="$1" ck="$2" entries name envs e line step_name found
  entries="$(twin_entries "$ci")"
  [ -n "$entries" ] || return 1
  [ "$(printf '%s\n' "$entries" | sort)" = "$(twin_entries "$ck" | sort)" ] || return 1
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    name="${line%% *}"
    envs=""
    case "$line" in *" env "*) envs="${line#* env }" ;; esac
    case "$name" in
    *\**)
      code_lines "$ci" | grep -Fq "for t in scripts/$name; do" || return 1
      code_lines "$ck" | grep -Fq "for t in scripts/$name; do" || return 1
      ;;
    *)
      code_lines "$ci" | grep -F "$name" | grep -Eq 'bash' || return 1
      found="$(code_lines "$ck" | grep -F "bash scripts/$name")" || return 1
      for e in $envs; do
        printf '%s\n' "$found" | grep -Fq "$e=" || return 1
        step_name="$(awk -v n="$name" '/^      - name: / { s = substr($0, 15) } index($0, n) && /bash/ && !/^ *#/ { print s; exit }' "$ci")"
        step_env "$ci" "$step_name" | grep -Fxq "$e" || return 1
      done
      ;;
    esac
  done <<EOF
$entries
EOF
  # the other way: every script a ci.yml gate line names is in the declared set
  code_lines "$ci" | grep -E 'bash |for t in ' | grep -Eo '[A-Za-z0-9._*-]+\.sh' | sort -u | while IFS= read -r s; do
    printf '%s\n' "$entries" | grep -Eq "^$(printf '%s' "$s" | sed 's/[*.]/\\&/g') " || printf '%s\n' "$entries" | grep -Fxq "$s" || echo "undeclared $s"
  done | { ! grep -q undeclared; }
}

# 1. a stamp with non-default values, and one with the defaults
A="$(newrepo)"
RC=0
bash lib/stamp.sh --only ci,pr-shape,owners --default-branch master --owner testowner --tags app,lib --product-paths app/,pkg/ "$A" >"$WORK/stamp-a.out" 2>&1 || RC=$?
expect "stamp of the ci group exits 0" [ "$RC" -eq 0 ]
for f in scripts/check.sh scripts/test-check.sh .github/workflows/ci.yml; do
  expect "created $f" grep -qx "created: $f" "$WORK/stamp-a.out"
  expect "$f is listed in the lock" grep -q "^file $f ci sha256:" "$A/.claude/team-stamp.lock"
done
expect "scripts/check.sh is executable" test -x "$A/scripts/check.sh"
expect "scripts/test-check.sh is executable" test -x "$A/scripts/test-check.sh"
expect "no {{KEY}} is left in a generated file" bash -c "! grep -rE '\{\{[A-Za-z_]+\}\}' '$A/scripts/check.sh' '$A/scripts/test-check.sh' '$A/.github/workflows/ci.yml'"
bash lib/stamp.sh --only ci,pr-shape,owners "$A" >"$WORK/stamp-a2.out" 2>&1
expect "the second run prints only unchanged lines" bash -c '! grep -Ev "^(unchanged|using): " "$1" | grep -q .' _ "$WORK/stamp-a2.out"
expect "--check is clean" bash lib/stamp.sh --only ci,pr-shape,owners --check "$A"
B="$(newrepo)"
bash lib/stamp.sh --only ci --default-branch main "$B" >/dev/null 2>&1
CIA="$A/.github/workflows/ci.yml"; CKA="$A/scripts/check.sh"
CIB="$B/.github/workflows/ci.yml"; CKB="$B/scripts/check.sh"
expect "the manifest has the three rows of the group" bash -c "[ \$(grep -vc '^#' templates/team-stamp/manifest.d/85-ci.tsv) -eq 3 ]"

# 2. stamped values; nothing typed in the files
expect "check.sh takes the default branch from the stamp" grep -qxF "DEFAULT_BRANCH='master'" "$CKA"
expect "check.sh takes the product filter from the stamp" grep -qxF "product_re='^(app/|pkg/)'" "$CKA"
expect "ci.yml takes the same product filter from the stamp" grep -qF "product_re='^(app/|pkg/)'" "$CIA"
expect "no literal main branch in check.sh" bash -c "! grep -Eq 'origin/main|[^a-z]main[^a-z]' '$CKA'"
expect "ci.yml is byte-identical but for the product filter" bash -c "diff <(sed 's/product_re=.*/F/' '$CIA') <(sed 's/product_re=.*/F/' '$CIB') >/dev/null"

# 3. AC11: the runner label, on the template text and the rendered file; a planted hosted label is caught
expect "AC11: the template text has runs-on [self-hosted] only, and no hosted label" runner_labels_ok "$TPL"
expect "AC11: the rendered workflow has runs-on [self-hosted] only, and no hosted label" runner_labels_ok "$CIA"
sed 's/^    runs-on: \[self-hosted\]$/    runs-on: ubuntu-latest/' "$TPL" >"$WORK/planted1.yml"
refute "AC11: a planted ubuntu-latest in the workflow text is caught" runner_labels_ok "$WORK/planted1.yml"
{ cat "$TPL"; printf '  # runs on macos-14 here\n'; } >"$WORK/planted2.yml"
refute "AC11: a hosted label in a comment is caught too" runner_labels_ok "$WORK/planted2.yml"
sed 's/^    runs-on: \[self-hosted\]$/    runs-on: [self-hosted, pool]/' "$TPL" >"$WORK/planted3.yml"
refute "AC11: a second label is caught" runner_labels_ok "$WORK/planted3.yml"
if command -v actionlint >/dev/null 2>&1; then
  RC=0; actionlint "$CIA" >"$WORK/actionlint.out" 2>&1 || RC=$?
  expect "AC11: actionlint accepts the rendered workflow" [ "$RC" -eq 0 ]
  [ "$RC" -eq 0 ] || sed 's/^/    /' "$WORK/actionlint.out"
else
  ok "actionlint is not installed, the rendered workflow was not linted"
fi

# 4. structure: permissions, trigger, jobs, the job name pr-merge.sh waits for
expect "permissions: contents: read at the top, and nothing else in the block" bash -c "awk '/^permissions:/ { p = 1; next } p && /^  / { n++; if (\$0 != \"  contents: read\") bad = 1; next } p { exit } END { exit (bad || n != 1) }' '$CIA'"
expect "the trigger is pull_request" grep -qx '  pull_request:' "$CIA"
expect "no pull_request_target and no workflow_dispatch" bash -c "! grep -Eq 'pull_request_target|workflow_dispatch' '$CIA'"
expect "the job changes exists" grep -qx '  changes:' "$CIA"
expect "the job pr-shape exists" grep -qx '  pr-shape:' "$CIA"
job_text() { awk -v j="$2" '$0 == "  " j ":" { g = 1; next } g && /^  [a-z#]/ { exit } g' "$1"; }
for j in changes pr-shape; do
  expect "the job $j runs only for a pull request from this repo (fork guard)" bash -c "$(declare -f job_text); job_text '$CIA' $j | grep -qxF '    if: github.event.pull_request.head.repo.full_name == github.repository'"
done
expect "the workflow has exactly the two gate jobs, and no tests job" bash -c "[ \$(grep -c '^  [a-z][a-z-]*:\$' '$CIA') -eq 2 ] && ! grep -qx '  tests:' '$CIA'"
expect "no step of the workflow runs a script of the pull request's tests" bash -c "! grep -v '^ *#' '$CIA' | grep -q 'scripts/test-'"
expect "no step of the workflow runs a loop over the pull request's files" bash -c "! grep -v '^ *#' '$CIA' | grep -Eq 'for t in|bash \"\\\$t\"'"
expect "the stub says a job that runs the pull request's code needs its own runner label or a container job" bash -c "grep -q 'SEPARATE runner label or in a container job' '$CIA' && grep -q 'never on' '$CIA'"
expect "the pr-shape job runs none of the pull request's scripts/test-*.sh" bash -c "$(declare -f job_text); ! job_text '$CIA' pr-shape | grep -q 'scripts/test-'"
expect "the changes job runs none of the pull request's scripts/test-*.sh" bash -c "$(declare -f job_text); ! job_text '$CIA' changes | grep -q 'scripts/test-'"
expect "neither gate job executes a file from the checkout except through git show" bash -c "$(declare -f job_text); for j in changes pr-shape; do job_text '$CIA' \$j | grep -E '^ +(run: )?(bash|sh|source|\\.) ' | grep -vE 'bash -c \"\\\$\(cat \"\\\$RUNNER_TEMP/gate/check-owners.sh\"\)\"|bash \"\\\$RUNNER_TEMP/gate/pr-shape.sh\"' | grep -q . && exit 1; done; exit 0"
expect "the header says the workflow file itself comes from the pull request" grep -q 'a pull request can edit THIS file' "$CIA"
expect "the header says a job that runs PR code needs a separate runner, and not for public repos" bash -c "grep -q 'separate runner label or in a container job' '$CIA' && grep -q 'Not for public repos' '$CIA'"
expect "the header says a skipped job leaves its check missing and the merge guard refuses" grep -q 'A skipped job leaves its check' "$CIA"
expect "the changes job exposes the product output" grep -qF 'product: ${{ steps.filter.outputs.product }}' "$CIA"
expect "the end of the file shows where the repo's own jobs go" grep -q 'own build and test jobs go here' "$CIA"
expect "the pr-shape job gets the title and body through env: entries" bash -c "grep -qxF '          PR_TITLE: \${{ github.event.pull_request.title }}' '$CIA' && grep -qxF '          PR_BODY: \${{ github.event.pull_request.body }}' '$CIA'"
expect "no pull request text is interpolated into script text" no_untrusted_in_script "$CIA"
{ cat "$TPL"; printf '      - run: echo ${{ github.event.pull_request.title }}\n'; } >"$WORK/planted4.yml"
refute "a planted interpolation of the title into a run line is caught" no_untrusted_in_script "$WORK/planted4.yml"

# 5. the pins
expect "every uses: is pinned by a full commit sha with its tag after it" pins_ok "$TPL"
sed 's/@[0-9a-f]\{40\} #/@v4 #/' "$TPL" >"$WORK/planted5.yml"
refute "a uses: pinned by a tag only is caught" pins_ok "$WORK/planted5.yml"
expect "the template carries no placeholder pin" bash -c "! grep -Eiq 'PLACEHOLDER|UNPINNED|@@|TODO|FIXME' '$TPL'"
expect "the release tag of shellcheck is recorded in the header" grep -Eq '^# Pinned here: shellcheck v[0-9.]+,' "$TPL"
expect "the version the job downloads is the recorded tag" bash -c "t=\$(sed -n 's/^# Pinned here: shellcheck v\\([0-9.]*\\),.*/\\1/p' '$TPL'); [ -n \"\$t\" ] && grep -qF \"SHELLCHECK_VERSION: \\\"\$t\\\"\" '$TPL'"
expect "four digests, each written sha256=<64 hex>" bash -c "[ \$(grep -Eo 'sha256=[0-9a-f]{64}' '$TPL' | sort -u | wc -l) -eq 4 ]"
expect "no bare hex run outside sha256= and a pinned uses: line (template)" hex_ok "$TPL"
expect "no bare hex run outside sha256= and a pinned uses: line (rendered)" hex_ok "$CIA"
printf 'x: %s\n' "$(printf '%064d' 0 | tr 0 a)" >"$WORK/bare.txt"
printf 'x: sha256=%s\n' "$(printf '%064d' 0 | tr 0 a)" >"$WORK/marked.txt"
refute "the hex scan catches a bare digest (self-test)" hex_ok "$WORK/bare.txt"
expect "the hex scan allows a marked digest (self-test)" hex_ok "$WORK/marked.txt"
if [ "${STAMP_CI_ONLINE:-}" = 1 ] && command -v gh >/dev/null 2>&1; then
  ver="$(sed -n 's/^# Pinned here: shellcheck \(v[0-9.]*\),.*/\1/p' "$TPL")"
  gh api "repos/koalaman/shellcheck/releases/tags/$ver" --jq '.assets[] | select(.name | endswith(".tar.gz")) | .digest' 2>/dev/null | sed 's/^sha256:/sha256=/' >"$WORK/online.txt"
  expect "online: each pinned digest is in the release metadata" bash -c "[ -s '$WORK/online.txt' ] && for d in \$(grep -Eo 'sha256=[0-9a-f]{64}' '$TPL'); do grep -qxF \"\$d\" '$WORK/online.txt' || exit 1; done"
else
  ok "online digest comparison skipped (set STAMP_CI_ONLINE=1 with gh and network)"
fi

# 6. the shellcheck install step, run from the rendered file with a fake curl and uname
SC_RUN="$WORK/install.sh"
step_run "$CIA" "Install pinned shellcheck" >"$SC_RUN"
expect "the install step was extracted" test -s "$SC_RUN"
VER="$(sed -n 's/^# Pinned here: shellcheck v\([0-9.]*\),.*/\1/p' "$CIA")"
hasher="$(command -v sha256sum 2>/dev/null || command -v shasum)"
mkbin() { # mkbin <dir> <tool>...
  local d="$1" t p; shift; mkdir -p "$d"
  for t in "$@"; do p="$(command -v "$t" 2>/dev/null)" && case "$p" in /*) ln -sf "$p" "$d/$t";; esac; done
}
fake_curl() { # fake_curl <dir>: a curl that copies $FAKE_TARBALL to the -o target and logs the url
  cat >"$1/curl" <<'EOF'
#!/bin/sh
out=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in -o) out="$2"; shift;; --retry) shift;; -*) ;; *) url="$1";; esac
  shift
done
echo "$url" >> "$FAKE_LOG"
cp "$FAKE_TARBALL" "$out"
EOF
  chmod +x "$1/curl"
}
fake_uname() { # fake_uname <dir>: uname -s and uname -m answer from FAKE_S and FAKE_M
  cat >"$1/uname" <<'EOF'
#!/bin/sh
case "$1" in -s) echo "$FAKE_S";; -m) echo "$FAKE_M";; *) echo "$FAKE_S";; esac
EOF
  chmod +x "$1/uname"
}
digest_of() { if [ "$(basename "$hasher")" = sha256sum ]; then "$hasher" "$1" | cut -d' ' -f1; else "$hasher" -a 256 "$1" | cut -d' ' -f1; fi; }
make_tarball() { # make_tarball <out.tar.gz>: shellcheck-v<ver>/shellcheck, a script that prints a version
  local d="$WORK/tb.$$.$RANDOM"
  mkdir -p "$d/shellcheck-v$VER"
  printf '#!/bin/sh\necho fake shellcheck\n' >"$d/shellcheck-v$VER/shellcheck"
  chmod +x "$d/shellcheck-v$VER/shellcheck"
  tar -czf "$1" -C "$d" "shellcheck-v$VER"
}
TARBALL="$WORK/fake.tar.gz"
make_tarball "$TARBALL"
FAKE_DIGEST="$(digest_of "$TARBALL")"
# run_install <name> <uname -s> <uname -m> <sha tool: sha256sum|shasum> <script>: result in $irc, logs in $WORK/<name>.*
run_install() {
  local name="$1" s="$2" m="$3" tool="$4" script="$5" bin="$WORK/bin-$1"
  mkdir -p "$bin" "$WORK/rt-$name"
  mkbin "$bin" bash cat mkdir tar gzip cp dirname basename rm sh echo printf
  fake_curl "$bin"; fake_uname "$bin"
  if [ "$tool" = sha256sum ]; then
    printf '#!/bin/sh\nif [ "$(basename "%s")" = sha256sum ]; then exec "%s" "$@"; else exec "%s" -a 256 "$@"; fi\n' "$hasher" "$hasher" "$hasher" >"$bin/sha256sum"
    chmod +x "$bin/sha256sum"
  else
    printf '#!/bin/sh\n[ "$1" = "-a" ] && [ "$2" = "256" ] || { echo "shasum called without -a 256" >&2; exit 9; }\nshift 2\nif [ "$(basename "%s")" = sha256sum ]; then exec "%s" "$@"; else exec "%s" -a 256 "$@"; fi\n' "$hasher" "$hasher" "$hasher" >"$bin/shasum"
    chmod +x "$bin/shasum"
  fi
  : >"$WORK/gp-$name"
  : >"$WORK/log-$name"
  irc=0
  env -i PATH="$bin" RUNNER_TEMP="$WORK/rt-$name" GITHUB_PATH="$WORK/gp-$name" SHELLCHECK_VERSION="$VER" \
    FAKE_S="$s" FAKE_M="$m" FAKE_TARBALL="$TARBALL" FAKE_LOG="$WORK/log-$name" \
    bash "$script" >"$WORK/$name.out" 2>"$WORK/$name.err" || irc=$?
}
# pinned_for <platform>: the digest the step pins for a platform
repin() { # repin <platform> <hex> <in> <out>: the step with that platform's digest replaced
  sed -E "/platform=\"$1\"/ s/sha256=[0-9a-f]{64}/sha256=$2/" "$3" >"$4"
}
n=0
for row in "Linux x86_64 linux.x86_64" "Linux aarch64 linux.aarch64" "Linux arm64 linux.aarch64" "Darwin x86_64 darwin.x86_64" "Darwin arm64 darwin.aarch64" "Darwin aarch64 darwin.aarch64"; do
  set -- $row
  s="$1"; m="$2"; plat="$3"; n=$((n + 1))
  # a build whose digest differs from the pin fails the job
  run_install "bad$n" "$s" "$m" sha256sum "$SC_RUN"
  expect "$s $m: a build with a different digest fails the job" [ "$irc" -ne 0 ]
  expect "$s $m: the mismatch message names the asset" grep -q "the digest of shellcheck-v$VER.$plat.tar.gz is sha256=" "$WORK/bad$n.err"
  expect "$s $m: a mismatch leaves GITHUB_PATH untouched" test ! -s "$WORK/gp-bad$n"
  expect "$s $m: the asset is picked by platform" grep -qF "koalaman/shellcheck/releases/download/v$VER/shellcheck-v$VER.$plat.tar.gz" "$WORK/log-bad$n"
  # the same build with its digest pinned passes, with either hash tool
  repin "$plat" "$FAKE_DIGEST" "$SC_RUN" "$WORK/install-ok$n.sh"
  run_install "okA$n" "$s" "$m" sha256sum "$WORK/install-ok$n.sh"
  expect "$s $m: a matching digest passes (sha256sum)" [ "$irc" -eq 0 ]
  expect "$s $m: the tool dir is put on GITHUB_PATH" grep -q "shellcheck-install/shellcheck-v$VER\$" "$WORK/gp-okA$n"
  expect "$s $m: the installed shellcheck ran --version" grep -q 'fake shellcheck' "$WORK/okA$n.out"
  run_install "okB$n" "$s" "$m" shasum "$WORK/install-ok$n.sh"
  expect "$s $m: a matching digest passes with shasum -a 256 when sha256sum is absent" [ "$irc" -eq 0 ]
  run_install "badB$n" "$s" "$m" shasum "$SC_RUN"
  expect "$s $m: a mismatch fails with shasum -a 256 too" [ "$irc" -ne 0 ]
done
run_install "plat-unknown" FreeBSD amd64 sha256sum "$SC_RUN"
expect "an unpinned platform fails the job" [ "$irc" -ne 0 ]
expect "an unpinned platform: names the platform" grep -q 'no pinned build for FreeBSD amd64' "$WORK/plat-unknown.err"
expect "an unpinned platform: nothing is downloaded" test ! -s "$WORK/log-plat-unknown"
# the pinned digests differ by platform (a copy-paste of one digest would pass the cases above)
expect "the four pinned digests are all different" bash -c "[ \$(grep -Eo 'sha256=[0-9a-f]{64}' '$CIA' | sort -u | wc -l) -eq 4 ]"

# 7. the gate scripts come from the base revision, so a pull request cannot weaken them
G="$(newrepo)"
gi "$G" symbolic-ref HEAD refs/heads/master
mkdir -p "$G/scripts"
cp "$ROOT/templates/team-stamp/files/scripts/check-owners.sh" "$G/scripts/check-owners.sh"
printf '#!/bin/sh\necho base-version\n' >"$G/scripts/pr-shape.sh"
printf '# Owners\n\n| Path | What it does | Owner | Sponsor |\n|---|---|---|---|\n| `scripts/check-owners.sh` | owners | @t | |\n| `scripts/pr-shape.sh` | shape | @t | |\n' >"$G/OWNERS.md"
printf '#!/bin/sh\necho x\n' >"$G/scripts/unowned.sh"
gi "$G" add -A; gi "$G" commit -q -m base
BASE="$(gi "$G" rev-parse HEAD)"
printf 'exit 0\n' >"$G/scripts/check-owners.sh"
printf '#!/bin/sh\necho weak-version\n' >"$G/scripts/pr-shape.sh"
gi "$G" add -A; gi "$G" commit -q -m "weaken the gates"
HEAD_="$(gi "$G" rev-parse HEAD)"
gate_step() { # gate_step <name> <step name> <BASE_SHA>: run the step in $G; result in $grc
  step_run "$CIA" "$2" >"$WORK/step-$1.sh"
  mkdir -p "$WORK/rt-$1"
  grc=0
  (cd "$G" && env BASE_SHA="$3" RUNNER_TEMP="$WORK/rt-$1" bash "$WORK/step-$1.sh") >"$WORK/$1.out" 2>"$WORK/$1.err" || grc=$?
}
gate_step own1 "Take the owners check from the base revision" "$BASE"
expect "the owners step takes check-owners.sh from the base" [ "$grc" -eq 0 ]
expect "the copy aside is the base text, not the pull request's" bash -c "grep -q 'check-owners:' '$WORK/rt-own1/gate/check-owners.sh' && ! grep -qx 'exit 0' '$WORK/rt-own1/gate/check-owners.sh'"
step_run "$CIA" "Every script and workflow has an owner" >"$WORK/run-owners.sh"
orc=0
(cd "$G" && env RUNNER_TEMP="$WORK/rt-own1" bash "$WORK/run-owners.sh") >"$WORK/owners.out" 2>"$WORK/owners.err" || orc=$?
expect "the owners step runs the base copy against the pull request tree: it refuses an unowned script" [ "$orc" -eq 1 ]
expect "the owners refusal names the script" grep -q 'check-owners: no owner yet for scripts/unowned.sh' "$WORK/owners.err"
expect "the pull request's own weakened copy would have passed (the control)" bash -c "cd '$G' && bash scripts/check-owners.sh"
gate_step shape1 "Take the PR shape check from the base revision" "$BASE"
expect "the PR shape step takes pr-shape.sh from the base" [ "$grc" -eq 0 ]
expect "the copy aside is the base text" grep -qx 'echo base-version' "$WORK/rt-shape1/gate/pr-shape.sh"
expect "the step says which revision the copy came from" grep -q "gate: scripts/pr-shape.sh is the copy from base $BASE" "$WORK/shape1.out"
ROOT_C="$(gi "$G" commit-tree -m empty "$(gi "$G" hash-object -t tree -w /dev/null)")"
gate_step shape2 "Take the PR shape check from the base revision" "$ROOT_C"
expect "a base without the script fails the step (the bootstrap pull request is merged by hand)" [ "$grc" -ne 0 ]
expect "no copy of the pull request's script was taken" test ! -s "$WORK/rt-shape2/gate/pr-shape.sh"
expect "the failure says to merge the first stamp pull request by hand" grep -q 'Merge it by hand' "$WORK/shape2.err"
gate_step shape3 "Take the PR shape check from the base revision" "$(printf '%040d' 0)"
expect "a base revision missing from the checkout fails the step" [ "$grc" -ne 0 ]
expect "a missing base revision is named" grep -q 'is not in this checkout' "$WORK/shape3.err"

# 8. the path filter, with the stamped product paths
filter_run() { # filter_run <name> <BASE> <HEAD>: the product output
  step_run "$CIA" "Path filter" >"$WORK/filter-$1.sh"
  : >"$WORK/go-$1"
  (cd "$G" && env BASE_SHA="$2" HEAD_SHA="$3" GITHUB_OUTPUT="$WORK/go-$1" bash "$WORK/filter-$1.sh") >"$WORK/filter-$1.out" 2>&1 || return 1
  grep -x 'product=.*' "$WORK/go-$1"
}
r="$(filter_run f1 "$BASE" "$HEAD_")"
expect "no product path changed: product=false" [ "$r" = "product=false" ]
mkdir -p "$G/app"; printf 'x\n' >"$G/app/main.rs"
gi "$G" add -A; gi "$G" commit -q -m "touch a product path"
r="$(filter_run f2 "$HEAD_" "$(gi "$G" rev-parse HEAD)")"
expect "a product path changed: product=true" [ "$r" = "product=true" ]
mkdir -p "$G/.github/workflows"; printf 'name: CI\n' >"$G/.github/workflows/ci.yml"
H2="$(gi "$G" rev-parse HEAD)"
gi "$G" add -A; gi "$G" commit -q -m "touch the workflow"
r="$(filter_run f3 "$H2" "$(gi "$G" rev-parse HEAD)")"
expect "the workflow itself changed: product=true" [ "$r" = "product=true" ]
printf 'y\n' >"$G/other.txt"
H3="$(gi "$G" rev-parse HEAD)"
gi "$G" add -A; gi "$G" commit -q -m "touch another path"
r="$(filter_run f4 "$H3" "$(gi "$G" rev-parse HEAD)")"
expect "a path outside the product paths: product=false" [ "$r" = "product=false" ]

# 9. AC12: the twin set
expect "AC12: the declared set of ci.yml is not empty" bash -c "[ -n \"\$(sed -n 's/^#   twin: //p' '$CIA')\" ]"
expect "AC12: the set holds the two gate commands" bash -c "[ \$(sed -n 's/^#   twin: //p' '$CIA' | wc -l) -eq 2 ]"
expect "AC12: the declared sets of ci.yml and check.sh match, and every member runs in both with the same inputs" twin_ok "$CIA" "$CKA"
expect "AC12: the same holds for the default-value stamp" twin_ok "$CIB" "$CKB"
# negative controls: drop a command, drop an input, empty the set, add an undeclared command
grep -v 'bash scripts/pr-shape.sh' "$CKA" >"$WORK/ck-nopr.sh"
refute "AC12: check.sh without its pr-shape command fails the twin check" twin_ok "$CIA" "$WORK/ck-nopr.sh"
sed 's/BASE_SHA="\$base" //' "$CKA" >"$WORK/ck-noenv.sh"
refute "AC12: check.sh without the BASE_SHA input fails the twin check" twin_ok "$CIA" "$WORK/ck-noenv.sh"
grep -v '^          PR_BODY: ' "$CIA" >"$WORK/ci-noenv.yml"
refute "AC12: a workflow step without the PR_BODY input fails the twin check" twin_ok "$WORK/ci-noenv.yml" "$CKA"
grep -v '^#   twin: ' "$CIA" >"$WORK/ci-empty.yml"
grep -v '^#   twin: ' "$CKA" >"$WORK/ck-empty.sh"
refute "AC12: an empty set fails the twin check" twin_ok "$WORK/ci-empty.yml" "$WORK/ck-empty.sh"
sed 's/^        run: bash "\$RUNNER_TEMP\/gate\/pr-shape.sh"$/        run: bash "$RUNNER_TEMP\/gate\/pr-shape.sh" \&\& bash scripts\/extra.sh/' "$CIA" >"$WORK/ci-extra.yml"
refute "AC12: a gate command in ci.yml that the set does not declare fails the twin check" twin_ok "$WORK/ci-extra.yml" "$CKA"
sed 's/^#   twin: check-owners.sh$/#   twin: check-other.sh/' "$CIA" >"$WORK/ci-other.yml"
refute "AC12: sets that differ fail the twin check" twin_ok "$WORK/ci-other.yml" "$CKA"

# 10. every generated file: kit-free, no dash characters, no python3, no bash 4 feature, shellcheck clean
for f in scripts/check.sh scripts/test-check.sh .github/workflows/ci.yml; do
  expect "$f names no kit path" bash -c "! grep -Eq '$KIT_PATTERN' '$A/$f'"
  expect "$f has no em or en dash" bash -c "! LC_ALL=C grep -q -e '$(printf '\342\200\224')' -e '$(printf '\342\200\223')' '$A/$f'"
  expect "$f does not call python3" bash -c "! grep -q 'python3' '$A/$f'"
done
for f in scripts/check.sh scripts/test-check.sh; do
  expect "$f has no bash 4 feature" bash -c "! grep -Eq 'readarray|mapfile|grep -P|sed -r|declare -A|\\$\\{[A-Za-z_]+(,,|\\^\\^)\\}' '$A/$f'"
  expect "$f holds no bare 40 or 64 digit hex run" bash -c "! grep -Eq '[0-9a-fA-F]{40}' '$A/$f'"
  expect "$f has no em or en dash in the template" bash -c "! LC_ALL=C grep -q -e '$(printf '\342\200\224')' -e '$(printf '\342\200\223')' '$ROOT/templates/team-stamp/files/$f.tpl'"
  if have_shellcheck; then expect "$f is shellcheck clean at warning" shellcheck -S warning "$A/$f"; else ok "shellcheck not installed, $f skipped"; fi
done
expect "every refusal of check.sh prints Fix: and no lowercase fix:" bash -c "! grep -q 'fix: ' '$CKA'"
expect "check.sh sets no token and makes no gh api call" bash -c "! grep -Eq 'GH_TOKEN|GITHUB_TOKEN|gh api' '$CKA'"
expect "PR text never reaches eval in check.sh" bash -c "! grep -Eq '(^|[^a-z_-])eval[ \t]' '$CKA'"
expect "the header of check.sh says where the PR text comes from, and that gh is optional" bash -c "grep -q 'gh pr view' '$CKA' && grep -q 'No token' '$CKA'"

# 11. the generated test passes with non-default values (real pr-shape and owners beside it), with the
# defaults and the check group alone (stubs only), and with another tag list
RC=0
bash "$A/scripts/test-check.sh" >"$WORK/test-a.out" 2>&1 || RC=$?
expect "the generated test passes with non-default values" [ "$RC" -eq 0 ]
[ "$RC" -eq 0 ] || tail -n 12 "$WORK/test-a.out" | sed 's/^/    /'
expect "the generated test ran the real-script cases" grep -q 'PASS  real scripts, a product change with proof, tag and body: exit 0' "$WORK/test-a.out"
expect "the generated test ran its attacker-text cases" grep -q 'running every Fix line creates no PWNED' "$WORK/test-a.out"
RC=0
bash "$B/scripts/test-check.sh" >"$WORK/test-b.out" 2>&1 || RC=$?
expect "the generated test passes with the default values and no pr-shape beside it" [ "$RC" -eq 0 ]
[ "$RC" -eq 0 ] || tail -n 12 "$WORK/test-b.out" | sed 's/^/    /'
expect "the generated test skips the real-script cases when they are absent" grep -q '^skipped: the real-script cases' "$WORK/test-b.out"
C="$(newrepo)"
bash lib/stamp.sh --only ci,pr-shape,owners --default-branch develop --owner testowner --tags web,api --product-paths src/,services/ "$C" >/dev/null 2>&1
RC=0
bash "$C/scripts/test-check.sh" >"$WORK/test-c.out" 2>&1 || RC=$?
expect "the generated test passes with another branch, tags and product paths" [ "$RC" -eq 0 ]
[ "$RC" -eq 0 ] || tail -n 12 "$WORK/test-c.out" | sed 's/^/    /'
# a negative control: a check.sh that never runs pr-shape fails the generated test
sed 's/bash scripts\/pr-shape.sh/true/' "$CKA" >"$WORK/check-broken.sh"
D="$(newrepo)"
bash lib/stamp.sh --only ci,pr-shape,owners --default-branch master --owner testowner --tags app,lib --product-paths app/,pkg/ "$D" >/dev/null 2>&1
cp "$WORK/check-broken.sh" "$D/scripts/check.sh"
RC=0
bash "$D/scripts/test-check.sh" >"$WORK/test-d.out" 2>&1 || RC=$?
refute "a check.sh that never runs pr-shape fails the generated test" [ "$RC" -eq 0 ]

# 12. check.sh and ci.yml agree on the real stamped scripts: the real check.sh runs clean on a stamped repo
E="$(newrepo)"
bash lib/stamp.sh --default-branch main --owner testowner "$E" >/dev/null 2>&1
gi "$E" symbolic-ref HEAD refs/heads/main
gi "$E" add -A
gi "$E" commit -q -m base
gi "$E" update-ref refs/remotes/origin/main "$(gi "$E" rev-parse HEAD)"
gi "$E" checkout -q -b feat/x
printf 'a note\n' >"$E/docs/note.md"
gi "$E" add -A
gi "$E" commit -q -m "docs: add a note"
RC=0
(cd "$E" && env -u CI PATH="$PATH" bash scripts/check.sh --title "docs: add a note" --body "") >"$WORK/real-check.out" 2>"$WORK/real-check.err" || RC=$?
expect "check.sh passes on a stamped repo with a docs-only change" [ "$RC" -eq 0 ]
[ "$RC" -eq 0 ] || { tail -n 15 "$WORK/real-check.out" "$WORK/real-check.err" | sed 's/^/    /'; }
expect "check.sh ran the owners check, pr-shape and the stamped script tests" bash -c "grep -q 'ok    owners' '$WORK/real-check.out' && grep -q 'ok    pr-shape' '$WORK/real-check.out' && grep -q 'script test: scripts/test-check.sh' '$WORK/real-check.out'"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
