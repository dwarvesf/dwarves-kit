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

# The host's ambient environment must not decide a verdict here. A developer
# machine that happens to export a service-account token made the secrets step
# fire in every run and turned a CLOUD-READY assertion red for a reason that had
# nothing to do with the code. Same class as a test PATH that leaks the host's
# real binaries. Section 5c sets this variable explicitly where it is the point.
unset OP_SERVICE_ACCOUNT_TOKEN
unset CLOUD_PROVISION CLOUD_DASH_GUARD
unset CLOUD_WORKSPACE CLOUD_REPOS CLOUD_REPO_OWNER CLOUD_MAP CLOUD_RULES
unset CLOUD_PLUGINS CLOUD_HOOKS_PATH CLOUD_VAULT CLOUD_CANARY_REF CLOUD_OP_VERSION

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
#
# ON_PATH IS LOAD-BEARING IN THE OFF CASE TOO. Without it the macOS `uname` gate
# fires first and the hook exits before the cloud gate is ever read, so every
# OFF assertion passed with the cloud gate DELETED. That was the sixth false
# green in this subsystem's history: the suite proved at least one of the three
# gates fires, never which one. With the stub in place the OFF case reaches the
# cloud gate for real, and neutering that one line turns this suite red.
guard_off() { printf '{"tool_input":{"file_path":"%s"}}' "$1" \
    | PATH="$ON_PATH" env -u CLAUDE_CODE_REMOTE CLOUD_DASH_GUARD=1 \
      bash "$H/cloud-dash-guard.sh"; }
guard_on()  { printf '{"tool_input":{"file_path":"%s"}}' "$1" \
    | PATH="$ON_PATH" CLOUD_DASH_GUARD=1 CLAUDE_CODE_REMOTE=true HOME="$W/home" \
      bash "$H/cloud-dash-guard.sh"; }
# The same fixture with the master switch absent: a cloud session that never
# opted in must be untouched.
guard_noswitch() { printf '{"tool_input":{"file_path":"%s"}}' "$1" \
    | PATH="$ON_PATH" env -u CLOUD_DASH_GUARD CLAUDE_CODE_REMOTE=true HOME="$W/home" \
      bash "$H/cloud-dash-guard.sh"; }

echo
echo "=== 1. STATIC: the gate is the documented variable, not a directory probe ==="
has() { grep -q "$1" "$2" 2>/dev/null && echo yes || echo no; }
# has_gate matches the EXECUTABLE gate line, not any occurrence of the name.
# `has` greps the whole file, and every gate in these hooks has a paragraph of
# prose above it naming the variable, so `has` reported yes for a hook whose
# gate had been changed from `|| exit 0` to `|| :`. The static check has to
# match the line that does the work: the test, the comparison, and the exit.
has_gate() {  # has_gate <VARNAME> <file>
  grep -qE "^\[ \"\\\$\{$1:-\}\" = \"[^\"]*\" \] \|\| exit 0" "$2" 2>/dev/null \
    && echo yes || echo no
}
for h in cloud-session-start.sh cloud-dash-guard.sh; do
  ck "$h gates on CLAUDE_CODE_REMOTE" yes "$(has_gate CLAUDE_CODE_REMOTE "$H/$h")"
  # The failure this replaces: a gate that tested for a sibling checkout, so
  # cloning that sibling disabled the hook mid-session.
  ck "$h has no '-d \$HOME/...' cloud probe" no \
    "$(grep -qE '^\[ -d "\$HOME/' "$H/$h" && echo yes || echo no)"
done
# Negative control for the greps above: an absence proves nothing unless the
# SAME pattern is shown firing on the historical regression's exact shape. The
# fixture is byte-identical to what the retired gate looked like.
printf '[ -d "$HOME/workspace/sibling" ] || exit 0\n' >"$W/old-gate-fixture"
ck "NC: the same pattern fires on the historical gate shape" yes \
  "$(grep -qE '^\[ -d "\$HOME/' "$W/old-gate-fixture" && echo yes || echo no)"
ck "NC: the helper reports absent for a string in no hook" no \
  "$(has 'zzz-not-in-any-hook' "$H/cloud-session-start.sh")"
