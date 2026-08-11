#!/usr/bin/env bash
# provision.sh -- assemble a usable working layout inside a Claude Code cloud VM.
#
# A cloud session clones ONE repo and nothing else: no user CLAUDE.md, no user
# skills, no plugins, no sibling checkouts, no secrets. This script rebuilds the
# generic half of that around whatever repo the session got. Idempotent; re-run
# freely.
#
#   provision.sh                      # assemble
#   provision.sh map                  # print the consumer's routing map
#   provision.sh repo <name>          # clone one more repo on demand
#   provision.sh repo <owner>/<name>  # non-default owner
#   provision.sh rules                # print the cloud rules this session follows
#   provision.sh secrets              # just the secrets step
#   provision.sh plugins              # just the behavioral-plugin step
#
# Every knob is CONSUMER CONFIG, never a value baked into the kit. With no config
# at all this still does the useful generic work: symlink the repo into a
# workspace, report the toolchain, name the background layer the session reads.
#
# TWO TIERS, because a project's `.kit.toml` rides inside the repo and a pull
# request can therefore set it.
#
#   THE RULE, for whoever adds the next key: a PROJECT key may only name
#   something INSIDE this repo, and the code must ENFORCE that, not just
#   promise it. Anything that reaches outside the repo, runs code, or names a
#   credential is an OPERATOR key and skips the project overlay. When in doubt,
#   take the operator tier.
#
#   key           tier      env override        default
#   ------------  --------  ------------------  ------------------------------
#   map           project   CLOUD_MAP           (none)          repo-relative
#   rules         project   CLOUD_RULES         the kit's CLOUD-RULES.md
#   workspace     operator  CLOUD_WORKSPACE     $HOME/workspace
#   op_version    operator  CLOUD_OP_VERSION    v2.31.1
#   repos         operator  CLOUD_REPOS         (none)
#   repo_owner    operator  CLOUD_REPO_OWNER    (none)
#   plugins       operator  CLOUD_PLUGINS       (none)
#   hooks_path    operator  CLOUD_HOOKS_PATH    (none, never auto-detected)
#   vault         operator  CLOUD_VAULT         (none)
#   canary_ref    operator  CLOUD_CANARY_REF    op://<vault>/cloud-canary/credential
#
# The two project keys are PATHS, so `repo_path` resolves each one against the
# repo root and refuses anything that escapes it. Naming the tier is not the
# control; the resolution check is.
#
# `workspace` is operator-tier because it names a directory OUTSIDE the repo and
# the assemble step creates a symlink there. A project-settable value pointed it
# at `$HOME/.claude/skills`, which turned a PR-authored root `SKILL.md` into a
# live skill in the same session (reproduced). Constraining it to "under the
# home" would not have stopped that, because that path IS under the home.
#
# `op_version` is operator-tier because it selects a BINARY: the value is
# interpolated into a download URL, and the download is then chmod +x, prepended
# to PATH and persisted into CLAUDE_ENV_FILE. It is additionally validated
# against a version shape, because "operator-tier" is not a reason to skip
# validating a value that lands in a URL.
#
# `repos` and `repo_owner` are operator keys even though a clone runs no code:
# the clone's AGENTS.md and CLAUDE.md are then NAMED to the model as files to
# read, so a project-settable clone target is a prompt-injection path into every
# later turn. The two switches CLOUD_PROVISION and CLOUD_DASH_GUARD are master
# gates read by the hooks, not `[cloud]` keys, and nothing here resolves them.
#
# Repo-root resolution follows the kit's existing consumer pattern: `--repo-root`,
# then $REPO_ROOT, then $CLAUDE_PROJECT_DIR, then the cwd's git toplevel, then cwd.
# It NEVER hard-fails: a non-zero exit from anything on the cloud startup path
# aborts the whole session before Claude Code starts (observed live, twice).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "$SELF_DIR/../.." && pwd)"

say()  { printf '%s\n' "$*"; }
fail=0
note() { say "  !! $*"; fail=1; }

# ---------------------------------------------------------------- repo root
# Leading flags only, then `break`, so the verb and its arguments stay in "$@"
# untouched. Collecting them into a string and re-splitting would lose a path
# containing a space, which a configurable workspace can easily produce.
ROOT_FLAG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo-root) ROOT_FLAG="${2:-}"; shift 2 ;;
    --repo-root=*) ROOT_FLAG="${1#--repo-root=}"; shift ;;
    *) break ;;
  esac
