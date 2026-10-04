# Verification: config registry env vars

| Item | Registered as | Reader |
|---|---|---|
| HARVEST_STATE_DIR | env row, module session | `hooks/harvest.sh`, `hooks/harvest.py`, `hooks/harvest_sweep.py` |
| KIT_WRAP_CI_GRACE_SECS | env row, module wrap | `lib/wrap/wrap.sh` |
| HARVEST_SWEEP_CHILD | internal allowlist (parent-to-child marker) | `hooks/harvest.sh`, set by `hooks/harvest_sweep.py` |
| harvest.enable, harvest.hook_when_sweep_on | root-only keys table | `hooks/harvest.sh`, `hooks/harvest_sweep.py` |

| Check | Result |
|---|---|
| `bash tests/test-config-registry.sh` before | 54/56, 3 orphans plus root-only key diff |
| `bash tests/test-config-registry.sh` after | 56/56 |
| `bash tests/test-meta.sh` after | 887/887 |
| Negative control (registry reverted to parent commit) | 54/56, 3 orphans reported, root-only diff FAIL |
| Restore | 56/56 |
