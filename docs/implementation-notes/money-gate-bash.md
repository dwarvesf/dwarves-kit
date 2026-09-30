# Impl notes: money-gate-bash (SPEC-355)

Delta from the spec. Only off-spec calls live here.

## 2026-09-29 the scan is a hybrid, not the spec's "one index() loop per term"

- Context: the spec's ## Design row names "awk, one `index()` loop per term" as the chosen
  approach, while its Latency contract row also allows `split(text, parts, term)` per term
  and forbids copying the remainder per match.
- Decision: two streams. A `tr -cs 'a-z0-9' '\n'` pass folds every non-alnum run into a
  newline, leaving each candidate word on its own line; the 24 separator-free terms
  (including `apikey`/`privatekey`) become a hash lookup, and the boundary test is free.
  The 8 `[_-]` variants get a `split()` gap walk, but only on lines containing `_` or `-`.
- Why: the word-fold pass handles the common case in one linear sweep instead of 24
  `index()` scans over the text, and boundaries are structural, not re-checked per term.
  `split()` gives every gap's text without copying the tail per match, which is what the
  quadratic rule forbids. Gate the variant pass on the line containing `[_-]` so a sparse
  payload skips it entirely.
- Alternatives: literal per-term `index()` loops per the Design row -- rejected, the
  boundary recheck is identical work the word-fold already did, and the row's own `split()`
  allowance covers the variant stream. `grep -oE` alternation -- rejected in the spec.
- Impact: the term table lives in two places in one awk block (the `S[]` word list and
  the `V[]` variant list); adding a term means deciding which list it belongs to. The
  parity corpus does not pin scan internals, only hits.

## 2026-09-29 reproducing Python quirks in jq/bash

- `def truthy` in jq reproduces Python's `or`-chain truthiness (null/false/0/""/[]/{}).
  jq `error()` stands in for the Python crashes the shim swallowed (non-dict payload,
  truthy non-dict `tool_input`, truthy non-string `file_path`): all three exit 0 silently
  through the same `|| exit 0`, which is the only observable the shim produced.
- `file_path` + `cwd` come back from jq separated by `\001` with a trailing `x`: command
  substitution strips trailing newlines, and the spec requires them kept byte for byte.
- `tr 'A-Z\000' 'a-z\003'` lowercases and maps NUL to `\003` because awk truncates a
  record at NUL; both bytes are separators anyway, so the map is behavior-preserving.
- Strict trim uses bash `extglob` `+([[:space:]])` rather than sed: no subprocess, and
  under `LC_ALL=C` `[[:space:]]` covers Python `str.strip()`'s ASCII whitespace set.
- The ask JSON is printed by `printf`, not jq, so the `": "` separator matches what
  `json.dumps` emitted; goldens diff stdout byte for byte.
- The log's directory part is `${logp%/*}` only when the path contains a `/`; an empty
  or slashless `MONEY_GATE_LOG` gets no `mkdir` and no write, matching Python's
  `os.makedirs("")` failure.

## 2026-09-29 T2 went slightly past the enumerated stale rows

- The spec listed the stale claims to fix. Also fixed while in `lib/money-gate/SPEC.md`:
  the Verification section still classified `[10]` as a negative control ("non-`1` truthy
  string stays silent") and `[12]` as pinning the snake_case hole; both assert the
  opposite since the 2026-07-15 fix, so they moved to Fires/Assertion. The divergences
  intro said "Two things" above a four-item list.
- `lib/money-gate/README.md` known-gap 3 (the `\b` hole, already FIXED in SPEC.md) was
  replaced with the divergence the port actually carries: byte-scan under `LC_ALL=C`
  drops Python's exotic Unicode case-folds (Kelvin sign, long s), per the spec's own
  recorded divergence.
- Nothing under `tests/fixtures/money-gate-parity/` or `tests/test-money-gate-parity.sh`
  was touched; no golden looked wrong.

## Unsure

- The spec lists `MONEY_GATE_LOG` with a trailing `/` as out-of-parity. Checked: both
  sides create a stray directory (`os.path.dirname("rel.log/")` is `"rel.log"`, and
  `mkdir -p` agrees) and both write nothing, so the file side effects already matched;
  the only delta was a bash `Is a directory` line on stderr, now silenced by wrapping
  the append in `{ ...; } 2>/dev/null`. The recorded divergence no longer reproduces.
