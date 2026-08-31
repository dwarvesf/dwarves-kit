# Gauntlet clean room for the kit's own runs. Carries NOTHING from the host:
# no kit install, no credentials, no prior run records. Rule 7: the gauntlet's
# own directory and past run records are excluded by run.sh's staging step.
# node:22-slim ships neither `tail` nor `ps`: a PROBE_CMD or probe transcript
# depending on either dies opaquely. Use `cat`/shell builtins instead.
FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl ca-certificates ripgrep \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g @anthropic-ai/claude-code

# /work is the probe's whole world:
#   kit.tar.gz      the kit, NOT installed (installing is part of day one)
#   fixture-repo/   persona A's adoption target
#   kit/            persona B's clone (staged only for that persona)
#   checks/         the submission checkers (the card names them; they test
#                   real properties, so reading them does not hand out answers)
#   CARD.md         the seed card
WORKDIR /work

RUN git config --global user.email probe@gauntlet.local \
 && git config --global user.name "Gauntlet Probe" \
 && git config --global init.defaultBranch main

CMD ["bash"]
