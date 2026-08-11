#!/usr/bin/env bash
# cloud.sh -- the cloud subsystem's verb dispatcher.
#
#   cloud provision [--repo-root <p>]   assemble the working layout in a cloud VM
#   cloud vm-setup                      VM-level installs (the Setup script body)
#   cloud install-gh                    just the gh installer
#   cloud rules                         print the cloud rules this session follows
#   cloud map                           print the consumer's routing map
#   cloud repo <name>                   clone one more repo into the workspace
#   cloud secrets                       just the secrets step
#   cloud plugins                       just the behavioral-plugin step
#
# Every VERB exits 0 by design: this subsystem runs on the cloud startup path,
# where a non-zero exit aborts the session before Claude Code starts.
#
# ONE exception, and it matters on that same path: an UNKNOWN verb exits 1, so a
# typo in the environment's Setup-script field would abort the session. That is
# why the documented Setup-script line ends in `|| true`, and why the `|| true`
# is load-bearing rather than decorative. The dispatcher keeps the non-zero exit
# because a silent 0 on a misspelled verb hides the typo forever.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

verb="${1:-}"
[ $# -gt 0 ] && shift
case "$verb" in
  provision)                        exec bash "$SELF_DIR/provision.sh" "$@" ;;
  vm-setup)                         exec bash "$SELF_DIR/vm-setup.sh" "$@" ;;
  install-gh)                       exec bash "$SELF_DIR/install-gh.sh" "$@" ;;
  rules|map|repo|secrets|plugins)   exec bash "$SELF_DIR/provision.sh" "$verb" "$@" ;;
  ""|-h|--help|help)                usage; exit 0 ;;
  *) echo "cloud: unknown verb '$verb'" >&2; usage >&2; exit 1 ;;
esac
