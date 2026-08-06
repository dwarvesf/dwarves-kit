#!/usr/bin/env bash
# fixture: a DEPLOYABLE change -- a rollout script under a deploy/ path. Its path AND
# commit subject ("deploy: add rollout script") carry proof-ledger.sh's stateful signal
# ("deploy"), so classify() puts this diff in the stateful class (== deployable, SG-07).
set -euo pipefail
echo "rolling out service to production"
