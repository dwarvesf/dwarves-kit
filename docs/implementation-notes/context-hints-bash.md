# Implementation notes -- context-hints-bash

Deltas from SPEC-406. Nothing here repeats what the spec already states.

## 2026-10-16 The shared harness did not run under bash 3.2 (fixed here)

- Context: `tests/lib/hook-parity.sh` says it is bash 3.2 safe. Running the new parity test under `/bin/bash` stopped with a syntax error at the stray-file check.
- Decision/Change: the `case` statement inside `$( ... )` became an `if`. Bash 3.2 cannot parse a `case` pattern's closing parenthesis inside a command substitution.
- Why: every remaining port sources this library, and the macOS system bash is what a hook meets when the PATH has no Homebrew bash.
- Impact: the library, the self-test, and all 120 context-hints cases pass under `/bin/bash`.

## 2026-10-16 Seed, read, and tokens went into the shared harness, not into a fixture wrapper

- Context: context-hints is the first port whose result lives in a file the hook writes (the per-session state), and whose input includes a file the hook reads (state, map). The two older ports only had a log line.
- Decision/Change: `hp_run_case` takes `seed` (files written before the run) and `read` (files dumped after it) and expands `@HOME@` and `@CWD@` in env values and payload text. The tokens fold back in every output field, so a golden never carries a temp path.
- Why: backlog-stage, harvest, and intake-sweep all read and write staging files and ledgers. One implementation, self-tested once.
- Impact: the number normalizer reads `1000.0` as `1000`, so Python's float repr and jq's integer output compare equal.

## 2026-10-16 One jq program decides everything

- Context: the Python has four crash points (a state file that is not an object, a bad `start`/`last` type, a prompt that is not a string, a map that is not an object). Two of them happen after the state write and one after the temporal line was already built.
- Decision/Change: the program returns `write` and `print` separately. A crash before the write returns neither; a crash after it returns the write and no print. Bash only reads the two files, writes `write`, and prints `print`.
- Why: the ordering is the behavior, and it stays in one place that the corpus (`crash-*` cases) pins.

## 2026-10-16 Case-insensitive match instead of lowercasing

- Context: the Python lowercased the prompt and the key, then searched `\b<key>\b`.
- Decision/Change: `test("\\b" + escaped-key + "\\b"; "i")` on the original prompt. jq has no Unicode `lower`, and `ascii_downcase` would leave `ĐÀ NẴNG` unmatched.
- Impact: agrees on every realistic input (the corpus pins Vietnamese, accents, Greek, CJK). It differs only for the few characters whose `lower()` and Oniguruma case folding disagree, listed in the spec.

## 2026-10-16 Real data

- 1,266 real user prompts from the transcripts on this machine, with the installed Python hook's real state files and a map of skill names, common words, Vietnamese and regex-hostile keys, went through the Python and the port: identical stdout, exit code, and state on all of them (125 produced a temporal line, 1,099 a skill hint). See `docs/verification/context-hints-bash.md`.
