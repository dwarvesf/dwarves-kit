# Implementation notes: guides-gauntlet-adopt

Deltas and decisions, no spec.

- `gauntlet.md` absorbs the tutorial in the brief's page shape. The persona mapping table (user and contributor slot values) moved out; `tests/gauntlet/README.md` already holds both inputs tables. The "Cheap probe" and "Common mistakes" text stays in `gauntlet.md`, because comments in `tests/gauntlet/deploy/` and the Dockerfile cite both by name.
- Probe key facts are unchanged: local reads `ANTHROPIC_API_KEY`; remote uses `probe_key_ref` from `~/.config/dwarves-kit/kit.toml`.
- `adopt.md` output was captured from `lib/adopt.sh` in a temp repo with an empty `XDG_CONFIG_HOME`. The operator's `adopt.single_source` knob changes the output, so a clean config dir was needed for the default shape.
- `wrap.md` scan and tidy samples were captured from `bin/wrap` in a temp repo with a local bare origin. `wrap land` needs `gh` and a remote PR, so its sample lists the format strings from `lib/wrap/wrap-land.sh` with `<...>` for values. It is labeled that way.
- Contributor seed card: the old gap was "one diagram per guide" against a guide with no diagram. That promise is gone. The new card asks the contributor to check every guide against the page shape the README states and fix the deviating guide or the claim. The card allows "no deviation found" (then fix one wrong index row or sentence), so it stays well posed even when the guides all conform. The checker adds one check: the commit body or `PR.md` names the page shape and a guide file.
- `tier1.sh`: only the T1.1 file list grew (`adopt.md`, `wrap.md`).
- Link repoints for the removed tutorial: `docs/MANUAL.md`, `tests/gauntlet/deploy/README.md`, `tests/gauntlet/deploy/campaign-pass`, `tests/gauntlet/cleanroom/Dockerfile` (comment only), `tests/gauntlet/README.md` wording.

Open: `review.md` and the figure files arrive from other slices; until then `refcheck` flags those links and `../figures/{gauntlet,adopt,wrap}.png`.
