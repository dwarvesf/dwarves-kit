#!/usr/bin/env bash
# install-gh.sh -- put the gh CLI in /usr/local/bin on a Linux cloud VM.
#
# ONE installer, called from two places, because the same bug lived in both:
# vm-setup.sh (root, once per environment cache generation) and provision.sh's
# SessionStart fallback (session user, every session). Both used apt and both
# failed the same way, so the fix belongs here, not in each caller.
#
# Why the release tarball is the PRIMARY and apt is only the fallback:
#
#   - A live cloud session printed `!!  gh install failed (continuing)` from the
#     apt path, so apt is empirically not reliable in this image.
#   - apt needs archive.ubuntu.com AND the `universe` component AND a working
#     plain-HTTP path through the security proxy. Three things to be true.
#   - Even when apt works, noble ships gh 2.45.0 (Feb 2024). The tarball is
#     current.
#
# Known ceiling: the cloud GitHub proxy scopes release-asset requests to the
# repositories attached to the session, so cli/cli may answer 403. That is why
# apt survives as the fallback and why every path still exits 0.
#
# Budget: one ~12 MB download, curl capped at 90s. The caller's whole setup
# script must finish inside roughly five minutes.
#
# Knobs:
#   GH_VERSION            pinned release, e.g. v2.97.0
#   GH_ARCH               force the asset arch instead of deriving it (testing)
#   GH_INSTALL_PREFIX     install dir, default /usr/local/bin (testing)
#   GH_INSTALL_DRY_RUN    print the URL that WOULD be fetched, then exit 0
set -u

GH_VERSION="${GH_VERSION:-v2.97.0}"
GH_INSTALL_PREFIX="${GH_INSTALL_PREFIX:-/usr/local/bin}"

if [ -z "${GH_ARCH:-}" ]; then
  case "$(uname -m)" in
    x86_64|amd64) GH_ARCH=amd64 ;;
    aarch64|arm64) GH_ARCH=arm64 ;;
    *) GH_ARCH="" ;;
  esac
fi

say() { printf '%s\n' "$*"; }

# The asset name carries the version WITHOUT the leading v; the tag carries it
# with. Getting that wrong is a 404, so both forms come from one variable.
gh_url() {
  v="${GH_VERSION#v}"
  printf 'https://github.com/cli/cli/releases/download/v%s/gh_%s_linux_%s.tar.gz\n' \
    "$v" "$v" "$GH_ARCH"
}

if [ -n "${GH_INSTALL_DRY_RUN:-}" ]; then
  [ -n "$GH_ARCH" ] || { say "!!  unknown arch $(uname -m)"; exit 0; }
  gh_url
  exit 0
fi

# Linux-only from HERE, the point where we would actually put a binary on the
# system. URL construction and dry-run above stay portable so the logic is
# testable on a Mac. A gate at the TOP of the file would make those branches
# unreachable off Linux, which is how the first version of this suite went
# false-green. The hazard being gated is real: `uname -m` on Apple silicon
# reports arm64, which maps to the LINUX arm64 asset, and the install escalates
# with `sudo -n` into /usr/local/bin.
[ "$(uname -s)" = "Linux" ] || { say "ok  install-gh: not Linux, nothing to install"; exit 0; }

if command -v gh >/dev/null 2>&1; then
  say "ok  gh present"
  exit 0
fi

# The install dir usually needs root. vm-setup already is root; provision may
# not be. Writability decides, so a test can point the prefix at a temp dir and
# still exercise the download and apt branches below.
SUDO=""
if [ ! -w "$GH_INSTALL_PREFIX" ]; then
  if sudo -n true >/dev/null 2>&1; then SUDO="sudo -n"; else
    say "!!  $GH_INSTALL_PREFIX not writable and no root, skipping gh"
    exit 0
  fi
fi

# --- primary: the release tarball ---------------------------------------------
if [ -z "$GH_ARCH" ]; then
  say "!!  unknown arch $(uname -m), skipping the gh tarball"
elif ! command -v curl >/dev/null 2>&1; then
  say "!!  no curl, skipping the gh tarball"
else
  v="${GH_VERSION#v}"
  tmp="$(mktemp -d)"
  # --strip-components=2 with the member named in full: no --wildcards, which
  # GNU tar needs and BSD tar rejects, so this line also runs on a Mac.
  if curl -fsSL --max-time 90 "$(gh_url)" -o "$tmp/gh.tgz" 2>/dev/null \
     && tar -xzf "$tmp/gh.tgz" -C "$tmp" --strip-components=2 \
          "gh_${v}_linux_${GH_ARCH}/bin/gh" 2>/dev/null \
     && $SUDO install -m 0755 "$tmp/gh" "$GH_INSTALL_PREFIX/gh" 2>/dev/null; then
    rm -rf "$tmp" 2>/dev/null
    say "ok  gh installed (tarball ${GH_VERSION})"
    exit 0
  fi
  rm -rf "$tmp" 2>/dev/null
  say "!!  gh tarball failed, trying apt"
fi

# --- fallback: apt, which may work in some images ------------------------------
if command -v apt-get >/dev/null 2>&1 \
   && $SUDO env DEBIAN_FRONTEND=noninteractive \
        sh -c 'apt-get update -qq && apt-get install -y -qq gh' >/dev/null 2>&1; then
  say "ok  gh installed (apt)"
else
  say "!!  gh install failed (continuing)"
fi

# Load-bearing: the environment Setup script aborts the session on a non-zero exit.
exit 0
