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
WORKDIR /work
RUN git config --global user.email probe@example.invalid \
 && git config --global user.name "Gauntlet Probe" \
 && git config --global init.defaultBranch main

CMD ["bash"]
