# Financial-data handling rules

Distills Modern Treasury's decimal-vs-float guidance and Stripe's idempotency-key pattern. Applies to any code touching money, balances, or ledger entries (trading, family-office, treasury/ICY work).

## Never use float for money
- Store and compute monetary amounts as integer minor units (cents) or a fixed-point/decimal type, never `float`/`double`. Floating point cannot represent most decimal fractions exactly, and rounding errors compound across a ledger.
- Pick a rounding rule once per domain (typically banker's rounding, round-half-to-even) and apply it consistently. Do not let each call site round differently.

## Ledger over mutation
- Prefer an append-only ledger (every balance change is a recorded entry, not an overwritten field) over mutating a running balance in place. The current balance is a derived sum, not the source of truth.
- Every entry carries enough context to reconstruct why it happened (source, timestamp, actor) so an audit trail exists without extra tooling.

## Idempotency for money-moving operations
- Any operation that moves or creates money (a transfer, a mint, a payout) takes an idempotency key from the caller. Replaying the same request with the same key must not double-execute; store seen keys and their result, and return the stored result on a repeat.
- Idempotency lives at the operation boundary (the API/function that actually moves money), not sprinkled through the call chain.
- Stripe-specific caveats (verify against your own provider, but these are common idempotency-layer behaviors worth designing for): keys prune after 24 hours, a replay past that window runs as a new request. Reusing a key with DIFFERENT parameters is not a silent replay, Stripe returns a 400 `idempotency_error` and treats it as a caller bug. Concurrent requests sharing one key are NOT deduplicated server-side, the second request errors instead of waiting; the caller still needs its own retry/locking around the race.

## Sources
- [Floats Don't Work for Storing Cents (Modern Treasury)](https://www.moderntreasury.com/journal/floats-dont-work-for-storing-cents)
- [Designing robust and predictable APIs with idempotency (Stripe)](https://stripe.com/blog/idempotency)
- [Implementing Stripe-like Idempotency Keys in Postgres (brandur.org)](https://brandur.org/idempotency-keys)

Verified: 2026-08-03.
