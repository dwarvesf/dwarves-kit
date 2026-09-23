# Spec: precedent ranks partial matches and reads YAML block-scalar descriptions

Generated: 2026-09-23
Status: SHIPPED on merge (branch `fix/precedent-partial-match`)
Lane: full
Type: spec-feature
File: `docs/specs/SPEC-308-precedent-partial-match.md`
References: `lib/precedent/inventory.py` (`score`, `term_pattern`, `skill_frontmatter`, `note_frontmatter`, `scan_kit_verbs`); `tests/test-precedent.sh`; SPEC-245 (the inventory surface this amends); ops-toolkit `experiments/jev-eval/TEST-REPORT.md` "Kit-decisions suite" (the evidence) and its `seed-data/kit-decisions/precedent-queries.json` (59 labeled queries).

## Problem

`precedent find --surface inventory` answers "does something already do X?" before a tool gets built. On the jev-eval labeled set (45 queries with a gold inventory row, 14 where nothing in the index does it) it gets hit@1 26/45 and misses rows it has indexed. Three causes:

1. **AND scoring.** `score()` zeroes a row when any query word is absent. One extra word hides the row: "lane classify regex" returns nothing although `lib/classify/lane-classify.sh` is indexed, and "gate ledger bulk record" misses `lib/gate/gate-ledger.sh`. Query words also split only on whitespace, so `lane_classify` is one term that matches nothing.
2. **YAML block scalars.** `description: |` or `description: >-` indexes the marker as the description. 29 of 172 skills on the operator's machine indexed as `|` or `>`, so only their name and body could match.
3. **Unindexed lib tool entry points.** The kit-verbs scan reads `lib/**/*.sh` only. The extensionless executables under `lib/<x>/bin/` (`session-observe`, `session-recall`, `plugin-check`, `skill-improve` and eight more) never reach the index. "session entry fee breakdown" cannot find `session-observe`, which owns the entry-fee view.

## Solution

### Approaches considered

1. **Ranked partial match in the existing scorer.** Score a row by how many query terms it matches, keep a floor, keep all-term rows on top. Tradeoff: some queries that returned nothing now return partial rows, so `nothing_matched` fires less often.
2. **TF-IDF or BM25 over a built index.** Principled term weighting. Tradeoff: needs a second pass over every row (document frequencies) and a rewrite of the scan-and-score-in-one-pass shape every iterator uses. Out of proportion for a two-to-four-word lookup.
3. **A model sweep (the Jev arm in the evidence).** Best hit@1 in the evidence, but it sends rows off-host and costs a network call per lookup. The evidence itself recommends it only in shadow mode beside lexical search.

### Chosen approach + why

Approach 1: the smallest change that fixes the measured misses. Every iterator keeps calling `score(terms, name, haystack)`; the output format, the `--json` schema, the `--quiet` summary line and the log line do not change.

### Design record

Every variant below ran against the same 59 queries through the same flat ranking the jev-eval harness uses (score descending, section rank, hit rank, egress filter applied).

| variant | hit@1 | hit@3 | none precision | none recall |
|---|---|---|---|---|
| origin/master (AND, whitespace terms) | 26/45 | 30/45 | 12/18 | 12/14 |
| prefix stemmer, floor ceil(n/2), no anchor | 29/45 | 35/45 | 1/2 | 1/14 |
| prefix stemmer, floor n-1, one name hit for a partial | 29/45 | 34/45 | 7/9 | 7/14 |
| same, two name hits for a partial | 28/45 | 32/45 | 8/12 | 8/14 |
| prefix stemmer, AND floor (isolates the stemmer) | 26/45 | 30/45 | 8/14 | 8/14 |
| query-side stem stripping, closed inflection set | 30/45 | 34/45 | 7/9 | 7/14 |
| **chosen**: original closed inflection set, separators split, floor n-1, one name hit for a partial, memory body counts only toward all-term matches | **30/45** | **34/45** | **9/11** | **9/14** |

Decisions the table settles:

- **The inflection set stays closed** (`-s -es -ed -ing`, doubled final consonant). Prefix matching (`mini` finds `minimal`) and query-side stripping (`tests` finds `test`) each added false hits on the negatives and found no gold row the closed set missed.
- **Floor = all terms for one- or two-term queries, n-1 above.** Half the terms (ceil(n/2)) flooded the negatives: none recall fell to 1/14.
- **A partial match needs a name hit.** A long description or note body shares two of three words with almost any query. One name hit keeps the recall; two costs hit@1 and hit@3 for one extra negative.
- **A memory note's body counts only toward an all-term match.** Same metrics, fewer noise rows (P07 went from 38 to 22 rows).
- **Coverage dominates the score:** `matched x 100 + weight`. A row matching more terms always outranks one matching fewer, so all-term rows stay on top. Within equal coverage a name hit weighs 2, a haystack hit 1, the adjacent phrase +3. A skill's name and description weigh double (4 and 2); the old code doubled the whole score, which would have let a partial skill match outrank a full match elsewhere.

