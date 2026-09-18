# Proof of done: webcheck flags a share card that social crawlers drop

Spec: `docs/specs/SPEC-298-webcheck-og-share-card.md`. Notes: `docs/implementation-notes/SPEC-298-webcheck-og-share-card.md`.

## Green run

| Command | Exit | Output | Verdict |
|---|---|---|---|
| `python3 -m pytest -q lib/webcheck/tests` (tests committed before the code) | 1 | `8 failed, 83 passed` | RED as expected |
| `python3 -m pytest -q lib/webcheck/tests` (after the build and review fixes) | 0 | `93 passed` | PASS |
| `python3 lib/webcheck/webcheck.py audit https://memo.d.foundation/macbook-notch-macos-27` | 0 | `og missing : none`, no SVG warning | PASS (live page after foundation-apps#126 and #127) |

## Negative control

`bash lib/gate/negctl.sh "$PWD" "python3 -m pytest -q lib/webcheck/tests" "sed -i '' 's/og_image and _og_image_is_svg(/False and _og_image_is_svg(/' lib/webcheck/core.py"`

| Step | Exit | Verdict |
|---|---|---|
| green before mutation | 0 | PASS |
| check disabled | 1 | RED as expected |
| `git checkout HEAD -- lib/webcheck/core.py`, rerun | 0 | GREEN |

Reproducible: the suite is stdlib Python with a stubbed fetch and no network.
