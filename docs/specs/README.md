# docs/specs

Historical record of shipped specs. One file per release that introduced a spec.

In-flight work lives in `.planning/SPEC.md` (single working file the kit's hooks and commands reference). At release time, the maintainer moves the finalized SPEC here as `SPEC-NNN-<slug>.md` so the history survives the next cycle.

Numbering: zero-padded sequential, assigned at the moment of move. The file's content is the spec as it was at ship time, including the Decision Log. Subsequent fixes get their own SPEC; do not edit a shipped SPEC in place.

See ADR-0002 for why `.planning/` stays as the working dir.
