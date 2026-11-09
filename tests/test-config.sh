#!/usr/bin/env bash
# test-config.sh -- the config-layer resolver (lib/config/kit-config.sh).
# Delegates to the resolver's own selftest (precedence, comment-strip, defaults).
set -euo pipefail
# Fence off the host operator kit.toml: a real operator file must not change what this suite asserts.
export KIT_CONFIG_OPERATOR="${TMPDIR:-/tmp}/kit-no-operator.$$"
KIT_DIR="${KIT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
bash "$KIT_DIR/lib/config/kit-config.sh" selftest
