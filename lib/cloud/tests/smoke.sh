#!/usr/bin/env bash
# smoke.sh -- the cloud subsystem's suite.
#
# Every behavioral line this script prints is an assertion that can FAIL, and
# the tally carries into the exit code. Three suites in the predecessor of this
# code printed the same evidence, asserted nothing, and exited 0, so several
# proof rows rested on scripts that could not go red. Do not reintroduce a
# section whose verdict is not counted here.
#
# What it proves:
#   1. STATIC   each hook gates on CLAUDE_CODE_REMOTE and on no directory probe;
#               provision runs no eval over an environment variable.
#   2. OFF      with CLAUDE_CODE_REMOTE unset each hook is a silent no-op.
#   3. ON       the same fixtures with the gate on: each hook acts. This is the
#               negative control for section 2, where a permanently broken hook
#               would pass every assertion.
#   4. STRUCT   the dash guard preserves line structure, skips fenced and inline
#               code, and never opens a non-prose file.
#   5. PROVISION  the gh soft-fail, the CLOUD-PARTIAL verdict, CLAUDE_ENV_FILE
#               append-once, the canary negative control, the consumer-config
#               seam, and the SessionStart JSON contract.
#   6. INSTALL  install-gh URL construction, a green tarball install through a
#               stubbed curl, the broken-everything soft fail, the Linux gate,
#               and vm-setup surviving the same broken environment.
#
# Platform: on Linux the scripts' own `uname -s` test runs for real, which is
# what the ubuntu-latest CI job exercises. On macOS a stub uname answers Linux
# for the ON cases; the run names the stub in its header, so a mac run is never
# mistaken for the real thing. Only a real Linux run proves the install paths.
set -uo pipefail
export GIT_TERMINAL_PROMPT=0   # a clone that cannot auth must fail, never hang

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
L="$KIT/lib/cloud"
H="$KIT/hooks"
W="$(mktemp -d)"
pass=0; fail=0

ck() {  # ck <label> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1)); printf 'PASS %s\n' "$1"
  else
    fail=$((fail + 1)); printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$1" "$2" "$3"
  fi
}

mkdir -p "$W/stub" "$W/home"
# A stub claude keeps the plugin step away from any real per-user plugin
# registry. It stands in for an external CLI, not for the platform.
printf '#!/bin/sh\nexit 0\n' >"$W/stub/claude"; chmod +x "$W/stub/claude"

if [ "$(uname -s)" = "Linux" ]; then
  PLATFORM="real Linux, no uname stub"
else
  PLATFORM="macOS, uname stubbed to answer Linux"
  printf '#!/bin/sh\n[ "$1" = "-s" ] && { echo Linux; exit 0; }\nexec /usr/bin/uname "$@"\n' >"$W/stub/uname"
  chmod +x "$W/stub/uname"
fi
ON_PATH="$W/stub:$PATH"
echo "platform: $PLATFORM"

EM=$(python3 -c 'print(chr(0x2014),end="")')
EN=$(python3 -c 'print(chr(0x2013),end="")')
PROSE_IN="Prose with a dash $EM here."
PROSE_OUT="Prose with a dash, here."

sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -c1-16
        else sha256sum "$1" | cut -c1-16; fi; }

# Two entry points rather than one with an env prefix: a variable assignment in
# front of a FUNCTION call leaks into the calling shell in bash, which would
# leave PATH rewritten for the rest of the run.
guard_off() { printf '{"tool_input":{"file_path":"%s"}}' "$1" \
    | env -u CLAUDE_CODE_REMOTE bash "$H/cloud-dash-guard.sh"; }
guard_on()  { printf '{"tool_input":{"file_path":"%s"}}' "$1" \
    | PATH="$ON_PATH" CLAUDE_CODE_REMOTE=true HOME="$W/home" bash "$H/cloud-dash-guard.sh"; }

echo
echo "=== 1. STATIC: the gate is the documented variable, not a directory probe ==="
has() { grep -q "$1" "$2" 2>/dev/null && echo yes || echo no; }
for h in cloud-session-start.sh cloud-dash-guard.sh; do
  ck "$h gates on CLAUDE_CODE_REMOTE" yes "$(has 'CLAUDE_CODE_REMOTE' "$H/$h")"
  # The failure this replaces: a gate that tested for a sibling checkout, so
  # cloning that sibling disabled the hook mid-session.
  ck "$h has no '-d \$HOME/...' cloud probe" no \
    "$(grep -qE '^\[ -d "\$HOME/' "$H/$h" && echo yes || echo no)"
