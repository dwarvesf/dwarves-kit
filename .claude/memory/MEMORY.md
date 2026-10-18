# dwarves-kit memory index

- [An id inside a test is the test's input: stripping it from the doc the test reads breaks the test, and only the full suite catches it](id-strip-breaks-anchored-tests.md)
- [North-star direction: check every proposal against PHILOSOPHY section 6 (N1-N7); every board row gets a module tag at intake](north-star-direction.md)
- [Gate ledger keys by spec slug + Lane header required](gate-ledger-keys-by-spec-slug.md): record gates under the branch/spec slug, not the board ID
- [Pin the operator layer in tests; resolve every surface through kit-config.sh](operator-layer-fence-and-surface.md): an operator preference otherwise turns a suite red and bin/config lies
- [Hook stderr on exit 0 reaches no one](hook-stderr-dropped-on-exit-zero.md): an allowed-path notice must be exit-0 JSON (systemMessage + additionalContext); test stdout, not stderr
- [A PR file guard must read both rename sides](pr-file-list-must-read-both-rename-sides.md): REST files list with previous_filename, paginated, refuse at 3000; pin the merge head