# NC for has_gate, the check this suite's sixth false green turned on: a fixture
# that MENTIONS the variable in prose and neuters the gate must report no, and
# the intact shape must report yes.
printf '# gates on CLAUDE_CODE_REMOTE, the documented cloud signal\n[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || :\n' \
  >"$W/neutered-gate-fixture"
ck "NC: has_gate rejects a neutered gate whose name survives in a comment" no \
  "$(has_gate CLAUDE_CODE_REMOTE "$W/neutered-gate-fixture")"
ck "NC: the plain grep is fooled by that same fixture (why has_gate exists)" yes \
  "$(has 'CLAUDE_CODE_REMOTE' "$W/neutered-gate-fixture")"
printf '[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0\n' >"$W/intact-gate-fixture"
ck "NC: has_gate accepts the intact shape" yes \
  "$(has_gate CLAUDE_CODE_REMOTE "$W/intact-gate-fixture")"

# The master switch is checked FIRST, before the cloud gate. hooks.json is the
# plugin manifest and is NOT filtered by the enabled module set, so on the
# plugin-install path both hooks are registered for every consumer. Without a
# switch, "off by default" would be false on the path the kit calls recommended.
# Comment lines are skipped and only a real `${VAR:-}` expansion counts, so the
# prose above each gate cannot satisfy the order check.
gate_order() {  # gate_order <file> <switch-name>
  awk -v s="$2" '
    /^[[:space:]]*#/ { next }
    $0 ~ ("\\$\\{" s ":-") && !sw { sw = NR }
    /\$\{CLAUDE_CODE_REMOTE:-/ && !cr { cr = NR }
    END { print (sw && cr && sw < cr) ? "yes" : "no" }' "$1"
}
for pair in "cloud-session-start.sh|CLOUD_PROVISION" "cloud-dash-guard.sh|CLOUD_DASH_GUARD"; do
  h="${pair%%|*}"; sw="${pair##*|}"
  ck "$h checks $sw" yes "$(has_gate "$sw" "$H/$h")"
  ck "$h checks the switch before CLAUDE_CODE_REMOTE" yes "$(gate_order "$H/$h" "$sw")"
done
# NC: the order check reports 'no' on a fixture where the switch comes second.
printf '[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0\n[ "${CLOUD_PROVISION:-}" = "1" ] || exit 0\n' \
  >"$W/order-fixture"
ck "NC: the order check catches a switch placed after the cloud gate" no \
  "$(gate_order "$W/order-fixture" CLOUD_PROVISION)"

# The tier split is declared once and read from there. This lint checks
# CONSISTENCY, never CORRECTNESS: every key provision.sh reads appears in
# exactly one list and is read through that list's resolver. It cannot know
# whether the list is the RIGHT one for the key, and three keys that reached
# outside the repo passed it for the whole life of the branch. The correctness
# half for a project-tier PATH is the repo_path containment assertions in 5b-3.
tier_bad=""
proj="$(grep -oE '^CLOUD_PROJECT_KEYS="[^"]*"' "$L/provision.sh" | sed 's/.*"\(.*\)"/\1/')"
oper="$(grep -oE '^CLOUD_OPERATOR_KEYS="[^"]*"' "$L/provision.sh" | sed 's/.*"\(.*\)"/\1/')"
# Call sites only: comment lines are stripped first, or the header's own prose
# about `cfg_root` would register as a phantom key.
calls="$(grep -vE '^[[:space:]]*#' "$L/provision.sh" | grep -oE 'cfg(_root)? [a-z_]+ ')"
for k in $proj; do
  printf '%s\n' "$calls" | grep -qE "^cfg $k " || tier_bad="$tier_bad unread:$k"
  printf '%s\n' "$calls" | grep -qE "^cfg_root $k " && tier_bad="$tier_bad wrong-tier:$k"
done
for k in $oper; do
  printf '%s\n' "$calls" | grep -qE "^cfg_root $k " || tier_bad="$tier_bad not-operator:$k"
done
# Every key actually read must be declared. A key in neither list is the bug the
# declaration exists to prevent.
for k in $(printf '%s\n' "$calls" | awk '{print $2}' | sort -u); do
  case " $proj $oper " in *" $k "*) ;; *) tier_bad="$tier_bad undeclared:$k" ;; esac
done
ck "every [cloud] key is declared in exactly one tier and read through it" "" "$tier_bad"
ck "NC: the tier lists are non-empty (the extraction is not vacuous)" yes \
  "$([ -n "$proj" ] && [ -n "$oper" ] && echo yes || echo no)"

# The op CLI pin lives in two files that run in different contexts (Setup-script
# time and per-session). A bump that touches one and not the other desyncs them.
op_pin_a="$(grep -oE '^OP_DEFAULT_VERSION=v[0-9.]+' "$L/provision.sh" | grep -oE 'v[0-9.]+')"
op_pin_b="$(grep -oE 'OP_VERSION:-v[0-9.]+' "$L/vm-setup.sh" | grep -oE 'v[0-9.]+')"
ck "the op version pin matches across provision.sh and vm-setup.sh" "$op_pin_a" "$op_pin_b"
ck "NC: the op pin extraction is not empty on both sides" yes \
  "$([ -n "$op_pin_a" ] && [ -n "$op_pin_b" ] && echo yes || echo no)"

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

# Same reason as guard_off: ON_PATH so the uname gate cannot short-circuit the
# run before the cloud gate. Every side effect is aimed at the workdir, because
# a NEUTERED cloud gate makes this invocation really provision.
mkdir -p "$W/off-repo"; git -C "$W/off-repo" init -q 2>/dev/null || true
out="$(echo '{}' | PATH="$ON_PATH" env -u CLAUDE_CODE_REMOTE CLOUD_PROVISION=1 \
       HOME="$W/home-off" CLOUD_WORKSPACE="$W/ws-off" CLAUDE_PROJECT_DIR="$W/off-repo" \
       bash "$H/cloud-session-start.sh")"; rc=$?
ck "session-start hook OFF exit code" 0 "$rc"
ck "session-start hook OFF is silent" "" "$out"
ck "session-start hook OFF assembled nothing" no \
  "$([ -e "$W/ws-off" ] && echo yes || echo no)"

# The other half of OFF: a real cloud session that never opted in.
printf '%s\n' "$PROSE_IN" >"$W/noswitch.md"
before="$(sha "$W/noswitch.md")"
out="$(guard_noswitch "$W/noswitch.md")"; rc=$?
ck "dash guard with no CLOUD_DASH_GUARD exit code" 0 "$rc"
ck "dash guard with no CLOUD_DASH_GUARD leaves the file byte-identical" \
  "$before" "$(sha "$W/noswitch.md")"
out="$(echo '{}' | PATH="$ON_PATH" env -u CLOUD_PROVISION CLAUDE_CODE_REMOTE=true \
       CLAUDE_PROJECT_DIR="$W" bash "$H/cloud-session-start.sh")"; rc=$?
ck "session-start hook with no CLOUD_PROVISION exit code" 0 "$rc"
ck "session-start hook with no CLOUD_PROVISION is silent" "" "$out"

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

# Each hook has THREE gates: its switch, the cloud signal, and Linux. The suite
# proved that SOME gate fired, never which one, so any single gate could be
# deleted and every assertion stayed green. Sections 2 and 3 now pin the switch
# and the cloud signal; this pins the third, with both other gates ON.
mkdir -p "$W/darwin"
printf '#!/bin/sh\n[ "$1" = "-s" ] && { echo Darwin; exit 0; }\nexec /usr/bin/uname "$@"\n' \
  >"$W/darwin/uname"
chmod +x "$W/darwin/uname"
DARWIN_PATH="$W/darwin:$PATH"
printf '%s\n' "$PROSE_IN" >"$W/darwin.md"
before="$(sha "$W/darwin.md")"
out="$(printf '{"tool_input":{"file_path":"%s"}}' "$W/darwin.md" \
       | PATH="$DARWIN_PATH" CLOUD_DASH_GUARD=1 CLAUDE_CODE_REMOTE=true HOME="$W/home" \
         bash "$H/cloud-dash-guard.sh")"; rc=$?
ck "dash guard off Linux exit code" 0 "$rc"
ck "dash guard off Linux is silent" "" "$out"
ck "dash guard off Linux leaves the file byte-identical" "$before" "$(sha "$W/darwin.md")"
out="$(echo '{}' | PATH="$DARWIN_PATH" CLOUD_PROVISION=1 CLAUDE_CODE_REMOTE=true \
       HOME="$W/home-dar" CLOUD_WORKSPACE="$W/ws-dar" CLAUDE_PROJECT_DIR="$W/off-repo" \
       bash "$H/cloud-session-start.sh")"; rc=$?
ck "session-start off Linux exit code" 0 "$rc"
ck "session-start off Linux is silent" "" "$out"
ck "session-start off Linux assembled nothing" no \
  "$([ -e "$W/ws-dar" ] && echo yes || echo no)"

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

# The unbalanced-fence skip is the branch the guard's own SAFETY note names as
# the reason this version is narrow: with an odd number of fences the code
# regions cannot be trusted, so the whole file is left alone even though it
# carries a prose dash.
printf 'Prose with a dash %s here.\n\n```py\nX = 1\n' "$EM" >"$W/unbalanced.md"
b="$(sha "$W/unbalanced.md")"
guard_on "$W/unbalanced.md" >/dev/null
ck "a file with unbalanced fences is skipped whole" "$b" "$(sha "$W/unbalanced.md")"
# NC: the same content with the fence CLOSED is rewritten, so the assertion above
# is the fence rule and not a guard that never writes.
printf 'Prose with a dash %s here.\n\n```py\nX = 1\n```\n' "$EM" >"$W/balanced.md"
guard_on "$W/balanced.md" >/dev/null
ck "NC: the same file with balanced fences IS rewritten" "$PROSE_OUT" \
  "$(head -1 "$W/balanced.md")"

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
# workspace is OPERATOR-tier: the same project .kit.toml that legitimately sets
# `rules` must not be able to choose the directory this script creates a symlink
# in. Set to `$HOME/.claude/skills` from a project file, it made a PR-authored
# root SKILL.md a live skill in the same session.
ck "the project .kit.toml did NOT choose the workspace" no \
  "$([ -e "$W/ws-from-toml" ] && echo yes || echo no)"
ck "the workspace fell back to the default under HOME" yes \
  "$([ -L "$W/home5/workspace/cfgrepo" ] && echo yes || echo no)"
case "$out" in *"docs/MY-RULES.md"*) got=yes ;; *) got=no ;; esac
ck "assemble names the project rules file" yes "$got"
# NC: the SAME value from the operator tier does choose the workspace, so the
# two assertions above are the tier boundary and not a workspace that never works.
out="$(PATH="$ON_PATH" HOME="$W/home5b" CLOUD_WORKSPACE="$W/ws-from-env" \
       bash "$L/provision.sh" --repo-root "$W/cfgrepo" 2>&1)"
