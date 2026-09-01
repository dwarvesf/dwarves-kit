# Proof of done: client activation + key-sharing observables (ID-438 slice, ID-439 slice)

2026-07-25. Acceptance: free→pro is one stored key; the doctor line reads entitlement,
grace and available updates; sharing is visible server-side and self-degrading.

## Green run

Command: `bin/activate <freshly minted craft key>` (staging, key via env-token mint)
Exit: 0
Output: key stored 0600 at $DWARVES_KIT_LICENSE; "craft · 1 seat(s) · updates until
2027-07-25 · stream ON"; "stream: v2.0.1 available (you're on v2.0.0)" , the ID-438
version-check line, live.
Verdict: PASS

Command: `bin/activate --status` with no key file
Exit: 0
Output: "no key stored: free core, fully functional" , free is the absence of a key.
Verdict: PASS

Command: admin visibility after client calls
Exit: 0
Output: /admin/licenses rows now carry use_today + distinct_callers_today (hashed
fingerprints, no raw IPs). Observed 1/1 immediately after two calls: KV is eventually
consistent, the counter is directional, not an invoice.
Verdict: PASS

## NEGATIVE CONTROL (revert -> RED -> restore)

Command: revoke the key (revert), then `bin/activate --status`
Exit: 0 (deliberate: the client never hard-fails)
Output: "key status: revoked , the install keeps working (perpetual fallback); the
stream is off" , RED on the stream, calm on the runtime, exactly the doctrine.
Restore: POST /admin/licenses/<key>/restore returns it to active.
Verdict: PASS

Command: `bin/activate` with no args
Exit: 64 (usage)
Verdict: PASS

## Not covered here

The 429 daily-cap path (STREAM_DAILY_CAP=200) is code-reviewed but not exercised ,
driving 200 real fetches against staging buys nothing; a worker-local test belongs
with the ID-412 gateway suite. /verify now returns grace:true inside the 14-day
window (ID-439 slice); the refund→revoke transaction stays queued with the
merchant-of-record wiring.