done

ROOT="$ROOT_FLAG"
[ -n "$ROOT" ] || ROOT="${REPO_ROOT:-}"
[ -n "$ROOT" ] || ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [ -z "$ROOT" ]; then
  # Root running against a repo owned by another user trips git's ownership
  # guard, so `git rev-parse` returns empty even inside a clone. Mark it safe,
  # then retry. `.git` is a DIRECTORY in a normal clone and a FILE in a
  # worktree, so test for existence, not for a directory.
  #
  # Marking a directory safe writes the operator's GLOBAL ~/.gitconfig, so the
  # write is gated to the context that needs it. Ungated, a hand-run of this
  # script on a workstation mutated the operator's own git config. The cloud VM
  # is the only place root meets someone else's checkout here.
  _cwd="$(pwd -P 2>/dev/null || true)"
  if [ -n "$_cwd" ] && [ -e "$_cwd/.git" ]; then
    if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ] && [ "$(uname -s)" = "Linux" ]; then
      git config --global --add safe.directory "$_cwd" 2>/dev/null || true
    fi
    ROOT="$(git -C "$_cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$_cwd")"
  else
    ROOT="$_cwd"
  fi
fi
[ -n "$ROOT" ] || { say "ok  provision: no repo reachable from here, nothing to assemble"; exit 0; }
cd "$ROOT" 2>/dev/null || true

# ---------------------------------------------------------------- config
# Loaded in a function scope so the resolver's own `${1:-}` selftest check never
# sees this script's positional parameters (same guard adopt.sh uses).
_load_config_resolver() {
  # shellcheck source=lib/config/kit-config.sh
  source "$KIT_ROOT/lib/config/kit-config.sh"
}
RESOLVER_OK=1
_load_config_resolver 2>/dev/null || RESOLVER_OK=0

# Two resolution tiers, because a project's `.kit.toml` rides inside the repo and
# a pull request can therefore set it.
#
#   cfg      env CLOUD_<KEY> > project .kit.toml > kit-root kit.toml > default
#   cfg_root env CLOUD_<KEY> > kit-root kit.toml > default   (project overlay SKIPPED)
#
# A key whose value SELECTS CODE TO RUN or NAMES A CREDENTIAL uses cfg_root. The
# resolver already ships `kit_config_get_root` for exactly this class. Concretely:
# `plugins` installs and runs a marketplace plugin unattended, and `hooks_path`
# arms `core.hooksPath`, which turns otherwise-inert scripts in the repo into
# code that every later git command executes. Neither may be settable by a
# branch under review. Everything else is inert data (a path to cat, a clone
# target, a directory name) and stays project-overridable, which is the point of
# the seam.
#
# Indirect expansion, never `eval`: a root-context `eval` over an environment
# variable was a reproduced command injection in the predecessor of this script.
_cfg_env() {
  local envname
  envname="CLOUD_$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  printf '%s' "${!envname:-}"
}