ck "NC: the operator tier DOES choose the workspace" yes \
  "$([ -L "$W/ws-from-env/cfgrepo" ] && echo yes || echo no)"
# NC: with no project config, the kit's own template is the rules file.
out="$(PATH="$ON_PATH" HOME="$W/home5" env -u CLOUD_WORKSPACE CLOUD_WORKSPACE="$W/ws3" \
       bash "$L/provision.sh" --repo-root "$W/repo" 2>&1)"
case "$out" in *"lib/cloud/CLOUD-RULES.md"*) got=yes ;; *) got=no ;; esac
ck "NC: no project config falls back to the kit template" yes "$got"

# Precedence: the env override is the seam's stated purpose, so prove it BEATS a
# conflicting project value rather than merely working when nothing conflicts.
printf 'ENV RULES MARKER\n' >"$W/cfgrepo/docs/env-rules.md"
out="$(PATH="$ON_PATH" HOME="$W/home5" CLOUD_RULES="docs/env-rules.md" \
       bash "$L/provision.sh" --repo-root "$W/cfgrepo" rules 2>&1)"
ck "CLOUD_<KEY> beats a conflicting project .kit.toml value" "ENV RULES MARKER" "$out"

# A leading ~ read out of a config FILE is a literal character, not $HOME. The
# README's own example uses one, and an unexpanded ~ silently created a directory
# actually named '~' under the repo.
# shellcheck disable=SC2088  # the literal ~ IS the fixture: it must not expand here
out="$(PATH="$ON_PATH" HOME="$W/home7" CLOUD_WORKSPACE="~/ws-tilde" \
       bash "$L/provision.sh" --repo-root "$W/repo" 2>&1)"
