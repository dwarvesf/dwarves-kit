---
paths: ["**/api/**", "**/pkg/**", "**/cmd/**", "**/internal/**"]
---

Go backend conventions for this project.

## Style

- Use Go idioms. Error handling: return errors, don't panic.
- Prefer stdlib over third-party libraries. Justify new dependencies.
- Test files go next to the code they test: `user.go` / `user_test.go`.
- Use table-driven tests for functions with multiple input/output cases.

## Error handling

- Always wrap errors with context: `fmt.Errorf("fetching user %s: %w", id, err)`
- Return errors up the stack. Only log at the top-level handler.
- Use sentinel errors (`var ErrNotFound = errors.New(...)`) for expected conditions.

## Naming

- Interfaces: describe behavior, not implementation (`Reader`, not `FileReader`).
- Unexported types/functions are fine. Don't export unless another package needs it.
- Package names: short, lowercase, single word. `user` not `userService`.

## Database

- Use prepared statements or parameterized queries. Never string-concat SQL.
- Transactions: always defer `tx.Rollback()` and call `tx.Commit()` at the end.
- Close rows: `defer rows.Close()` immediately after `db.Query()`.
