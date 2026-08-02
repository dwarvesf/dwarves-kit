# Bash implementation rules

Distills the Google Shell Style Guide, ShellCheck, and the "bash strict mode" convention, including its documented gaps.

## When to use Bash
- Small utility/wrapper scripts with straightforward control flow. Once logic grows non-trivial (real data structures, complex branching, or roughly 100+ lines per the Google Shell Style Guide's own threshold), move to Go or Python.

## Error handling
- Start every script with `set -euo pipefail`. Know its gaps: `set -e` does not fire inside `if`/`&&`/`||`/command substitution, and `pipefail` can misfire on a legitimate `SIGPIPE` (`cmd | head`).
- `((i++))` under `set -e` can silently exit the script when the expression evaluates to zero. Use `i=$((i+1))` instead.
- Check exit codes explicitly for anything strict mode's gaps could hide.

## Quoting
- Quote every variable and command substitution: `"${var}"`, `"$(cmd)"`. Unquoted expansion is the single most common bash bug class (word splitting, globbing).
- Prefer arrays over string-built argument lists. Use `"$@"`, never `"$*"`, to pass arguments through.

## Naming and structure
- Functions: lowercase with underscores, no space before `()`.
- Group related functions. Keep the entry-point logic in a clearly named function or at the bottom of the file, not scattered.

## Portability
- Bash-specific features (arrays, `[[ ]]`, `local`) are the default for anything you control (personal tooling, your own hosts, CI). POSIX `sh` is opt-in only, for scripts that must run on an unknown or minimal shell (embedded targets, arbitrary `/bin/sh`).

## Tooling
- ShellCheck is a hard gate, not advisory. It catches the quoting/word-splitting class of bug that strict mode cannot.

## Sources
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [ShellCheck wiki](https://www.shellcheck.net/wiki/)
- [BashFAQ/105: Why doesn't `set -e` do what I expected?](https://mywiki.wooledge.org/BashFAQ/105) (the canonical reference for the strict-mode gaps above)

Verified: 2026-07-29.