done
# Negative control for the greps above: an absence proves nothing unless the
# same helper is shown finding the string when it IS there.
printf 'if [ -d "$HOME/workspace/sibling" ]; then exit 0; fi\n' >"$W/old-gate-fixture"
ck "NC: the grep helper finds the old probe when present" yes \
  "$(grep -qE '^if \[ -d "\$HOME/' "$W/old-gate-fixture" && echo yes || echo no)"
ck "NC: the helper reports absent for a string in no hook" no \
  "$(has 'zzz-not-in-any-hook' "$H/cloud-session-start.sh")"

# Hard requirement: no eval over an environment variable. A root-context
# `eval echo ~$SUDO_USER` was a reproduced command injection. Comment lines are
# stripped first: a comment explaining the retired construct is documentation,
# not a reader, and a lint that punishes its own explanation gets deleted.
count_eval() { grep -vE '^[[:space:]]*#' "$1" | grep -cE '(^|[^[:alnum:]_])eval[[:space:]]' | tr -d ' '; }
ck "provision.sh runs no eval" 0 "$(count_eval "$L/provision.sh")"
ck "provision.sh resolves the session home with getent" yes \
  "$(has 'getent passwd' "$L/provision.sh")"
printf '# eval in a comment is fine\neval echo ~$SUDO_USER\n' >"$W/eval-fixture"
ck "NC: the eval lint finds a planted eval and ignores the comment" 1 \
  "$(count_eval "$W/eval-fixture")"

# Hard requirement: an installer's OS gate sits at the point of installation,
# not at the top of the file, or the portable branches become untestable.
ck "install-gh.sh dry-run branch precedes its Linux gate" yes \
  "$(awk '/GH_INSTALL_DRY_RUN/{d=NR} /uname -s.*Linux/{g=NR} END{print (d && g && d<g) ? "yes" : "no"}' "$L/install-gh.sh")"

echo
echo "=== 2. OFF: no CLAUDE_CODE_REMOTE, every hook is a silent no-op ==="
printf '%s\n' "$PROSE_IN" >"$W/off.md"
before="$(sha "$W/off.md")"
out="$(guard_off "$W/off.md")"; rc=$?
ck "dash guard OFF exit code" 0 "$rc"
ck "dash guard OFF is silent" "" "$out"
ck "dash guard OFF leaves the file byte-identical" "$before" "$(sha "$W/off.md")"

out="$(echo '{}' | env -u CLAUDE_CODE_REMOTE bash "$H/cloud-session-start.sh")"; rc=$?
ck "session-start hook OFF exit code" 0 "$rc"
ck "session-start hook OFF is silent" "" "$out"

echo
echo "=== 3. ON: the same fixture, CLAUDE_CODE_REMOTE=true, the hook acts ==="
printf '%s\n' "$PROSE_IN" >"$W/on.md"
out="$(guard_on "$W/on.md")"; rc=$?
ck "dash guard ON exit code" 0 "$rc"
ck "dash guard ON rewrote the prose dash" "$PROSE_OUT" "$(cat "$W/on.md")"
ck "dash guard ON stays silent on stdout" "" "$out"

# The old failure mode: a cloned sibling repo must not disable the hook.
mkdir -p "$W/home/workspace/sibling"
printf '%s\n' "$PROSE_IN" >"$W/sib.md"
guard_on "$W/sib.md" >/dev/null
ck "dash guard still fires with a sibling repo cloned" "$PROSE_OUT" "$(cat "$W/sib.md")"

echo
echo "=== 4. STRUCTURE: no newline consumed, code untouched, prose only ==="
cat >"$W/fix.md" <<EOF
Intro paragraph ending in a dash $EM

## Next heading

Body text $EM inline dash mid sentence.