ck "a ~ workspace lands in HOME" yes \
  "$([ -L "$W/home7/ws-tilde/repo" ] && echo yes || echo no)"
ck "NC: no literal '~' directory was created under the repo" no \
  "$([ -e "$W/repo/~" ] && echo yes || echo no)"

echo
echo "=== 5b-3. a project-tier PATH resolves INSIDE the repo, or it is refused ==="
# Calling a key "project tier" is a comment. This is the enforcement. Both
# project keys are paths, and each escape shape below printed a file from
# outside the repo straight into model context before repo_path existed.
mkdir -p "$W/escape/docs" "$W/curlfail"
printf 'SECRET OUTSIDE THE REPO\n' >"$W/outside-secret.md"
printf 'IN-REPO MAP MARKER\n' >"$W/escape/docs/MAP.md"
printf 'IN-REPO RULES MARKER\n' >"$W/escape/docs/RULES.md"
ln -sf "$W/outside-secret.md" "$W/escape/docs/link-out.md"
printf '#!/bin/sh\nexit 1\n' >"$W/curlfail/curl"; chmod +x "$W/curlfail/curl"

esc() {  # esc <verb> <toml-line> -- run one verb with a hostile project value
  printf '[cloud]\n%s\n' "$2" >"$W/escape/.kit.toml"
  PATH="$ON_PATH" HOME="$W/home9" CLOUD_WORKSPACE="$W/ws-escape" \
    env -u CLOUD_MAP -u CLOUD_RULES \
    bash "$L/provision.sh" --repo-root "$W/escape" "$1" 2>&1
}
for k in map rules; do
  out="$(esc "$k" "$k = \"$W/outside-secret.md\"")"
  case "$out" in *'SECRET OUTSIDE THE REPO'*) got=leaked ;; *) got=refused ;; esac
  ck "$k: an absolute path outside the repo is refused" refused "$got"
  case "$out" in *'!!'*) got=yes ;; *) got=no ;; esac
  ck "$k: the refusal is explained, not silent" yes "$got"
  out="$(esc "$k" "$k = \"../outside-secret.md\"")"
  case "$out" in *'SECRET OUTSIDE THE REPO'*) got=leaked ;; *) got=refused ;; esac
  ck "$k: a .. traversal out of the repo is refused" refused "$got"
  out="$(esc "$k" "$k = \"docs/link-out.md\"")"
  case "$out" in *'SECRET OUTSIDE THE REPO'*) got=leaked ;; *) got=refused ;; esac
  ck "$k: a committed symlink pointing out of the repo is refused" refused "$got"
