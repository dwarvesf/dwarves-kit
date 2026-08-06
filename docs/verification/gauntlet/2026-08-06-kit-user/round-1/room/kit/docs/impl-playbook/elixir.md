# Elixir implementation rules

Distills the community Elixir Style Guide, Credo, Dialyzer/dialyxir, and OTP's core design principles.

## Style
- `mix format` is the formatter, non-negotiable, never hand-format. Beyond formatting: `snake_case` for functions/atoms/variables, `PascalCase` for modules, predicate functions end in `?` (not an `is_` prefix).
- Pipe operator (`|>`) for 3+ chained transformations. A single call does not need a pipe.
- Pattern matching in function heads over `if/else` chains. Use `with` to chain fallible operations that each return `{:ok, _} | {:error, _}`, instead of nested `case` statements.

## OTP process design
- A plain module with pure functions is the default. Reach for a GenServer only when you need to hold mutable state across calls, serialize access to a shared resource, or respond asynchronously.
- "Let it crash": a process fails fast on invariant violations; a supervisor handles recovery (`:one_for_one`, `:one_for_all`, `:rest_for_one`), not defensive in-process error handling everywhere.

## Types
- Since Elixir 1.20 (June 2026), the compiler itself does sound, gradual set-theoretic type checking, built in, not a separate tool. It infers types across patterns, function calls, protocols, and anonymous functions with no `@spec` annotations required, and reports *verified* bugs (typing violations guaranteed to fail at runtime) as compile errors. This is now the primary line of defense against type errors.
- Dialyzer/dialyxir is a separate, older, best-effort tool (unsound success typing, warnings only, no compiler integration). Keep it in CI as a complementary check for gaps the compiler's type system doesn't cover yet, it is no longer the main line of defense.
- `@spec`/`@type` still matter for public API boundaries, documenting intent for readers and feeding Dialyzer, but the compiler's own inference no longer depends on them. A wrong spec is worse than no spec, it misleads both Dialyzer and readers.

## Testing
- ExUnit is the test runner (`mix test`), built in, no alternative needed.
- For invariant-heavy logic, `StreamData` (property-based testing, `ExUnitProperties`/`check all`) is worth the dependency. Example-based tests are the default otherwise.

## Web (Phoenix, when applicable)
- Phoenix is the de facto default for anything web-facing in Elixir. Keep business logic in Contexts (dedicated modules like `Accounts`, `Blog`); controllers stay thin and framework-agnostic.

## Tooling
- `mix credo` before commit, hard gate. `mix format --check-formatted` in CI.

## Sources
- [Elixir Style Guide (community)](https://github.com/christopheradams/elixir_style_guide)
- [Credo](https://github.com/rrrene/credo)
- [Elixir GenServer / Mix-OTP guide](https://elixir.hexdocs.pm/genservers.html)
- [StreamData: property-based testing](https://elixir-lang.org/blog/2017/10/31/stream-data-property-based-testing-and-data-generation-for-elixir/)
- [Phoenix Contexts](https://phoenix.hexdocs.pm/contexts.html)
- [Elixir v1.20 released: now a gradually typed language](https://elixir-lang.org/blog/2026/06/03/elixir-v1-20-0-released/)
- [Gradual set-theoretic types (Elixir docs)](https://elixir.hexdocs.pm/gradual-set-theoretic-types.html)

Verified: 2026-08-03.
