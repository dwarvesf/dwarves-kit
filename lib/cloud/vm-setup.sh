#!/usr/bin/env bash
# vm-setup.sh -- VM-level installs for a Claude Code cloud environment.
#
# This is the REAL body of the environment's Setup script field. That field
# holds only a short locator (see lib/cloud/README.md), so this logic stays
# versioned, reviewable and testable in the kit instead of rotting inside a
# textarea in a web dashboard.
#
# Context this runs in, all three of which have already broken a live session:
#   - as ROOT, before Claude Code launches
#   - from a cwd that is NOT the repo (never use a relative path)
#   - a non-zero exit ABORTS the session, so every failure degrades to a line
#
# What belongs here rather than in the SessionStart hook: anything installed
# into the FILESYSTEM. The setup script is covered by environment caching (the
# snapshot is taken after it runs), so an install here is paid once per cache
# generation instead of once per session. Anything repo-relative does NOT
# belong here: a resumed session on a cached environment never re-runs it.
#
# Budget: the whole setup script must finish inside roughly five minutes.
#
# Knobs: OP_VERSION (pinned 1Password CLI release), OP_INSTALL_PREFIX.
set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
say() { printf '%s\n' "$*"; }

# Each install is Linux-gated AT ITS OWN POINT of installation, never at the top
# of this file. A top gate makes every branch below unreachable off Linux, which
# is how the first version of the test suite went false-green. The hazard being
# gated is real: `uname -m` on Apple silicon reports arm64, which maps to the
# LINUX arm64 asset, installed into a system dir with `sudo -n`.
is_linux() { [ "$(uname -s)" = "Linux" ]; }

# --- gh: not shipped in the cloud image, and ported skills shell out to it ---
# Delegated to install-gh.sh so the Setup script and provision's SessionStart
# fallback share ONE installer. It is tarball-first, apt-fallback, and exits 0
# on every path (it carries its own Linux gate at its own install point).
bash "$SELF_DIR/install-gh.sh" || say "!!  gh installer errored (continuing)"

# --- op (1Password CLI): only useful when the environment carries a token ---
# Needs cache.agilebits.com on the network allowlist. Absent that, this prints
# a line and the session continues without secret resolution.
OP_VERSION="${OP_VERSION:-v2.31.1}"
OP_INSTALL_PREFIX="${OP_INSTALL_PREFIX:-/usr/local/bin}"
if command -v op >/dev/null 2>&1; then
  say "ok  op present"
elif ! is_linux; then
  say "ok  vm-setup: not Linux, skipping the op install"
else
  case "$(uname -m)" in
    x86_64|amd64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) arch="" ;;
  esac
  if [ -z "$arch" ]; then
    say "!!  unknown arch $(uname -m), skipping op"
  else
    command -v unzip >/dev/null 2>&1 || apt-get install -y -qq unzip >/dev/null 2>&1 || true
    command -v curl  >/dev/null 2>&1 || apt-get install -y -qq curl  >/dev/null 2>&1 || true
    tmp="$(mktemp -d)"
    url="https://cache.agilebits.com/dist/1P/op2/pkg/${OP_VERSION}/op_linux_${arch}_${OP_VERSION}.zip"
    if curl -fsSL --max-time 120 "$url" -o "$tmp/op.zip" 2>/dev/null \
       && unzip -oq "$tmp/op.zip" op -d "$OP_INSTALL_PREFIX" 2>/dev/null; then
      chmod +x "$OP_INSTALL_PREFIX/op" 2>/dev/null || true
      say "ok  op installed (${OP_VERSION})"
    else
      say "!!  op install failed (is cache.agilebits.com allowlisted?)"
    fi
    rm -rf "$tmp" 2>/dev/null || true
  fi
fi

say "VM-SETUP-DONE"
# Load-bearing: a non-zero exit here kills the session before Claude Code starts.
exit 0