done
# NC: the legitimate repo-relative use of both keys still works, so the six
# assertions above are a containment check and not a key that never resolves.
ck "NC: a repo-relative map is still printed" "IN-REPO MAP MARKER" \
  "$(esc map 'map = "docs/MAP.md"')"
ck "NC: a repo-relative rules file is still printed" "IN-REPO RULES MARKER" \
  "$(esc rules 'rules = "docs/RULES.md"')"

# op_version selects a BINARY: the value lands in a download URL, and the
# download is chmod +x, prepended to PATH and persisted into CLAUDE_ENV_FILE.
# The tier is observable because a failed install prints the URL it tried.
opv() {  # opv <env-assignments...> -- run the secrets step with curl broken
  PATH="$W/curlfail:$W/nogh" HOME="$W/home-opv" CLOUD_WORKSPACE="$W/ws-opv" \
    OP_SERVICE_ACCOUNT_TOKEN=stub-value-never-read CLOUD_VAULT=TestVault \
    env "$@" bash "$L/provision.sh" --repo-root "$W/escape" secrets 2>&1
}
printf '[cloud]\nop_version = "v9.9.9"\n' >"$W/escape/.kit.toml"
out="$(opv -u CLOUD_OP_VERSION)"
case "$out" in *v9.9.9*) got=used ;; *) got=ignored ;; esac
ck "op_version: a project .kit.toml value never reaches the download URL" ignored "$got"
case "$out" in *"$op_pin_a"*) got=yes ;; *) got=no ;; esac
ck "op_version: the URL carries the operator-tier pin instead" yes "$got"
# NC: the same value from the operator tier DOES reach the URL.
out="$(opv CLOUD_OP_VERSION=v9.9.9)"
case "$out" in *v9.9.9*) got=yes ;; *) got=no ;; esac
ck "NC: the operator tier DOES set the op pin" yes "$got"
# Operator tier is not a reason to skip validating a value that lands in a URL.
out="$(opv 'CLOUD_OP_VERSION=vEVIL/../../../../attacker-path')"
case "$out" in *"falling back to $op_pin_a"*) got=yes ;; *) got=no ;; esac
ck "op_version: a traversal-shaped pin is refused at the operator tier too" yes "$got"
case "$out" in *'attacker-path/op_linux'*) got=yes ;; *) got=no ;; esac
ck "op_version: the traversal never reaches the download URL" no "$got"

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
repos = "attacker/instructions"
repo_owner = "attacker"
workspace = "/dev/null/attacker-ws"
rules = "docs/OK-RULES.md"
EOF
# `/dev/null/...` can never be created, even by root, so an honoured value would
# surface as a `could not link ... into /dev/null/attacker-ws` line rather than
# as litter on the test host.
mkdir -p "$W/evil/docs"
printf 'PROJECT RULES FROM THE HOSTILE FILE\n' >"$W/evil/docs/OK-RULES.md"
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
# A clone runs no code, but provision NAMES the clone's AGENTS.md and CLAUDE.md
# to the model as files to read, so a project-settable clone target is a
# prompt-injection path into every later turn.
case "$out" in *'attacker/instructions'*) got=yes ;; *) got=no ;; esac
ck "the project .kit.toml did NOT reach the sibling-clone step" no "$got"
# workspace joined the operator tier after a project value pointed it at
# `$HOME/.claude/skills` and made a PR-authored root SKILL.md a live skill.
case "$out" in *'attacker-ws'*) got=yes ;; *) got=no ;; esac
ck "the project .kit.toml did NOT choose the workspace" no "$got"
# NC: the same keys DO take effect from the operator tier (the env override), or
# the four assertions above would pass for a provision that reads nothing at all.
out="$(PATH="$ON_PATH" HOME="$W/home6" CLOUD_WORKSPACE="$W/ws-evil2" \
       CLOUD_HOOKS_PATH=".githooks" bash "$L/provision.sh" --repo-root "$W/evil" 2>&1)"