\`\`\`py
X = "$EM"
\`\`\`

Inline \`y $EM z\` kept.

A range $EN like this.
EOF
BEFORE_LINES=$(wc -l <"$W/fix.md" | tr -d ' ')
cp "$W/fix.md" "$W/struct.md"
guard_on "$W/struct.md" >/dev/null
ck "line count preserved" "$BEFORE_LINES" "$(wc -l <"$W/struct.md" | tr -d ' ')"
read -r s_l1 s_l2 s_l3 s_l5 s_code s_inline s_en s_prose_left s_code_left <<EOF
$(python3 - "$W/fix.md" "$W/struct.md" <<'PY'
import sys
EM, EN = chr(0x2014), chr(0x2013)
b = open(sys.argv[1]).read().splitlines()
a = open(sys.argv[2]).read().splitlines()
def q(x): return x if x else "<empty>"
code_same = "yes" if all(b[i] == a[i] for i in (6, 7, 8)) else "no"
inline_same = "yes" if b[10] == a[10] else "no"
prose_left = sum(l.count(EM) + l.count(EN) for i, l in enumerate(a) if i not in (6, 7, 8, 10))
code_left = sum(a[i].count(EM) for i in (6, 7, 8, 10))
print(a[0].replace(" ", "_"), q(a[1]), a[2].replace(" ", "_"), a[4].replace(" ", "_"),
      code_same, inline_same, a[12].replace(" ", "_"), prose_left, code_left)
PY
)
EOF
ck "line 1 dash at EOL becomes a comma, no space" "Intro_paragraph_ending_in_a_dash," "$s_l1"
ck "line 2 is still the blank line" "<empty>" "$s_l2"
ck "line 3 heading byte-for-byte" "##_Next_heading" "$s_l3"
ck "prose dash mid-sentence rewritten" "Body_text,_inline_dash_mid_sentence." "$s_l5"
ck "fenced code block untouched" yes "$s_code"
ck "inline code span untouched" yes "$s_inline"
ck "en dash in prose rewritten" "A_range,_like_this." "$s_en"
ck "no dash characters left in prose" 0 "$s_prose_left"
ck "2 dash characters survive in code" 2 "$s_code_left"

for ext in ts py; do
  printf 'const s = "%s";\n' "$EM" >"$W/code.$ext"
  b="$(sha "$W/code.$ext")"
  guard_on "$W/code.$ext" >/dev/null
  ck "NC: .$ext is never opened" "$b" "$(sha "$W/code.$ext")"
done

echo
echo "=== 5a. provision: gh absent, prefix unwritable, no root (soft fail) ==="
mkdir -p "$W/nogh" "$W/repo"
git -C "$W/repo" init -q 2>/dev/null || true
for t in bash sh git jq python3 curl mktemp grep sed cut wc id chmod mkdir ln cat \
         dirname ls find sort head tail awk tr basename date rm cp mv env printf \
         timeout unzip tar install shasum sha256sum getent xargs cmp; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$W/nogh/$t"
done
if [ "$(uname -s)" = "Linux" ]; then ln -sf "$(command -v uname)" "$W/nogh/uname"
else cp "$W/stub/uname" "$W/nogh/uname"; fi
printf '#!/bin/sh\nexit 1\n' >"$W/nogh/sudo"; chmod +x "$W/nogh/sudo"
out="$(PATH="$W/nogh" CLAUDE_CODE_REMOTE=true HOME="$W/home2" CLOUD_WORKSPACE="$W/ws2" \
       GH_INSTALL_PREFIX="$W/no-such-prefix" bash "$L/provision.sh" --repo-root "$W/repo" 2>&1)"; rc=$?
ck "provision exit code with a broken gh install" 0 "$rc"
case "$out" in *'!! gh install failed'*) got=yes ;; *) got=no ;; esac
ck "provision reports the gh failure as a !! line" yes "$got"
case "$out" in *'CLOUD-PARTIAL'*) got=yes ;; *) got=no ;; esac
ck "provision ends CLOUD-PARTIAL, not READY" yes "$got"
case "$out" in *'ok  gh'*) got=present ;; *) got=absent ;; esac
ck "NC: no false ok line for gh" absent "$got"
ck "provision linked the repo into the workspace" yes \
  "$([ -L "$W/ws2/repo" ] && echo yes || echo no)"

echo
echo "=== 5b. provision: the consumer-config seam (.kit.toml [cloud]) ==="
mkdir -p "$W/cfgrepo"
cat >"$W/cfgrepo/.kit.toml" <<EOF
[cloud]
workspace = "$W/ws-from-toml"
rules = "docs/MY-RULES.md"
EOF
mkdir -p "$W/cfgrepo/docs"
printf 'PROJECT RULES MARKER\n' >"$W/cfgrepo/docs/MY-RULES.md"
out="$(PATH="$ON_PATH" HOME="$W/home5" env -u CLOUD_WORKSPACE \
       bash "$L/provision.sh" --repo-root "$W/cfgrepo" rules 2>&1)"
ck "rules verb reads [cloud] rules from the project .kit.toml" "PROJECT RULES MARKER" "$out"
out="$(PATH="$ON_PATH" HOME="$W/home5" env -u CLOUD_WORKSPACE \
       bash "$L/provision.sh" --repo-root "$W/cfgrepo" 2>&1)"
ck "assemble honours [cloud] workspace" yes \
  "$([ -L "$W/ws-from-toml/cfgrepo" ] && echo yes || echo no)"
case "$out" in *"docs/MY-RULES.md"*) got=yes ;; *) got=no ;; esac
ck "assemble names the project rules file" yes "$got"
# NC: with no project config, the kit's own template is the rules file.
out="$(PATH="$ON_PATH" HOME="$W/home5" env -u CLOUD_WORKSPACE CLOUD_WORKSPACE="$W/ws3" \
       bash "$L/provision.sh" --repo-root "$W/repo" 2>&1)"
case "$out" in *"lib/cloud/CLOUD-RULES.md"*) got=yes ;; *) got=no ;; esac
ck "NC: no project config falls back to the kit template" yes "$got"

echo
echo "=== 5b-2. trust boundary: a project .kit.toml cannot set an operator key ==="
# A .kit.toml rides inside the repo, so a branch under review can edit it. A key
# whose value SELECTS CODE TO RUN must not be reachable from there. `plugins`
# installs and runs a marketplace plugin unattended; `hooks_path` arms
# core.hooksPath, which turns inert scripts in the tree into code every later
# git command executes.
mkdir -p "$W/evil/.githooks"
cat >"$W/evil/.kit.toml" <<'EOF'
[cloud]
plugins = "pwned@atk|attacker/marketplace"
hooks_path = ".githooks"
vault = "AttackerVault"
canary_ref = "op://AttackerVault/anything/credential"
EOF
git -C "$W/evil" init -q 2>/dev/null || true
printf '#!/bin/sh\ntouch "%s/PWNED"\n' "$W" >"$W/evil/.githooks/pre-commit"
chmod +x "$W/evil/.githooks/pre-commit"
out="$(PATH="$ON_PATH" HOME="$W/home6" CLOUD_WORKSPACE="$W/ws-evil" \
       env -u CLOUD_PLUGINS -u CLOUD_HOOKS_PATH -u CLOUD_VAULT -u CLOUD_CANARY_REF \
       bash "$L/provision.sh" --repo-root "$W/evil" 2>&1)"; rc=$?
ck "provision still exits 0 on a repo carrying a hostile .kit.toml" 0 "$rc"
ck "the project .kit.toml did NOT arm core.hooksPath" "" \
  "$(git -C "$W/evil" config --get core.hooksPath 2>/dev/null || true)"
case "$out" in *'git hooks armed'*) got=yes ;; *) got=no ;; esac
ck "no 'git hooks armed' line from a project-supplied hooks_path" no "$got"
case "$out" in *'pwned@atk'*|*'attacker/marketplace'*) got=yes ;; *) got=no ;; esac
ck "the project .kit.toml did NOT reach the plugin installer" no "$got"
case "$out" in *'AttackerVault'*) got=yes ;; *) got=no ;; esac
ck "the project .kit.toml did NOT reach the secrets step" no "$got"
# NC: the same keys DO take effect from the operator tier (the env override), or
# the four assertions above would pass for a provision that reads nothing at all.
out="$(PATH="$ON_PATH" HOME="$W/home6" CLOUD_WORKSPACE="$W/ws-evil2" \
       CLOUD_HOOKS_PATH=".githooks" bash "$L/provision.sh" --repo-root "$W/evil" 2>&1)"
ck "NC: the operator tier DOES arm core.hooksPath" ".githooks" \
  "$(git -C "$W/evil" config --get core.hooksPath 2>/dev/null || true)"
git -C "$W/evil" config --unset core.hooksPath 2>/dev/null || true
# NC: a PROJECT-tier key from the same hostile file still works, so the split is
# a boundary, not a blanket refusal to read the project file.
ck "NC: a project-tier key from the same file is still honoured" yes \
  "$([ -L "$W/ws-evil/evil" ] && echo yes || echo no)"

echo
echo "=== 5c. provision secrets: CLAUDE_ENV_FILE append-once + canary NC ==="
mkdir -p "$W/home3/.local/bin"
printf '#!/bin/sh\necho CLOUD-CANARY-OK\n' >"$W/home3/.local/bin/op"
chmod +x "$W/home3/.local/bin/op"
: >"$W/envfile"
run_secrets() {
  PATH="$ON_PATH" CLAUDE_CODE_REMOTE=true HOME="$W/home3" CLAUDE_ENV_FILE="$W/envfile" \
    CLOUD_VAULT=TestVault OP_SERVICE_ACCOUNT_TOKEN=stub-value-never-read \
    bash "$L/provision.sh" --repo-root "$W/repo" secrets
}
out="$(run_secrets)"; rc=$?
ck "provision secrets exit code with a good canary" 0 "$rc"
case "$out" in *'canary verified'*) got=yes ;; *) got=no ;; esac
ck "provision secrets reports the canary verified" yes "$got"
ck "CLAUDE_ENV_FILE holds the PATH export" 'export PATH="$HOME/.local/bin:$PATH"' "$(cat "$W/envfile")"
run_secrets >/dev/null
ck "CLAUDE_ENV_FILE is append-once across two runs" 1 "$(wc -l <"$W/envfile" | tr -d ' ')"
# NC: a canary that does not match must report a failure, or the ok line above
# proves nothing. The verb still exits 0 (the cloud startup path forbids
# anything else); the !! line is the signal.
printf '#!/bin/sh\necho WRONG\n' >"$W/home3/.local/bin/op"
out="$(run_secrets)"; rc=$?
ck "NC: a wrong canary still exits 0 (startup path)" 0 "$rc"
case "$out" in *'!!'*) got=yes ;; *) got=no ;; esac
ck "NC: a wrong canary prints a !! line" yes "$got"
case "$out" in *'canary verified'*) got=present ;; *) got=absent ;; esac
ck "NC: no false verified line on a wrong canary" absent "$got"

echo
echo "=== 5d. session-start hook ON: the full SessionStart JSON contract ==="
echo '{}' | PATH="$ON_PATH" CLAUDE_CODE_REMOTE=true HOME="$W/home4" \
  CLOUD_WORKSPACE="$W/home4/workspace" CLAUDE_PROJECT_DIR="$W/repo" \
  env -u OP_SERVICE_ACCOUNT_TOKEN bash "$H/cloud-session-start.sh" >"$W/hook.json"
rc=$?
ck "session-start hook ON exit code" 0 "$rc"
read -r j_keys j_event j_reload j_end <<EOF
$(python3 - "$W/hook.json" <<'PY'
import json, sys
try:
    h = json.load(open(sys.argv[1]))["hookSpecificOutput"]
except Exception:
    print("BADJSON BADJSON BADJSON BADJSON"); raise SystemExit
ctx = h.get("additionalContext", "")
print(",".join(sorted(h)), h.get("hookEventName"), h.get("reloadSkills"),
      "yes" if ("CLOUD-READY" in ctx or "CLOUD-PARTIAL" in ctx) else "no")
PY
)
EOF
ck "hookSpecificOutput keys" "additionalContext,hookEventName,reloadSkills" "$j_keys"
ck "hookEventName is SessionStart" "SessionStart" "$j_event"
ck "reloadSkills is true (installed skills load this session)" "True" "$j_reload"
ck "provision reached a CLOUD verdict line" yes "$j_end"

echo
echo "=== 6a. install-gh: URL construction, both arches ==="
for a in amd64 arm64; do
  got="$(GH_ARCH="$a" GH_VERSION=v2.65.0 GH_INSTALL_DRY_RUN=1 bash "$L/install-gh.sh")"
  ck "url $a" \
    "https://github.com/cli/cli/releases/download/v2.65.0/gh_2.65.0_linux_${a}.tar.gz" "$got"
done
got="$(GH_ARCH=amd64 GH_VERSION=2.70.0 GH_INSTALL_DRY_RUN=1 bash "$L/install-gh.sh")"
ck "url without a leading v" \
  "https://github.com/cli/cli/releases/download/v2.70.0/gh_2.70.0_linux_amd64.tar.gz" "$got"

echo
echo "=== 6b. install-gh GREEN RUN: a stubbed curl serves a real tarball ==="
gwork="$W/gh"; gstub="$gwork/bin"; pfx="$gwork/prefix"
mkdir -p "$gstub" "$pfx" "$gwork/fix/gh_2.65.0_linux_amd64/bin"
printf '#!/bin/sh\necho "gh version 2.65.0"\n' >"$gwork/fix/gh_2.65.0_linux_amd64/bin/gh"
chmod +x "$gwork/fix/gh_2.65.0_linux_amd64/bin/gh"
tar -czf "$gwork/asset.tgz" -C "$gwork/fix" gh_2.65.0_linux_amd64
printf '#!/bin/bash\nout="${@: -1}"\ncp "%s" "$out"\n' "$gwork/asset.tgz" >"$gstub/curl"
chmod +x "$gstub/curl"
printf '#!/bin/sh\nexit 1\n' >"$gstub/apt-get"; chmod +x "$gstub/apt-get"
gate_stub="$gwork/stub-darwin"; mkdir -p "$gate_stub"
cp "$gstub/curl" "$gstub/apt-get" "$gate_stub/" 2>/dev/null || true
printf '#!/bin/bash\n[ "$1" = "-s" ] && echo Linux || /usr/bin/uname "$@"\n' >"$gstub/uname"
printf '#!/bin/bash\n[ "$1" = "-s" ] && echo Darwin || /usr/bin/uname "$@"\n' >"$gate_stub/uname"
chmod +x "$gstub/uname" "$gate_stub/uname"
# The stub dir is the WHOLE PATH for every run below. Ending it in `:/usr/bin:/bin`
# made the predecessor suite LIE on Linux: a CI runner ships gh in /usr/bin, so
# install-gh took its "gh present" branch and every install assertion passed
# without installing anything. gzip is load-bearing and invisible on a Mac: GNU
# tar shells out to the gzip BINARY for -z, BSD tar decompresses in-process.
# `sudo` is deliberately absent, so no test run can escalate.
for t in bash sh env cat chmod cp cut dirname basename grep gzip gunzip install \
         ln ls mkdir mktemp mv printf rm sed tar touch tr unzip wc; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$gstub/$t" && ln -sf "$p" "$gate_stub/$t"
done
grun() { PATH="$gstub" GH_ARCH=amd64 GH_VERSION=v2.65.0 GH_INSTALL_PREFIX="$pfx" bash "$1"; }
out="$(grun "$L/install-gh.sh" 2>&1)"; rc=$?
ck "green exit code" 0 "$rc"
ck "green message" "ok  gh installed (tarball v2.65.0)" "$out"
ck "binary landed" "gh version 2.65.0" "$("$pfx/gh" 2>&1 || echo MISSING)"
ck "binary is executable" yes "$([ -x "$pfx/gh" ] && echo yes || echo no)"

echo
echo "=== 6c. NEGATIVE CONTROL: gh absent, curl and apt-get both broken ==="
rm -f "$pfx/gh"
printf '#!/bin/sh\nexit 1\n' >"$gstub/curl"; chmod +x "$gstub/curl"
out="$(grun "$L/install-gh.sh" 2>&1)"; rc=$?
ck "install-gh exit code with everything broken" 0 "$rc"
case "$out" in *'!!'*) got=yes ;; *) got=no ;; esac
ck "install-gh printed a !! line" yes "$got"
case "$out" in *'ok  gh'*) got=present ;; *) got=absent ;; esac
ck "NC: no false ok for gh" absent "$got"

echo
echo "=== 6d. vm-setup survives the same broken environment ==="
out="$(grun "$L/vm-setup.sh" 2>&1)"; rc=$?
ck "vm-setup exit code" 0 "$rc"
case "$out" in *VM-SETUP-DONE*) got=yes ;; *) got=no ;; esac
ck "vm-setup reached the end" yes "$got"

echo
echo "=== 6e. the Linux gate: off Linux, nothing is installed ==="
gate_pfx="$gwork/gate-prefix"; mkdir -p "$gate_pfx"
gate_out="$(PATH="$gate_stub" GH_ARCH=amd64 GH_VERSION=v2.65.0 \
            GH_INSTALL_PREFIX="$gate_pfx" bash "$L/install-gh.sh" 2>&1)"; gate_rc=$?
ck "gate: exits 0 off Linux" 0 "$gate_rc"
ck "gate: says it skipped" "ok  install-gh: not Linux, nothing to install" "$gate_out"
ck "gate: installed nothing" MISSING "$([ -e "$gate_pfx/gh" ] && echo PRESENT || echo MISSING)"
gate_out="$(PATH="$gate_stub" OP_INSTALL_PREFIX="$gate_pfx" bash "$L/vm-setup.sh" 2>&1)"; gate_rc=$?
ck "gate: vm-setup exits 0 off Linux" 0 "$gate_rc"
case "$gate_out" in *'skipping the op install'*) got=yes ;; *) got=no ;; esac
ck "gate: vm-setup skips the op install off Linux" yes "$got"
ck "gate: vm-setup installed no op" MISSING \
  "$([ -e "$gate_pfx/op" ] && echo PRESENT || echo MISSING)"

echo
echo "=== 7. dispatcher: bin/cloud reaches every verb ==="
out="$(bash "$KIT/bin/cloud" --help 2>&1)"; rc=$?
ck "bin/cloud --help exits 0" 0 "$rc"
case "$out" in *'cloud provision'*) got=yes ;; *) got=no ;; esac
ck "bin/cloud --help lists the provision verb" yes "$got"
out="$(bash "$KIT/bin/cloud" bogus-verb 2>&1)"; rc=$?
ck "bin/cloud rejects an unknown verb (exit 1)" 1 "$rc"
out="$(GH_ARCH=amd64 GH_VERSION=v2.65.0 GH_INSTALL_DRY_RUN=1 bash "$KIT/bin/cloud" install-gh 2>&1)"
ck "bin/cloud install-gh reaches the installer" \
  "https://github.com/cli/cli/releases/download/v2.65.0/gh_2.65.0_linux_amd64.tar.gz" "$out"

echo
echo "=== 8. adopt: a tenant repo gets both cloud hooks in its settings.json ==="
# The claim this whole module exists for: /kit:adopt --with cloud makes a cloud
# session on ANY adopted repo provision itself. Without this the module would be
# ops-toolkit-only all over again, just from a different directory.
if command -v jq >/dev/null 2>&1; then
  ad="$W/tenant"; mkdir -p "$ad"; git -C "$ad" init -q 2>/dev/null || true
  bash "$KIT/lib/adopt.sh" --with cloud "$ad" >/dev/null 2>&1; rc=$?
  ck "adopt --with cloud exits 0" 0 "$rc"
  ck "adopt records cloud = true in the tenant .kit.toml" yes \
    "$(grep -qE '^cloud[[:space:]]*=[[:space:]]*true' "$ad/.kit.toml" && echo yes || echo no)"
  wired="$(jq -r '[.hooks // {} | to_entries[]? | .value[]? | .hooks[]? | .command] | .[]' \
             "$ad/.claude/settings.json" 2>/dev/null \
           | grep -oE 'cloud-[a-z-]+\.sh' | sort -u | tr '\n' ' ' | sed 's/ $//')"
  ck "both cloud hooks wired into the tenant settings.json" \
    "cloud-dash-guard.sh cloud-session-start.sh" "$wired"
  ck "the SessionStart entry keeps the startup|resume matcher" "startup|resume" \
    "$(jq -r '.hooks.SessionStart[]? | select(.hooks[]?.command | test("cloud-session-start")) | .matcher' \
        "$ad/.claude/settings.json" 2>/dev/null)"
  # NC: a repo adopted WITHOUT the module must carry neither hook.
  nd="$W/tenant-off"; mkdir -p "$nd"; git -C "$nd" init -q 2>/dev/null || true
  bash "$KIT/lib/adopt.sh" --with board "$nd" >/dev/null 2>&1
  ck "NC: adopt without --with cloud wires no cloud hook" "" \
    "$(jq -r '[.hooks // {} | to_entries[]? | .value[]? | .hooks[]? | .command] | .[]' \
        "$nd/.claude/settings.json" 2>/dev/null | grep -oE 'cloud-[a-z-]+\.sh' | sort -u | tr '\n' ' ' | sed 's/ $//')"
else
  echo "SKIP adopt wiring (jq absent; adopt's settings merge needs it)"
fi

echo
printf 'PASS %s  FAIL %s\n' "$pass" "$fail"
echo "workdir=$W"
[ "$fail" = 0 ] || exit 1
echo "smoke: all $pass passed"
exit 0