### Extensibility & boundaries

- One scorer, one floor function (`min_match`), one term splitter (`query_terms`). A later IDF pass would replace the weight part of `score()` and leave the call sites alone.
- `fm_value()` reads every frontmatter field that feeds the index (skills, memory notes, experiments, research), so all four sources gain the block-scalar fix.
- The lib entry-point scan is scoped to a directory named `bin` outside any `tests` or `fixtures` path, executable or `*.sh`.

## Picture

```
query words ──> query_terms() ── split on non-alnum, drop stopwords, dedupe
                     │
                     v
row (name, haystack) ──> score()
        per term: name hit +2 | haystack hit +1 | miss
        matched < min_match(n) ............................ 0
        partial (matched < n) and no name hit ............. 0
        all terms adjacent in order ....................... +3
        result = matched x 100 + weight
                     │
                     v
sections.add() drops 0 ──> render(): nothing_matched = no row scored > 0
```

## After state

- `bin/precedent find --surface inventory "lane classify regex"` lists `kit lib/classify/lane-classify.sh` first; before, nothing.
- `bin/precedent find --surface inventory "session entry fee breakdown"` lists `kit lib/session/observe/bin/session-observe` first; before, nothing.
- A skill with `description: >-` or `description: |` indexes the indented text under the marker.
- `bin/precedent find --surface inventory "kubernetes pod autoscaler"` still reports `nothing_matched: true`.
- Output format, `--json` keys, the `--quiet` summary line and the `precedent.log` line are unchanged.
- A lookup on the operator's full live registry stays under one second (measured 0.50 to 0.54s, origin/master 0.48 to 0.50s).

## Acceptance Criteria (global)

- AC1: a three-term query where one term matches nothing still finds the row that matches the other two, when one of them is in the row's name.
- AC2: a two-term query with one absent term, and a three-term query with only one matching term, both report `nothing_matched: true`.
- AC3: a partial match whose terms sit only in a description or note body scores 0; the all-term match of the same row still surfaces.
- AC4: `_`, `-` and `/` in a query separate terms.
- AC5: `>-` and `|` block-scalar descriptions index their text.
- AC6: extensionless executables under `lib/<x>/bin/` are indexed as kit verbs.
- AC7: every pre-existing case in `tests/test-precedent.sh` stays green.
- AC8: on the 59-query labeled set, hit@1 and hit@3 rise and none precision does not fall below origin/master's.

## Test plan

| row | AC | case (tests/test-precedent.sh) | category |
|---|---|---|---|
| T1 | AC1 | partial match: a three-term query with one absent word still finds tools/alpha/ | positive |
| T2 | AC2 | floor: a two-term query with one absent term zeroes every inventory hit | negative |
| T3 | AC2 | floor: one matching term of three is below the floor, nothing_matched | boundary |
| T4 | AC2 | none-query: an unrelated three-word query reports nothing_matched | negative |
| T5 | AC3 | partial match without a name hit is dropped; the all-terms match still surfaces | negative + positive |
| T6 | AC4 | separators: alpha_run matches tools/alpha/bin/alpha-run | positive |
| T7 | AC5 | block scalar: a >- and a \| skill description index the real text | positive |
| T8 | AC6 | lib bin entry point: session-observe is indexed and tops 'session entry fee breakdown' | positive |
| T9 | AC7 | the full existing suite (ranking, phrase bonus, redaction, explain, json, quiet, log) | regression |
| T10 | AC8 | the jev-eval labeled set, before vs after | eval |

## Verification

```
bash tests/test-precedent.sh
RUN_ALL_TIMEOUT_SECS=600 bash tests/run-all.sh --changed
bash lib/gate/negctl.sh "$PWD" "bash tests/test-precedent.sh" "git show origin/master:lib/precedent/inventory.py > lib/precedent/inventory.py"
```

Proof of done: `docs/verification/precedent-partial-match.md`.

## Edge Cases

1. A query of stopwords only: no terms, every row scores 0, `nothing_matched` true. Before, a stopword such as `the` matched as an ordinary word.
2. A duplicated query word (`board board`): deduped to one term.
3. A block scalar followed directly by the next key (empty block): the field reads empty, as an absent field did.
4. A lib `bin/` dir under `tests/` or `fixtures/`: not indexed.

## Out of Scope

- IDF or BM25 term weighting.
- The Jev shadow sweep the evidence recommends; that is a separate wiring decision.
- Relabeling the jev-eval gold file. Two gold sets are reported (as written, and with the newly indexed `session-observe`/`session-recall` rows counted).

## Decision Log

- DEC-001: closed inflection set over prefix matching, on the measured false hits (Design record).
- DEC-002: floor n-1 plus one name hit for a partial, on the measured none-recall collapse at ceil(n/2).
- DEC-003: lib `bin/` indexing lands in this change: 12 files, one condition in the existing walk.
