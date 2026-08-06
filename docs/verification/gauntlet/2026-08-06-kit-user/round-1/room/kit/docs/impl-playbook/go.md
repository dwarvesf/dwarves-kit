# Go implementation rules

Distills Effective Go and the Uber Go Style Guide. Read before writing or reviewing Go.

## Errors
- Return errors, do not panic, except for truly unrecoverable init failures.
- Wrap with context: `fmt.Errorf("doing X: %w", err)`. Never swallow an error silently.
- Check an error immediately after the call that can produce it.

## Naming
- Package names: short, lowercase, no underscores, no stutter (`http.Client`, not `http.HTTPClient`).
- Interfaces named by behavior, often with an `-er` suffix (`Reader`, `Closer`).
- Exported identifiers get a doc comment that starts with the identifier's own name.

## Structure
- Accept interfaces, return structs.
- Keep `main` thin; put logic in importable packages.
- Group related methods near their type. Split a file by purpose once it grows large.

## Concurrency
- Do not start a goroutine without knowing how it stops (context cancellation or a done channel).
- Guard shared state with a mutex or a channel. Never assume a race will not happen.
- Prefer `context.Context` as the first parameter for anything cancellable or with a timeout.

## Testing
- Table-driven tests are the default shape for multiple cases.
- Call `t.Helper()` in test helpers so failures point at the caller's line.

## Tooling
- `golangci-lint` before commit.
- `gofmt`/`goimports` are non-negotiable. Never hand-format Go code.

## Sources
- [Effective Go](https://go.dev/doc/effective_go) (frozen at 2009 by its own note; no generics/modules coverage, the Uber guide covers the modern parts)
- [Uber Go Style Guide](https://github.com/uber-go/guide/blob/master/style.md)

Verified: 2026-07-29.