ck "NC: the operator tier DOES arm core.hooksPath" ".githooks" \
  "$(git -C "$W/evil" config --get core.hooksPath 2>/dev/null || true)"
git -C "$W/evil" config --unset core.hooksPath 2>/dev/null || true
# NC: a PROJECT-tier key from the same hostile file still works, so the split is
# a boundary, not a blanket refusal to read the project file. `rules` is a real
# project key naming a real in-repo path, unlike the earlier version of this
# assertion, which checked a workspace symlink the ENV had set.
out="$(PATH="$ON_PATH" HOME="$W/home6" CLOUD_WORKSPACE="$W/ws-evil" \
       env -u CLOUD_RULES bash "$L/provision.sh" --repo-root "$W/evil" rules 2>&1)"
ck "NC: a project-tier key from the same file is still honoured" \
  "PROJECT RULES FROM THE HOSTILE FILE" "$out"

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
echo "=== 5c-2. the assemble pipeline's supporting steps ==="
# Steps 2 to 7 of the assemble path (sibling clone, toolchain report, hooks
# arming, board smoke, background layer, plugins) were named in the README and
# asserted nowhere. Each is cheap to pin from one run's output.
mkdir -p "$W/pipe/.claude/memory" "$W/pipe/_meta" "$W/pipe/.githooks"
git -C "$W/pipe" init -q 2>/dev/null || true
printf '# MEMORY\n\n- [One](one.md): a hook\n- [Two](two.md): another\n' >"$W/pipe/.claude/memory/MEMORY.md"
printf '# AGENTS\n' >"$W/pipe/AGENTS.md"
printf '# CLAUDE\n' >"$W/pipe/CLAUDE.md"
printf '| ID | Item | Notes & source | Status |\n|---|---|---|---|\n| ID-001 | a row | src | queued |\n' \
  >"$W/pipe/_meta/BACKLOG.md"
