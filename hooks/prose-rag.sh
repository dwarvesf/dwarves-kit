#!/usr/bin/env bash
# prose-rag.sh -- UserPromptSubmit hook shim for the prose-rag recall inject
# (kit-foldin port of ops-toolkit tools/prose-rag). Dormant unless the consumer
# sets PROSE_RAG_INJECT=1 (the engine's own master switch, duplicated here so a
# dormant hook pays ~0ms); with no engine built, `hook` exits 0 downstream too,
# so this can never break a prompt.
set -euo pipefail
[ "${PROSE_RAG_INJECT:-}" = "1" ] || exit 0
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$HERE/../bin/prose-rag" hook "$@" || true
exit 0
