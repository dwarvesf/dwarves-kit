# Rust implementation rules

Distills the Rust API Guidelines (rust-lang/api-guidelines) plus standard community error-handling and concurrency conventions (the Rust Book).

## Naming
- Types and traits: `UpperCamelCase`. Functions, variables, modules: `snake_case`. Constants: `SCREAMING_SNAKE_CASE`.
- Conversion methods: `as_` for a cheap borrowed view, `to_` for an expensive owned copy, `into_` for a consuming conversion.
- Getters have no `get_` prefix: `fn name(&self) -> &str`, not `fn get_name(&self)`.

## Error handling
- Library code returns `Result<T, E>` with a real error type (`thiserror`). No `unwrap`/`expect` outside tests.
- Binary/CLI code may use `anyhow` for the top-level error type, but still never `unwrap` on user input.
- Reserve `panic!` for programmer bugs (broken invariants), not expected failure paths.

## Ownership and API shape
- Take `&str`/`&[T]` in function signatures, not `&String`/`&Vec<T>`, unless ownership is genuinely needed.
- Prefer returning owned data in public APIs over lifetime-laden borrows, unless a measured perf need says otherwise.
- Implement `Debug` for every public type. Implement `Default`, `Clone`, `PartialEq` when they make sense for the type.

## Documentation
- Every public item gets a doc comment. A non-trivial one gets a runnable `# Examples` block (doctested).

## Concurrency
- Prefer message-passing (channels) over shared-state-plus-mutex when the design allows it.
- `Send`/`Sync` bounds are load-bearing. Do not silently work around them.

## Tooling
- `cargo clippy` and `cargo fmt` before commit. `cargo test` also runs doctests; do not skip them.

## Sources
- [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/)
- [The Rust Book, ch. 9: error handling](https://doc.rust-lang.org/book/ch09-00-error-handling.html) (the `thiserror`/`anyhow` split above is community convention, not in the API Guidelines)
- [The Rust Book, ch. 16: message passing](https://doc.rust-lang.org/book/ch16-02-message-passing.html)

Verified: 2026-07-29.
