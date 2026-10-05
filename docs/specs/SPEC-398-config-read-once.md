# Spec: read each kit.toml layer once per process

Generated: 2026-10-05
Status: VALIDATED (design call made in the kit-speed run, R26; the proof is a differential run against the frozen resolver, no validation fan-out)
Lane: full (`lib/config/` is a hard path)
Type: perf
Source: kit-speed mega-goal, sub-goal 09 (R22 reopened by R26; NOTES item 4).

## Problem

`kit_config_get` resolved one key with up to three `awk` runs and three subshells: `kit_config_project`, `kit_config_operator`, `kit_config_root` and `_kit_toml_get` each ran in `$(...)`. About 158 call sites read keys that way (board.sh 31, lane-data.sh 11, orchestrate.sh 11). It cost about 6.5 ms a lookup at load 6 and far more on a busy host, because a fork is what a loaded host makes slow.

## Design

- **One awk pass per layer content.** `_kit_toml_load <file>` parses a file once into newline-joined `section<TAB>key<TAB>value` records held in a shell variable. The pass reuses the reference reader's comment, header, trim and unquote statements, so each value is cut by the same rules. A lookup is parameter expansion over that string: the first record for a `(section, key)` wins, as the reference's `exit` on first match did. No associative arrays, so it runs on bash 3.2.
- **Identity is the file content, not size and mtime.** A slot (parallel indexed arrays: path, content, records) is reused only when the path matches and the content read now equals the content parsed. The read is `$(<file)`, a builtin with no fork. Size plus mtime would need a `stat` fork per lookup, which is the cost this removes. It would also miss a same-size edit inside one second (bash 3.2 compares whole seconds) and a reused `mktemp` path, and `lane-data.sh` rewrites one temp path with different tomls. A different project root changes the path and a layer edited mid-process changes the content, so either re-parses. Sixteen slots, then the oldest is recycled.
- **No subshell on the hit path.** `kit_config_get` and `kit_config_get_root` inline the same three path expansions that `kit_config_project`, `kit_config_operator` and `kit_config_root` use, and call `_kit_toml_lookup`, which sets a variable instead of printing. The three public path functions stay as they were.
- **Cache filled where subshells inherit it.** Callers read `v="$(kit_config_get ...)"`, and a subshell's cache dies with it. So the lib parses its three layers once when it is sourced. A subshell then starts with a warm cache and re-parses only a layer whose path or content changed. A missing layer costs nothing. A sourcing script that reads no key and counts its own spawns sets `KIT_CONFIG_NO_PRIME=1` (only `lib/decide/flick.sh`, whose test pins one awk run per batch). The cache is never exported: kilobytes of environment in every child would cost more than it saves.
- **Raw getter too.** `_kit_toml_get <file> <section> <key>` (called by lane-data.sh, gate-policy.sh, proof-ledger.sh, config.sh, orchestrate.sh) answers from the same cache and prints what it printed before: the value and a newline when the key line exists, nothing when it does not.
- **Exactness over reach.** The reference reader stays as `_kit_toml_get_awk`, the ground truth. The cache answers only keys made of `[A-Za-z0-9_-]` and sections with no whitespace or backslash. The reference treats the key as a regex and passes both through `awk -v`, which expands escapes, so any other input goes to the reference reader unchanged. A missing or unreadable file also goes there, so its error and exit status are unchanged.
- **String work runs in the C locale.** bash 3.2 string operations cost about twice as much under UTF-8, and every comparison is bytewise. The awk run keeps the caller's locale.
- **Unchanged.** Callers, `kit_config_tracked_clean`, `kit_config_show_at`, the selftest cases, and the precedence rules (project over operator over kit root; `_root` skips the project).

## Test plan

| Case | Layer under test | Proof |
|---|---|---|
| Value parity for every `section.key` in kit.toml and the fixture set, `get` and `root` | resolver | differential run against the frozen pre-cache resolver, zero diffs |
| Raw `_kit_toml_get` output parity, found-empty vs absent | raw getter | same differential run, newline included |
| Quotes, inline and full-line comments, arrays, duplicate keys, duplicate sections, dotted sections, empty values, CRLF, BOM, headerless keys, regex-metachar keys, last-dot split | parser | fixtures in the same run |
| Project over operator over root; missing, empty, directory and unreadable layers | precedence | fixture triples in the same run |
| Same answers via `$(...)`, in one process, in reverse order, bash 3.2 and the PATH bash | cache state | three driver modes per shell |
| A layer edited mid-process (same size, same second) | invalidation | in-process edit, new value read |
| A different project root; a deleted layer; an operator edit | invalidation | in-process |
| More paths than slots | recycling | 20 roots, then earlier ones again |
| awk runs: 0 after source, 0 over 150 lookups, 1 after one edit | read-once | PATH shim counts awk |
| `KIT_CONFIG_NO_PRIME=1`: 0 awk at source, first lookup still answers | opt-out | PATH shim counts awk |
| Sourcing prints nothing; unset HOME under `set -u` returns the default | safety | shell test |

## Verification

```
bash tests/test-config-cache.sh      # parity and cache behaviour
bash tests/test-config.sh            # the resolver's own selftest
bash tests/test-config-registry.sh
bash tests/test-config-seams.sh
bash tests/test-config-stamp.sh
bin/test-affected --base origin/master
# negative control: a saved copy whose slot never invalidates; the mid-process edit case goes red
```

## After state

- [x] `kit_config_get` and `kit_config_get_root` return the same value as before for every key, layer and edge case in the differential run.
- [x] A process parses each distinct layer content once; 150 lookups after the source spawn no awk.
- [x] No change to any caller.
