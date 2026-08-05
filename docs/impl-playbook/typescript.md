# TypeScript implementation rules

Distills the Google TypeScript Style Guide plus Effective TypeScript's core advice.

## Types
- Never `any`. Use `unknown` plus a narrowing check when a type is genuinely unknown.
- Prefer inference where the inferred type is already correct and obvious. Always annotate function signatures and exported values.
- Structural typing is the model. Do not fight it with unnecessary nominal wrappers.

## Style
- `const` by default, `let` only when reassignment is real, never `var`.
- Prefer a union or discriminated union over independent boolean flags for state (one `status` field beats two unrelated booleans).
- No `enum` for a simple string set; use a `const` object plus a derived union type, unless the project already standardized on `enum` (Effective TypeScript's position; Google's guide itself permits plain `enum` and bans only `const enum`).

## Structure
- Named exports only, no `default export` (Google guide): a default export has no fixed name at the import site, which invites inconsistent aliasing across files.
- One export per concern. Avoid a single file re-exporting everything as a dumping ground.
- Async functions return `Promise<T>` explicitly in their signature. Do not mix callback and promise styles in one module.

## Errors
- Model expected failures in the return type (a result-shaped union or a typed thrown error). Do not leave a `catch (e)` with `e` unhandled as `unknown`.

## Process lifecycle
- A child process spawned via `execFileSync`/`execSync`/plain `spawn` inherits the parent's process group. Killing the parent's PID signals only that one process; a child already forked (a test runner's own worker pool, for example) is orphaned to init and keeps running instead of dying with it.
- Any script that shells out to a long-running or pool-spawning subprocess (a test runner, a build watcher, a mutation-testing harness) and needs to be interruptible: spawn with `detached: true`, keep the child handle in scope, and on both `SIGINT` and `SIGTERM` kill the whole group with `process.kill(-child.pid, "SIGTERM")`, not `child.kill()`. `execFileSync`/`execSync` give no handle to kill, so an interruptible subprocess call must use async `spawn`.
- Handle `SIGTERM`, not only `SIGINT`. A plain `kill <pid>` sends `SIGTERM`; a script that only registers `SIGINT` cleans up on Ctrl-C but leaks its subprocess tree on an ordinary `kill`.

## Tooling
- `pnpm` for package management. ESLint plus `strict: true` in tsconfig are the enforced layer.

## Sources
- [Google TypeScript Style Guide](https://google.github.io/styleguide/tsguide.html)
- [Effective TypeScript (official companion repo, 2nd ed.)](https://github.com/danvk/effective-typescript)
- [Node.js child_process docs, `detached` option](https://nodejs.org/api/child_process.html#optionsdetached)

Verified: 2026-08-05.