#
# KIT_CONFIG_ROOT is PINNED to the kit install this script belongs to. The
# resolver otherwise takes that path from the environment, so the kit-root file
# that is supposed to be the operator-owned half of the split could be
# redirected at a file inside the repo. Pinning it means the operator tier reads
# one file whose location no caller chooses.
cfg() {
  local key="$1" def="${2:-}" v
  v="$(_cfg_env "$key")"
  [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  if [ "$RESOLVER_OK" -eq 1 ]; then
    v="$(KIT_PROJECT_ROOT="$ROOT" KIT_CONFIG_ROOT="$KIT_ROOT" \
         kit_config_get "cloud.$key" "" 2>/dev/null || true)"
    [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  fi
  printf '%s' "$def"
}

cfg_root() {
  local key="$1" def="${2:-}" v
  v="$(_cfg_env "$key")"
  [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  if [ "$RESOLVER_OK" -eq 1 ]; then
    v="$(KIT_CONFIG_ROOT="$KIT_ROOT" kit_config_get_root "cloud.$key" "" 2>/dev/null || true)"
    [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  fi
  printf '%s' "$def"
}

# HOME differs by context: the Setup script runs as root (HOME=/root), so the
# workspace it would build is not the one the session user later sees. Assemble
# under the SESSION user's home when we can identify it.
# `getent passwd`, never `eval echo ~$USER`: this branch can run AS ROOT, and
# eval on an environment variable is command execution. A crafted SUDO_USER
# containing a command substitution ran arbitrary commands as root (reproduced).
_home="$HOME"
if [ "$(id -u)" = "0" ] && [ -n "${SUDO_USER:-}" ]; then
  _lookup="$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)"
  [ -n "$_lookup" ] && _home="$_lookup"
fi

# A leading `~` read out of a config FILE is a literal character, not the home
# directory: bash expands a tilde only in an unquoted literal word, never in the
# contents of a variable. Without this, `workspace = "~/workspace/acme"` made
# `mkdir -p` create a directory actually named `~` under the repo, silently, with
# no `!!` line. Expanded here, once, where the value enters.
expand_home() {  # expand_home <path>
  # shellcheck disable=SC2088  # the literal ~ is the INPUT being stripped, not an expansion
  case "$1" in
    "~") printf '%s' "$_home" ;;
    "~/"*) printf '%s%s' "$_home" "${1#\~}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# The tier split, declared ONCE. The suite reads these two lists out of this
# source and fails if a key is read through the wrong resolver, or belongs to
# neither list.
#
# That lint checks CONSISTENCY, not CORRECTNESS. It proves each key is read
# through the resolver its list names; it cannot know whether the list is the
# right one for that key. Three keys sat in the project list, passed this lint
# for the whole life of the branch, and each one reached outside the repo. The
# lint is a spelling check on the tier split, and the enforcement for a
# project-tier PATH is `repo_path`, below.
# shellcheck disable=SC2034  # read by lib/cloud/tests/smoke.sh, not by this script
CLOUD_PROJECT_KEYS="map rules"
# shellcheck disable=SC2034  # same
CLOUD_OPERATOR_KEYS="workspace op_version repos repo_owner plugins hooks_path vault canary_ref"

# ROOT resolved through symlinks: every containment test below compares against
# this, never against the possibly-symlinked ROOT the caller handed us.
ROOT_P="$(cd "$ROOT" 2>/dev/null && pwd -P)" || ROOT_P=""
[ -n "$ROOT_P" ] || ROOT_P="$ROOT"

# repo_path <key> <value> -- resolve a PROJECT-tier path against the repo root.
# THE rule for a project key is that it may only name something inside this
# repo, and this is where that rule is enforced. Rejected: an absolute path, a
# leading `~`, any `..` segment, a path whose directory resolves outside the
# repo (an intermediate symlink), and a final component that is itself a symlink
# (a committed `docs/x.md -> /etc/foo` would otherwise be read and printed into
# model context).
#
# The answer comes back in REPO_PATH_OUT, not on stdout, because the refusal
# reason goes through `note`: a `$( )` call site would swallow that reason INTO
# the value, leave the value non-empty, and print the note twice (caught in the
# first run of this guard's own control).
REPO_PATH_OUT=""
repo_path() {  # repo_path <key> <value>  -> REPO_PATH_OUT, 1 on refusal
  local key="$1" val="$2" dir base out
  REPO_PATH_OUT=""
  [ -n "$val" ] || return 1
  case "$val" in
    /*)  note "$key: '$val' is absolute; a project key may only name a path inside this repo"; return 1 ;;
    "~"*) note "$key: '$val' starts with ~; a project key may only name a path inside this repo"; return 1 ;;
  esac
  case "/$val/" in
    */../*) note "$key: '$val' contains '..'; a project key may only name a path inside this repo"; return 1 ;;
  esac
  dir="$(cd "$ROOT_P/$(dirname "$val")" 2>/dev/null && pwd -P)" || dir=""
  [ -n "$dir" ] || { note "$key: '$val' does not resolve inside this repo"; return 1; }
  base="$(basename "$val")"
  out="$dir/$base"
  case "$out" in
    "$ROOT_P"/*) ;;
    *) note "$key: '$val' resolves outside the repo ($out)"; return 1 ;;
  esac
  if [ -L "$out" ]; then
    note "$key: '$val' is a symlink; a project key may not point out of the repo through one"
    return 1
  fi
  REPO_PATH_OUT="$out"
}

WS="$(expand_home "$(cfg_root workspace "$_home/workspace")")"
MAP_RAW="$(cfg map "")"
RULES_RAW="$(cfg rules "")"
MAP=""; [ -n "$MAP_RAW" ] && repo_path map   "$MAP_RAW"   && MAP="$REPO_PATH_OUT"
RULES=""; [ -n "$RULES_RAW" ] && repo_path rules "$RULES_RAW" && RULES="$REPO_PATH_OUT"

# The op pin selects a binary to download, chmod +x and put on PATH, so it is
# validated as well as operator-tier: a value like `vX/../../../attacker` built
# a traversal-shaped download URL. A bad pin falls back to the default rather
# than failing the session, per the exits-0 invariant.
OP_DEFAULT_VERSION=v2.31.1
OP_VERSION="$(cfg_root op_version "$OP_DEFAULT_VERSION")"
# `case`, not `grep -qE`: grep matches LINE-wise, so a multi-line value passes
# when ANY line matches and the rest still reaches the URL. Verified:
# CLOUD_OP_VERSION=$'v1.0\n../../../../attacker-path' was ACCEPTED by the grep
# form. A case glob tests the whole string, so a newline cannot hide behind a
# valid first line. Host stays pinned either way, so this was low severity, but
# operator tier is not a reason to skip validating a value that lands in a URL.
case "$OP_VERSION" in
  v[0-9]*|[0-9]*) _op_shape=ok ;;
  *) _op_shape=bad ;;
esac
case "$OP_VERSION" in
  *[!v0-9.]*) _op_shape=bad ;;
esac
if [ "$_op_shape" != ok ]; then
  note "op_version '$OP_VERSION' is not a version string; falling back to $OP_DEFAULT_VERSION"
  OP_VERSION="$OP_DEFAULT_VERSION"
fi
# Operator-owned tier: a branch under review may not set any of these.
REPOS="$(cfg_root repos "")"
REPO_OWNER="$(cfg_root repo_owner "")"
PLUGINS="$(cfg_root plugins "")"
VAULT="$(cfg_root vault "")"
CANARY_REF="$(cfg_root canary_ref "${VAULT:+op://$VAULT/cloud-canary/credential}")"
HOOKS_PATH="$(cfg_root hooks_path "")"
CANARY_VALUE="${CLOUD_CANARY_VALUE:-CLOUD-CANARY-OK}"

# The rules a cloud session follows: the consumer's own file when it names one,
# else the kit's portable template. RULES is already repo_path-resolved, so a
# value that pointed outside the repo is empty here and falls back to the kit's
# own template, which is the safe direction to fail.
rules_file() {
  if [ -n "$RULES" ]; then
    printf '%s' "$RULES"
  else
    printf '%s' "$KIT_ROOT/lib/cloud/CLOUD-RULES.md"
  fi
}

mkdir -p "$WS" 2>/dev/null || true

# ---------------------------------------------------------------- helpers
# Clone helper: plain https first (the cloud proxy injects credentials there),
# gh as the fallback (covers a local run where https auth is non-interactive).
# Every external call is time-capped: the SessionStart hook has a bounded budget
# and one stalled clone must not starve the steps after it.
fetch() {  # owner/name dest
  local slug="$1" dest="$2"
  [ -e "$dest" ] && { say "ok  $slug present"; return 0; }
  if cap 60 git clone --depth 1 "https://github.com/$slug.git" "$dest" >/dev/null 2>&1; then
    say "ok  cloned $slug"
  elif command -v gh >/dev/null 2>&1 && cap 60 gh repo clone "$slug" "$dest" -- --depth 1 >/dev/null 2>&1; then
    say "ok  cloned $slug (gh)"
  else
    note "cannot clone $slug (the proxy may not cover sibling repos)"
    return 1
  fi
}

# Background layer of a repo: its own memory index and conventions. The files
# ride in with the clone, but no user-level hook injects them here, so name them
# and tell the session to read them. Counts, never contents. Reports only, never
# fails: a repo without memory is normal, not a broken provision.
background() {  # dir label
  local dir="$1" label="$2" n
  if [ -f "$dir/.claude/memory/MEMORY.md" ]; then
    n="$(grep -c '^- \[' "$dir/.claude/memory/MEMORY.md" 2>/dev/null || true)"
    say "ok  $label memory index present (${n:-?} notes): READ $label/.claude/memory/MEMORY.md"
  else
    say "ok  $label carries no .claude/memory/MEMORY.md"
  fi
  [ -f "$dir/AGENTS.md" ] && say "ok  $label AGENTS.md present: read before touching code"
  [ -f "$dir/CLAUDE.md" ] && say "ok  $label CLAUDE.md present: read before working in this repo"
  return 0
}

# cap <seconds> <cmd...> -- run with a timeout where one is available. The
# SessionStart hook has a bounded budget and a slow clone must not eat it: a
# capped failure degrades to the rules prose, which is the floor this improves on.
cap() {
  if command -v timeout >/dev/null 2>&1; then timeout "$@"; else shift; "$@"; fi
}

# An `export` inside this script dies with the process. CLAUDE_ENV_FILE is the
# documented way a SessionStart hook hands a variable to every later Bash
# command: "write export statements to CLAUDE_ENV_FILE. Use append (>>) to
# preserve variables set by other hooks." Without this, an installed `op` is
# invisible to the very next command. Append-once, so re-provisioning does not
# stack duplicate lines.
persist_path() {
  local line='export PATH="$HOME/.local/bin:$PATH"'
  [ -n "${CLAUDE_ENV_FILE:-}" ] || return 0
  grep -qxF "$line" "$CLAUDE_ENV_FILE" 2>/dev/null && return 0
  printf '%s\n' "$line" >>"$CLAUDE_ENV_FILE" 2>/dev/null || true
}

install_op() {
  local arch url tmp rc=0
  [ "$(uname -s)" = "Linux" ] || { note "secrets: op missing (install it for $(uname -s) by hand)"; return 1; }
  case "$(uname -m)" in
    x86_64|amd64)  arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) note "secrets: no op build for $(uname -m)"; return 1 ;;
  esac
  command -v unzip >/dev/null 2>&1 || { note "secrets: unzip missing, cannot install op"; return 1; }
  url="https://cache.agilebits.com/dist/1P/op2/pkg/$OP_VERSION/op_linux_${arch}_$OP_VERSION.zip"
  tmp="$(mktemp -d)"
  mkdir -p "$HOME/.local/bin"
  # --max-time, like both sibling downloads (60 for a clone, 150 for the gh
  # install): without it a stalled connection holds the SessionStart hook open
  # until the platform kills the whole hook, which loses every step after this
  # one instead of just this one.
  if curl -fsSL --max-time 120 "$url" -o "$tmp/op.zip" \
     && unzip -oq "$tmp/op.zip" op -d "$HOME/.local/bin"; then
    chmod +x "$HOME/.local/bin/op"
    export PATH="$HOME/.local/bin:$PATH"   # this process only
    persist_path                           # every later Bash command
    say "ok  secrets: installed op $OP_VERSION"
  else
    note "secrets: op install failed ($url)"
    rc=1
  fi
  # Explicit, on both paths: the download dir leaked on every call, green or
  # red. A RETURN trap would be the tidier shape and is not worth the bash
  # inheritance rules it drags in.
  rm -rf "$tmp"
  return "$rc"
}

# Secrets. A cloud session bootstraps from ONE env var (OP_SERVICE_ACCOUNT_TOKEN,
# a read-only service account scoped to a single sandbox vault); every other
# value stays an op:// reference resolved at runtime, exactly like local. Most
# sessions carry no token at all, which is a normal repo-only session, not a
# failure. Nothing here ever prints a secret: the canary is compared in-process
# and only the verdict is printed.
secrets() {
  local got
  if [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
    say "ok  secrets: none configured (repo-only session)"
    return 0
  fi
  if [ -z "$CANARY_REF" ]; then
    note "secrets: a token is present but no canary_ref is configured; cannot verify the vault"
    return 1
  fi
  if [ -x "$HOME/.local/bin/op" ]; then export PATH="$HOME/.local/bin:$PATH"; persist_path; fi
  command -v op >/dev/null 2>&1 || install_op || return 1
  got="$(op read "$CANARY_REF" 2>/dev/null || true)"
  if [ "$got" = "$CANARY_VALUE" ]; then
    say "ok  secrets: ${VAULT:-vault} reachable (canary verified)"
  else
    note "secrets: canary check failed ($CANARY_REF); token or vault is wrong"
    return 1
  fi
}

# gh. The cloud image does not ship it, so fetch()'s gh fallback would be dead
# code in a VM and any skill that shells out to gh would fail. The RIGHT home
# for this install is the environment's Setup script field, which the
# environment cache keeps. This is the fallback for an environment whose Setup
# script is not set yet, and it is why the failure is a !! line, not a stop.
install_gh() {
  command -v gh >/dev/null 2>&1 && { say "ok  gh"; return 0; }
  [ "$(uname -s)" = "Linux" ] || { note "missing gh"; return 1; }
  if cap 150 bash "$SELF_DIR/install-gh.sh" >/dev/null 2>&1 \
     && command -v gh >/dev/null 2>&1; then
    say "ok  gh installed"
  else
    note "gh install failed; see $SELF_DIR/install-gh.sh"
    return 1
  fi
}

# Behavioral plugins. A plugin enabled only in USER settings never reaches a VM,
# and declaring one in the repo's .claude/settings.json was tested and REJECTED:
# it writes a second, project-scope record into the shared per-user plugin
# registry on the operator's own machine, so the plugin is then listed twice and
# can no longer be disabled locally. The install runs here instead. Anthropic's
# docs require it anyway: a plugin that only a project's settings enable, coming
# from an external marketplace, "doesn't load until the team member installs
# it". A VM is that team member, and no human is there to answer the prompt.
#
# LINUX-GATED inside the function, not at the caller, because provision is also
# runnable by hand on a Mac, where this step must be a no-op.
# Config format: comma-separated `<plugin@marketplace>|<owner/repo>` pairs.
plugins() {
  [ -n "$PLUGINS" ] || { say "ok  plugins: none configured"; return 0; }
  [ "$(uname -s)" = "Linux" ] || { say "ok  plugins: not Linux, leaving the host alone"; return 0; }
  command -v claude >/dev/null 2>&1 || { say "ok  plugins: claude CLI absent, skipping"; return 0; }
  local have pair id slug
  have="$(cap 15 claude plugin list 2>/dev/null || true)"
  for pair in $(printf '%s' "$PLUGINS" | tr ',' ' '); do
    id="${pair%%|*}"; slug="${pair##*|}"
    [ -n "$id" ] || continue
    case "$have" in *"$id"*) say "ok  plugins: $id already present"; continue ;; esac
    [ "$slug" != "$id" ] && cap 15 claude plugin marketplace add "$slug" >/dev/null 2>&1 || true
    if cap 15 claude plugin install "$id" >/dev/null 2>&1; then
      say "ok  plugins: $id installed (skills load after a session reload)"
    else
      note "plugins: $id unavailable, follow the cloud rules prose instead"
    fi
  done
}

# ---------------------------------------------------------------- verbs
case "${1:-}" in
  map)
    if [ -z "$MAP_RAW" ]; then
      say "ok  map: this repo configures no routing map ([cloud] map in .kit.toml)"
      exit 0
    fi
    # An empty MAP with a non-empty MAP_RAW means repo_path already refused the
    # value and printed the reason. Printing the file anyway is the whole bug.
    [ -n "$MAP" ] || exit 0
    [ -f "$MAP" ] || { note "map: $MAP missing"; exit 0; }
    cat "$MAP"
    exit 0
    ;;
  rules)
    r="$(rules_file)"
    [ -f "$r" ] || { note "rules: $r missing"; exit 0; }
    cat "$r"
    exit 0
    ;;
  repo)
    arg="${2:-}"
    [ -n "$arg" ] || { note "usage: provision.sh repo <name> | <owner>/<name>"; exit 0; }
    case "$arg" in
      */*) slug="$arg" ;;
      *)   [ -n "$REPO_OWNER" ] || { note "repo: a bare name needs [cloud] repo_owner"; exit 0; }
           slug="$REPO_OWNER/$arg" ;;
    esac
    dir="$WS/${slug##*/}"
    fetch "$slug" "$dir" && background "$dir" "${slug##*/}"
    exit 0
    ;;
  secrets) secrets; exit 0 ;;
  plugins) plugins; exit 0 ;;
