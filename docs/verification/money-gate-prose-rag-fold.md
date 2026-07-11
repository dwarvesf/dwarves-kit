# Proof of done: money-gate + prose-rag fold (kit-foldin completion)

Change under proof (Han 2026-07-11 overruled the kit-foldin "stays personal"
disposition: the engines are generic, only their DEFAULTS were personal):

1. `hooks/money-gate.{sh,py}` , function-named port of ops-toolkit
   `cc-money-gate`. Genericized: no default repo list; INERT unless the consumer
   sets `CC_MONEY_REPOS` (adapter-default invariant, the kit ships no tenant repo
   names). Module `money_gate` (PreToolUse `Edit|Write|MultiEdit`).
2. `lib/prose-rag/` , fold of ops-toolkit `tools/prose-rag` (Rust engine
   preferred + Python/uv fallback). Genericized: the hardcoded personal corpus
   default (til/research/ledger paths) became `PROSE_RAG_CORPUS` (colon-separated,
   `~/` expands) in BOTH engines. Module `prose_rag`: dormant UserPromptSubmit
   hook (`hooks/prose-rag.sh`, activates only with `PROSE_RAG_INJECT=1`) + the
   `prose-rag` CLI shim via the SPEC-184 stable entrypoint `bin/prose-rag`
   (runtime engine pick; `hook` with no engine exits 0, never breaks a prompt).
3. Wiring: kit `settings.json` (+2 hook entries, gated by modules), `kit.toml`
   rows, README module table, `test-install-modules.sh` UNWANTED list extended,
   `test-install-clis.sh` extended (opt-in hook wiring + prose-rag shim + NCs),
   `test-hooks.sh` hook-count pin 22 -> 24.

## Confirmation run-table

| # | Check | Command | Result | Verdict |
|---|---|---|---|---|
| 1 | money-gate behavior (7 checks incl. 3 NCs, one NEW: inert-without-config) | `bash tests/test-money-gate.sh` | all 7 passed | PASS |
| 2 | prose-rag Rust suite (genericized corpus) | `cd lib/prose-rag/rust && cargo test --release` | 10 passed, 0 failed | PASS |
| 3 | prose-rag Rust CLI smoke | `bash lib/prose-rag/rust/tests/smoke.sh` | all 13 passed | PASS |
| 4 | prose-rag Python engine smoke (uv venv) | `bash lib/prose-rag/tests/smoke.sh` | all 11 passed | PASS |
| 5 | installer CLI/hook wiring incl. new modules | `bash tests/test-install-clis.sh` | all 26 passed | PASS |
| 6 | module machinery | `bash tests/test-install-modules.sh` | 37 passed, 0 failed | PASS |
| 7 | full hooks suite | `bash tests/test-hooks.sh` | 453 / 453 | PASS |
| 8 | compat + contract installs | `bash tests/test-install-compat.sh; bash tests/test-install-contract.sh` | PASS; 4/4 | PASS |
| 9 | dormant hook shims cost ~0 | `echo '{}' \| hooks/prose-rag.sh` (no PROSE_RAG_INJECT); money-gate without CC_MONEY_REPOS | both exit 0 silent | PASS |

## Negative controls

- `tests/test-money-gate.sh` [4][5][6]: no fire on non-money edit; no fire outside
  named repos; **inert with `CC_MONEY_REPOS` unset** (the kit-default state).
- `tests/test-install-clis.sh`: spine-only install exposes neither hook nor shim;
  user-owned files never clobbered.
- `lib/prose-rag/tests/smoke.sh` [8]: master switch off -> silent even on a recall
  prompt (made env-hermetic with `env -u PROSE_RAG_INJECT`; a consumer shell with
  the rollout flag exported used to false-fail this check).
- Tenant-leak grep: `rg "workspace/tieubao|family-office|trading" lib/prose-rag/src hooks/money-gate.py`
  -> no hits in code paths (historical SPEC/implementation-notes keep their
  original context as records).

## Reproduce

```
bash tests/test-money-gate.sh
bash tests/test-install-clis.sh
(cd lib/prose-rag/rust && cargo test --release)
bash lib/prose-rag/rust/tests/smoke.sh
bash lib/prose-rag/tests/smoke.sh
bash tests/test-hooks.sh
```
