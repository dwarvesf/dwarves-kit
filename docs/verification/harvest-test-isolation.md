# Proof of done: harvest tests stop inheriting host config; dry run shows STATE rows

## What changed

`tests/test-kit-foldin-hooks.sh` failed 85/97 on a host with the harvest sweep active: the operator `kit.toml` had `[harvest] enable = true` and the `sweep/installed` marker existed, so the per-session harvest hook stood down by design. The suite now exports `KIT_CONFIG_OPERATOR` and `KIT_CONFIG_ROOT` pointing at empty temp dirs, and `HARVEST_STATE_DIR` at a marker-free temp dir. `tests/test-harvest-sweep.sh` reads the host config through `_kit_root` too, so it pins the same two config variables. No product code changed for this part.

`hooks/harvest_sweep.py`: `--sweep --dry-run` now adds `state_rows` and `incidents` to the manifest JSON. `stage1.log` gets one `fallback <source> <session-id> <reason>` line when the Codex fallback runs (`codex (limit)`, `codex (error)`, or `failed`). No transcript or extractor text is logged; the file stays 0600.

## Gate table

| Claim | Evidence |
|---|---|
| foldin suite is host-independent | 97/97 on the Mini with the sweep active |
| sweep suite pins neutral config | 637/637 on the Mini |
| dry-run manifest carries the fallback STATE row | new assertions in `test-harvest-sweep.sh` |
| `stage1.log` has one fallback line, mode 0600, ids and reason only | new assertions |
| both changes are load-bearing | negative controls below |

## Run table

| Command | Result |
|---|---|
| `bash tests/test-kit-foldin-hooks.sh` | 97 / 97 |
| `bash tests/test-harvest-sweep.sh` | 637 / 637 |
| `bash tests/test-meta.sh` | 887 / 887 |

## Negative controls

| Control | Result |
|---|---|
| foldin suite with the three pin exports removed | 85 / 97, the original failure returns |
| `hooks/harvest_sweep.py` reverted, new tests kept | the dry-run and stage1.log assertions fail (629 / 637) |

## Rollback

Revert the commit. The change touches two test files, `hooks/harvest_sweep.py` (manifest keys and one log line), and this note. No state, config, or schema migrates.
