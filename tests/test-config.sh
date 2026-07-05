#!/usr/bin/env bash
# test-config.sh -- the config-layer resolver (lib/config/kit-config.sh).
# Delegates to the resolver's own selftest (precedence, comment-strip, defaults).
set -euo pipefail
KIT_DIR="${KIT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
bash "$KIT_DIR/lib/config/kit-config.sh" selftest