esac

# ---------------------------------------------------------------- assemble
# 1. The session repo at a stable workspace path, so a cross-repo command that
#    expects a workspace layout finds it.
repo_name="$(basename "$ROOT")"
if [ ! -e "$WS/$repo_name" ]; then
  if ln -s "$ROOT" "$WS/$repo_name" 2>/dev/null; then
    say "ok  $repo_name -> $ROOT (symlink)"
  else
    note "could not link $ROOT into $WS"
  fi
else
  say "ok  $repo_name present in $WS"
fi

# 2. Sibling repos the consumer declared. Cloning depends on the platform's
#    GitHub proxy covering repos beyond the session repo; when it does not, this
#    reports and the session keeps working in the repo it has.
#
#    The 60s per-clone cap bounds ONE clone, not the loop. Three unreachable
#    siblings at 60s plus the 150s gh install already exceed the SessionStart
#    budget, and blowing that budget kills the whole hook, losing every step
#    after this one. So the loop carries its own deadline and reports the
#    siblings it skipped, which is the same degradation the per-clone cap gives.
CLONE_BUDGET=90
clone_deadline=$(( $(date +%s) + CLONE_BUDGET ))
for r in $(printf '%s' "$REPOS" | tr ',' ' '); do
  [ -n "$r" ] || continue
  if [ "$(date +%s)" -ge "$clone_deadline" ]; then
    note "repos: the ${CLONE_BUDGET}s clone budget is spent; '$r' and any after it were skipped (clone on demand: provision.sh repo $r)"
    break
  fi
  case "$r" in
    */*) slug="$r" ;;
    *)   [ -n "$REPO_OWNER" ] || { note "repos: '$r' is a bare name and no repo_owner is set"; continue; }
         slug="$REPO_OWNER/$r" ;;
  esac
  d="$WS/${slug##*/}"
  fetch "$slug" "$d" && background "$d" "${slug##*/}"
