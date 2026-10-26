# Gauntlet run corpus (bulk artifacts)

The bulky gauntlet run artifacts (probe transcripts and fixture tarballs) are not in the git tree. They are one release asset on this repo, kept retrievable here. Every `ROUNDS.md`, findings file, patch, checker output and small text file stays in place; only the files in the table below moved.

| Field | Value |
|---|---|
| Release tag | `gauntlet-corpus-2026-10` |
| Asset name | `gauntlet-corpus-2026-10.tar.gz` |
| Asset sha256 | `1539c54d8ec07c00d0a5222857cc4987531ed509df54643efb3f68ce4b87436a` |
| Asset size | 8670802 bytes |
| Files inside | 40 |
| Paths | relative to `docs/verification/gauntlet/` |

## Fetch and unpack

Run from the kit root. The unpack puts every file back at its original path.

```bash
gh release download gauntlet-corpus-2026-10 -p gauntlet-corpus-2026-10.tar.gz -R dwarvesf/dwarves-kit
shasum -a 256 gauntlet-corpus-2026-10.tar.gz    # must equal the sha256 above
tar -xzf gauntlet-corpus-2026-10.tar.gz -C docs/verification/gauntlet
```

The unpacked files are git-ignored (see `.gitignore`), so an unpack never dirties the tree.

## Who needs it

- `lib/gauntlet/stats.sh`: the probe tokens and cost columns come from the transcripts. Without the corpus it prints `-` there and says so on stderr; every other column reads `ROUNDS.md` only.
- `skills/gauntlet-proof-audit`: Tier 2 quote matching against a cited transcript. Unpack first; with no transcript the axis is UNSURE (no checkable evidence), never OK.
- Everything else (the Tier 1 audit, `tests/gauntlet/tier1.sh`) reads committed small files and needs nothing.

## Adding a later run

Large artifacts of a new run (transcripts over 200 KB, fixture tarballs) stay out of git. Publish them as a new release asset (`gauntlet-corpus-<YYYY-MM>`, `--latest=false`), and append its tag, asset, sha256 and file table to this file in the same commit.

## Moved files

