# Spec: wordstat (a small word-counting CLI)

Generated: 2026-09-30
Status: VALIDATED
Lane: full

## Problem

There is no tiny tool in this repo that counts lines, words and bytes of a text and lists its most frequent words. `wordstat` fills that gap as one stdlib-only Python script with a human format and a `--json` format.

## Solution

One file, `src/wordstat.py`, run as `python3 src/wordstat.py [--top N] [--json] [FILE]`. It reads FILE, or stdin when FILE is absent or `-`. A word is a maximal run of `[A-Za-z0-9']` characters, compared case-folded; one tokenizer serves both the `words` count and `--top`. Input is read as raw bytes (so `bytes` equals the file size and CRLF is not undercounted) and decoded as UTF-8 with `errors="replace"` for tokenizing. No third-party dependency.

## Design

One module, one flow, pure functions for the logic and `main` for I/O:

```
argv -> parse (--top N, --json, FILE|-)
          |  bad --top -> argparse error, exit 2
          v
     read FILE or stdin as bytes ---- OSError -> stderr "wordstat: cannot read <FILE>", exit 2
          v
     count(data)      -> lines (b"\n" count), bytes (len), words (len of tokens)
     top_words(text,n)-> [(word, count)] sorted by count desc, word asc   (only with --top)
          v
     text: "lines=.. words=.. bytes=.." then "<word> <count>" lines
     json: json.dumps of {lines, words, bytes[, top]}
          v
        exit 0
```

Chosen approach: stdlib `re.findall` for tokens, `collections.Counter` for frequencies, `argparse` for the CLI, and a custom argparse `type` that rejects negative or non-integer `--top`. Tests import the module by inserting `src` into `sys.path`.

## Task Breakdown

### Phase 1: Counts

- [ ] TASK-A: create `src/wordstat.py` with `main(argv=None)` and a `count(text)` function returning lines, words and bytes; the CLI prints `lines=<n> words=<n> bytes=<n>` for FILE or stdin. Lines = number of `\n` bytes; bytes = raw input length; words = number of `[A-Za-z0-9']+` tokens (so `printf 'a,b\n'` is 2 words). AC: `python3 src/wordstat.py tests/data/sample.txt` prints exactly `lines=3 words=11 bytes=52`; `printf 'a b\n' | python3 src/wordstat.py` prints `lines=1 words=2 bytes=4`; `printf 'a,b\n' | python3 src/wordstat.py` prints `lines=1 words=2 bytes=4`; unit tests in `tests/test_counts.py` pass.

### Phase 2: Top words

- [ ] TASK-B: add `top_words(text, n)` and the `--top N` flag. Words are tokens matching `[A-Za-z0-9']+`, lowercased; sort by count descending, then alphabetically; print `<word> <count>` one per line after the counts line. AC: `python3 src/wordstat.py --top 2 tests/data/sample.txt` prints the counts line, then `the 3`, then `brown 1`; `--top 0` prints no word lines; unit tests in `tests/test_top.py` pass.
- [ ] TASK-C (depends on TASK-B): add `--json`. Output is one JSON object made with `json.dumps` defaults, keys in the order `lines`, `words`, `bytes`, `top` (the `top` key is present only with `--top`, as a list of `[word, count]` pairs). AC: `python3 src/wordstat.py --json --top 2 tests/data/sample.txt` prints exactly `{"lines": 3, "words": 11, "bytes": 52, "top": [["the", 3], ["brown", 1]]}`; without `--top` the `top` key is absent; unit tests in `tests/test_json.py` pass.

### Phase 3: Errors and docs

- [ ] TASK-D: error handling and usage docs. A FILE that cannot be read for any `OSError` reason (missing, a directory, no permission) prints `wordstat: cannot read <FILE>` to stderr and exits 2; a negative or non-integer `--top` exits 2 with argparse's message; empty input prints `lines=0 words=0 bytes=0` and exits 0. Add `docs/usage.md` with a `## Usage` heading and one example per flag. AC: `python3 src/wordstat.py nope.txt; echo $?` ends with `2`; `printf '' | python3 src/wordstat.py` prints `lines=0 words=0 bytes=0`; `grep -q '^## Usage' docs/usage.md`; unit tests in `tests/test_errors.py` pass.

## After state

- [ ] `python3 src/wordstat.py tests/data/sample.txt` prints `lines=3 words=11 bytes=52`. (Today: `src/wordstat.py` does not exist.)
- [ ] `--top` and `--json` behave as the task criteria state.
- [ ] `bash tests/run.sh` exits 0 and runs the four test files named in the tasks.

## Acceptance Criteria (global)

- [ ] All tasks pass their individual acceptance criteria
- [ ] Tests cover happy path and the edge cases below
- [ ] The Verification commands below all pass from the repo root

## Verification

Run from the repo root:

```bash
bash tests/run.sh
test "$(python3 src/wordstat.py tests/data/sample.txt)" = "lines=3 words=11 bytes=52"
test "$(python3 src/wordstat.py --top 2 tests/data/sample.txt | tail -2 | tr '\n' ',')" = "the 3,brown 1,"
test "$(python3 src/wordstat.py --json --top 2 tests/data/sample.txt)" = '{"lines": 3, "words": 11, "bytes": 52, "top": [["the", 3], ["brown", 1]]}'
python3 src/wordstat.py tests/data/missing.txt 2>/dev/null; test $? -eq 2
test "$(printf '' | python3 src/wordstat.py)" = "lines=0 words=0 bytes=0"
grep -q '^## Usage' docs/usage.md
```

## Edge Cases

1. Input with no trailing newline: lines counts `\n` characters only, so `printf 'a b' | python3 src/wordstat.py` prints `lines=0 words=2 bytes=3`.
2. Non-ASCII text: bytes is the raw byte length, not the character count; CRLF input counts every byte.
3. `--top N` larger than the number of distinct words prints every distinct word.
4. Apostrophes stay inside a word (`don't` is one word); other punctuation splits words.
5. FILE given as `-` reads stdin.

## Out of Scope

- Unicode-aware word splitting, locale handling, multiple files, packaging.

## Touches

- src/**
- tests/**
- docs/**
