# Clean room for the team-stamp gauntlet. Carries NOTHING from the host: no kit install, no
# credentials, no prior run records. The room is a teammate's machine: git, bash, jq, shellcheck
# and the agent CLI.
FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      git jq curl ca-certificates shellcheck \
    && apt-get clean \
    && npm install -g @anthropic-ai/claude-code

# /work is the probe's whole world:
#   repo/         the stamped scratch repo (git archive of committed state, then a fresh history)
#   bin/gh        the gh stand-in that records pr create, view, checks and merge
#   submission/   where the stand-in writes pr.json
#   CARD.md       the card
#   PROMPT.md     the probe framing
# The probe and the checker run as the image's non-root user "node", which owns /work. A new named
# volume mounted at /work takes its owner from this directory, so the probe can write to it; the
# seed is copied in as that user without preserved ownership, so nothing keeps a host uid.
RUN mkdir -p /work && chown node:node /work
USER node
WORKDIR /work
RUN git config --global user.email probe@example.invalid \
 && git config --global user.name "Gauntlet Probe" \
 && git config --global init.defaultBranch main

CMD ["bash"]