done

# 3. Toolchain sanity, report-only (the cloud base image varies and is undocumented).
for t in git jq python3; do
  if command -v "$t" >/dev/null 2>&1; then say "ok  $t"; else note "missing $t"; fi
done
install_gh

# 4. Repo git hooks. core.hooksPath is LOCAL git config, so it is not part of a
#    clone: without this the repo's commit-message and pre-commit checks never
#    fire in a cloud session. Idempotent.
#
#    EXPLICIT ONLY, never a bare directory probe. Arming core.hooksPath turns
#    scripts that a plain clone leaves inert into code every later git command
#    runs. Auto-arming a `.githooks` directory found in the tree would hand that
#    to whatever branch the session checked out. The value is operator-tier
#    (kit-root config or the CLOUD_HOOKS_PATH env), so a branch under review
#    cannot introduce it.
hp="$HOOKS_PATH"
if [ -n "$hp" ]; then
  if [ ! -d "$ROOT/$hp" ]; then
    note "hooks_path '$hp' is configured but $ROOT/$hp does not exist; hooks left off"
  elif git -C "$ROOT" config core.hooksPath "$hp" 2>/dev/null; then
    say "ok  git hooks armed (core.hooksPath=$hp)"
  else
    note "could not set core.hooksPath; the repo's commit checks are off"
  fi