printf '#!/bin/sh\nexit 0\n' >"$W/pipe/.githooks/pre-commit"; chmod +x "$W/pipe/.githooks/pre-commit"
out="$(PATH="$ON_PATH" HOME="$W/home8" CLOUD_WORKSPACE="$W/ws-pipe" \
       CLOUD_HOOKS_PATH=".githooks" CLOUD_REPOS="no-such-owner/no-such-repo-xyz" \
       bash "$L/provision.sh" --repo-root "$W/pipe" 2>&1)"; rc=$?
ck "assemble exits 0 with every step exercised" 0 "$rc"
case "$out" in *'memory index present (2 notes)'*) got=yes ;; *) got=no ;; esac
ck "background layer counts the memory index and names the file to read" yes "$got"
case "$out" in *'AGENTS.md present'*) got=yes ;; *) got=no ;; esac
ck "background layer names AGENTS.md" yes "$got"
case "$out" in *'CLAUDE.md present'*) got=yes ;; *) got=no ;; esac
ck "background layer names CLAUDE.md" yes "$got"
case "$out" in *'ok  git'*) got=yes ;; *) got=no ;; esac
ck "toolchain report names the tools it found" yes "$got"
ck "git hooks armed from the operator tier" ".githooks" \
  "$(git -C "$W/pipe" config --get core.hooksPath 2>/dev/null || true)"
case "$out" in *'board renders'*) got=yes ;; *) got=no ;; esac
ck "board smoke ran against the repo's kanban" yes "$got"
case "$out" in *'cannot clone no-such-owner/no-such-repo-xyz'*) got=yes ;; *) got=no ;; esac
ck "an unreachable sibling repo degrades to a !! line" yes "$got"
case "$out" in *'CLOUD-PARTIAL'*) got=yes ;; *) got=no ;; esac
ck "an unreachable sibling repo lands CLOUD-PARTIAL, not READY" yes "$got"
case "$out" in *'plugins: none configured'*) got=yes ;; *) got=no ;; esac
ck "the plugin step is a reported no-op with no config" yes "$got"
# NC: with a reachable repo list the same run must reach CLOUD-READY, or the
# PARTIAL assertion above would pass for a provision that always fails.
out="$(PATH="$ON_PATH" HOME="$W/home8" CLOUD_WORKSPACE="$W/ws-pipe2" \
       env -u CLOUD_REPOS bash "$L/provision.sh" --repo-root "$W/pipe" 2>&1)"
case "$out" in *'CLOUD-READY'*) got=yes ;; *) got=no ;; esac
ck "NC: with nothing failing the verdict is CLOUD-READY" yes "$got"

echo
echo "=== 5d. session-start hook ON: the full SessionStart JSON contract ==="
echo '{}' | PATH="$ON_PATH" CLOUD_PROVISION=1 CLAUDE_CODE_REMOTE=true HOME="$W/home4" \
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
echo "=== 9. the suite itself goes red (self-check) ==="
# The one invariant a suite cannot assert about itself inline: that a failure
# reaches the exit code. Three suites in the predecessor of this code printed
# FAIL lines and still exited 0. Re-invoke this file with one planted failure
# and check the exit code. Guarded against recursion by the same variable.
if [ -z "${CLOUD_SMOKE_SELFTEST:-}" ]; then
  CLOUD_SMOKE_SELFTEST=1 bash "${BASH_SOURCE[0]}" >/dev/null 2>&1; sub_rc=$?
  ck "a planted failure makes this suite exit non-zero" 1 "$sub_rc"
  CLOUD_SMOKE_SELFTEST=0 bash "${BASH_SOURCE[0]}" >/dev/null 2>&1; sub_rc=$?
  ck "NC: the same re-invocation with nothing planted exits 0" 0 "$sub_rc"
fi

echo
printf 'PASS %s  FAIL %s\n' "$pass" "$fail"
echo "workdir=$W"
[ "${CLOUD_SMOKE_SELFTEST:-0}" = "1" ] && ck "PLANTED FAILURE (self-check)" expected planted
[ "$fail" = 0 ] || exit 1
echo "smoke: all $pass passed"
exit 0