| Path | sha256 | Bytes |
|---|---|---|
| `2026-08-06-kit-user/J3-round-1/room/transcript.jsonl` | `dfacc84c6201581b9999c37e4773b2fa54246b30a7f0ffa06e9b2fbaa5f7b367` | 1172534 |
| `2026-08-06-kit-user/J3-round-1/submission/fixture-repo.tar.gz` | `d5255c661a2fdcb5cb200f1fa0c4d81b2006f616bea43662063a77c5f8ed145d` | 58148 |
| `2026-08-06-kit-user/J3-round-2/room/transcript.jsonl` | `55aee6597fd971375cbcf7f27ea0ee8099a96ebb88b4f0b0533683b16ae3eb1d` | 927551 |
| `2026-08-06-kit-user/J3-round-2/submission/fixture-repo.tar.gz` | `af9a7a66159963eb797129d5b3f67a58a5c350e00158468aabfcdffd1f7912fe` | 59898 |
| `2026-08-06-kit-user/round-1/room/transcript.jsonl` | `5bbb8ecc882f529762606afe64f662410cf63fe37f0058054ab9a2ba7bd3de62` | 677005 |
| `2026-08-06-kit-user/round-1/submission/fixture-repo.tar.gz` | `acfbc1431a95ccb24d477dee15c6bb64b5ea64351d377d33386a5163644f3a39` | 28760 |
| `2026-08-06-kit-user/round-2/room/transcript.jsonl` | `fb61e03b7887434d53bf0c2417f51ac2c29b6cf5fc769bbf7bc3bdf8a3a9aba7` | 625699 |
| `2026-08-06-kit-user/round-2/submission/fixture-repo.tar.gz` | `77e51c47f287af9eb07b5938bca8cf5dbc933bef50824af47b1abcaa05bd0f33` | 26369 |
| `2026-08-06-kit-user/round-3/room/transcript.jsonl` | `e4ecdacd2eaaceded93ed8c5d3dd883e67c70e575bed4aa01fbdf8be521efd7a` | 548113 |
| `2026-08-06-kit-user/round-3/submission/fixture-repo.tar.gz` | `3887c8e0035542ef972604b6df887ca8e8f4b1cbd91fe5dbefd06701e94cf2b4` | 14173 |
| `2026-08-31-onboarding-j1-revised/round-1/room/transcript.jsonl` | `04cc033fc546dc818fe32140111d309ded5504c1649daca31560304b1be490fc` | 2247988 |
| `2026-08-31-onboarding-j1-revised/round-2/room/transcript.jsonl` | `064dd7cf00054a01246c060913eaedf63e8decee4c049e404aff70cad3d65fa5` | 3812762 |
| `2026-08-31-user-J1-nw/round-1/room/transcript.jsonl` | `0301f8cb57fb1d56f05111e479e9899eaa28fa76a13026c72adbcff340ff1524` | 2087125 |
| `2026-08-31-user-J1/round-1/room/transcript.jsonl` | `738f5f66c634f4f080355467dfcf6049ad1a537a874136619643c5ace257cf82` | 513990 |
| `2026-09-01-ab-doorway-26daed4-vs-7909768/A/round-1/transcript.jsonl` | `5f27577bf6702999cc6ebd9640b0e9c483ecbc671689646ff865872a599f2a8c` | 2145637 |
| `2026-09-01-ab-doorway-26daed4-vs-7909768/A/round-2/transcript.jsonl` | `5882948e2f97f3b9ae13880e610f3c86c5881eb741a86dfe9c123e5f9d3cfdcf` | 1999711 |
| `2026-09-01-ab-doorway-26daed4-vs-7909768/B/round-1/transcript.jsonl` | `ef5c567ac88466cfe6f86c7ff983374522d42b4ce6005ed9e234b704af276e61` | 4175770 |
| `2026-09-01-ab-doorway-26daed4-vs-7909768/B/round-2/transcript.jsonl` | `4975f5c987a83ab1e152397da73a184ec52c0beb0dca0c48c484a52b6ad3d0cb` | 2966159 |
| `2026-09-01-onboarding-campaign-2/J1/transcript.jsonl` | `0358b96389b9a06f3516287a800720404286b5e824ab11c9992c776a07709bff` | 2453155 |
| `2026-09-01-onboarding-campaign-2/J10/transcript.jsonl` | `efa7838016924ae2f215ec02adc26450dc40f327e028ff26a73abaa091747486` | 3540059 |
| `2026-09-01-onboarding-campaign-2/J11/transcript.jsonl` | `e4ac4efb7479f473a4b13a011f6815f659d28d61297b9c53472bd1f449674461` | 2684565 |
| `2026-09-01-onboarding-campaign-2/J2/transcript.jsonl` | `60763c8cf077b7e0fd5c989223e5ae82680d46d055314eaf4d54f12d2a71eea9` | 1884648 |
| `2026-09-01-onboarding-campaign-2/J3/transcript.jsonl` | `c9bc1ed6e93982b11160f948c7311b35371639ff8f67ed4349b7b62802fad449` | 3773946 |
| `2026-09-01-onboarding-campaign-2/J4/transcript.jsonl` | `b101bc1e1889bf9adf70dd669509a8af81029d6e681aaded25bf85b9e188d760` | 1768858 |
| `2026-09-01-onboarding-campaign-2/J5/transcript.jsonl` | `88c5cb23efb897b0b61d6bb1a49193197726c9b95cae01a5ef816b3ed4f3b73d` | 1713370 |
| `2026-09-01-onboarding-campaign-2/J6/transcript.jsonl` | `33b284a495c4c874d147c6a49bda5b88a7a8bd0119fe1faf15cdd35d3276b0e4` | 4074288 |
| `2026-09-01-onboarding-campaign-2/J7/transcript.jsonl` | `3cc8d5ad720327abfd2d9f9e1b70b3f8a023c77e5974b045e31ff2e3a938c25d` | 1258387 |
| `2026-09-01-onboarding-campaign-2/J8/transcript.jsonl` | `4c494af12cf63d1ef5eb034c84e1bb2d9fcf794fdcfdceffc9e5d6797de38575` | 1976430 |
| `2026-09-01-onboarding-campaign-2/J9/transcript.jsonl` | `fbce8a9bb7b96fdda286e44f2252ed19c40ac85a00eba82c84f95b5c978357ec` | 1362977 |
| `2026-09-01-onboarding-campaign/J1/transcript.jsonl` | `70d53a7cdea91ef4982aa8a8334c811ec95a76068eb9428b2ca1de4cde4aa642` | 2903980 |
| `2026-09-01-onboarding-campaign/J10/transcript.jsonl` | `488e945d2311eb7e4843cbeeedb929230f0e1fd9e01f68e48ba3012ec16e1a25` | 750817 |
| `2026-09-01-onboarding-campaign/J11/transcript.jsonl` | `4faffe7f4406fa0f131f93ca9ffa7a5c3b1145c0d52b437d4e71136dd9595771` | 739433 |
| `2026-09-01-onboarding-campaign/J2/transcript.jsonl` | `c7feb5040fb8f27cdc4e48b1ed79fbf80fdff661547a5929eaac0e4770a66843` | 3119589 |
| `2026-09-01-onboarding-campaign/J3/transcript.jsonl` | `db46ca90aa2d112bbc3983b197180572b01082134f8e8c1b15d1388a10b8d75f` | 2427194 |
| `2026-09-01-onboarding-campaign/J4/transcript.jsonl` | `0918229019ba616ca9c36b6cb1d019fc6fa7f869e4f63d0cf618e87de56f3a77` | 1300214 |
| `2026-09-01-onboarding-campaign/J5/transcript.jsonl` | `d31f2a6d3de7b003ae6f6e3608e77d77b7fb809e6512cd4b45a9a722844743d0` | 1558466 |
| `2026-09-01-onboarding-campaign/J6/transcript.jsonl` | `1ed13326801d2bfe74d3ee30b3fb69098240846d6de9651c25d91c9e82bcada5` | 6527424 |
| `2026-09-01-onboarding-campaign/J7/transcript.jsonl` | `54714048ae406e0b78d142cc28541dc3dc98e0080c85a8509aacca46f6474e39` | 2097408 |
| `2026-09-01-onboarding-campaign/J8/transcript.jsonl` | `feabc5f5f9c6ac218e68c1b5ab6cee1891b849d9a971e86d5d8d90f73ea0399c` | 3591746 |
| `2026-09-01-onboarding-campaign/J9/transcript.jsonl` | `1b09c15ad12dadea8153532b3270cc6709a253219a07e2f5e621367ddd761569` | 2579540 |