fi

# 5. Board smoke, when this repo keeps a kit kanban. A failure here means the
#    kit install is not reachable, which the session needs to know.
for b in "$ROOT/_meta/BACKLOG.md" "$ROOT/BACKLOG.md"; do
  [ -f "$b" ] || continue
  if cap 15 bash "$KIT_ROOT/bin/board" board --backlog-file "$b" >/dev/null 2>&1; then
    say "ok  board renders (${b#"$ROOT"/})"
  else
    note "board render failed for ${b#"$ROOT"/} (is the kit install complete?)"
  fi
  break
done

# 6. Background layer of the session repo.
background "$ROOT" "$repo_name"

# 7. Behavioral plugins (Linux-gated inside the function).
plugins

# 8. Secrets, only when the environment carries a service-account token.
secrets

say ""
say "Cloud rules for this session: $(rules_file)"
[ -n "$MAP" ] && say "Routing: which repo owns the work -> provision.sh map"
if [ "$fail" = 0 ]; then
  say "CLOUD-READY"
else
  say "CLOUD-PARTIAL: see the !! lines above. Clone more repos on demand:"
  say "  bash $SELF_DIR/provision.sh repo <name>"
fi
# Always exit 0 on the assemble path. A partial layout is a session that still
# works; a non-zero exit here aborts the whole cloud session before Claude Code
# starts (observed live: "Setup script failed", then no session at all). The !!
# lines are the signal, the exit code is not.
exit 0
