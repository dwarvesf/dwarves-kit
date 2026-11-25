"""The one `ntn` runner every Notion source shares.

A Notion API blip (the CLI's bare "Failed to execute public API request", a
5xx, a 429, a stalled call) heals within seconds, but a single failed call
used to end the whole sync run. This runner retries it, with one rule that
matters more than the retry itself: only a call that is safe to repeat is
retried on an ambiguous failure.

    read    GET (no -X), `datasources resolve`, and a POST to a `/query` path
            (a data-source query is a read that happens to need a body).
            Retried on any transient failure, including a bare error or a
            timeout: repeating it changes nothing.
    write   every other POST, and PATCH. The first attempt may have landed
            before the error came back, so a bare error, a 5xx or a timeout
            is NOT retried (a retried create would mint a duplicate page).
            Retried only on a 429, which Notion answers before processing.

An auth or request error (401, 403, 404, 400) is never retried: repeating it
cannot fix it. On a failure that is final, the runner raises `SystemExit`
with `ntn <args[:3]> failed: <stderr>`, the same message and exception type
the three per-source copies raised before, so a caller's tick log is unchanged.
"""

import json
import os
import re
import subprocess
import sys
import time

ATTEMPTS = 3                                       # first try plus 2 retries
# seconds before retry 1, then retry 2 (tests set 0,0)
BACKOFF = tuple(float(x) for x in
                os.environ.get("NTN_RETRY_BACKOFF", "5,20").split(","))
TIMEOUT = float(os.environ.get("NTN_CALL_TIMEOUT", "120"))  # seconds per call

# The CLI's bare "Failed to execute public API request", a 429/500-504 in
# either spelling the CLI prints ("failed (500 Internal ..." and "failed: 502
# Bad Gateway <html>"), a stalled call, a dropped connection.
_STATUS = r"(?:429|50[0-4])"
TRANSIENT_RE = re.compile(
    rf"Failed to execute public API request|request failed:? \(?{_STATUS}\b"
    rf"|\({_STATUS}[ )]|service_unavailable|rate_limited|timed out"
    r"|temporarily unavailable|connection (reset|refused)", re.IGNORECASE)
# The one failure Notion raises before it processes anything.
RATE_LIMIT_RE = re.compile(
    r"rate_limited|request failed:? \(?429\b|\(429[ )]", re.IGNORECASE)


class _NtnError(Exception):
    def __init__(self, msg: str, err: str, timed_out: bool = False):
        super().__init__(msg)
        self.err = err
        self.timed_out = timed_out


def is_read(args: list) -> bool:
    """True when repeating this call cannot change Notion state."""
    if args[:2] == ["datasources", "resolve"]:
        return True
    method = "GET"
    if "-X" in args:
        i = args.index("-X")
        method = args[i + 1].upper() if i + 1 < len(args) else "GET"
    if method == "GET":
        return True
    path = next((a for a in args[1:] if a.startswith("v1/")), "")
    return method == "POST" and path.split("?")[0].endswith("/query")


def _once(args: list, data: dict | None):
    cmd = ["ntn", *args]
    # ntn reads a piped stdin as a request body, so a call with no body gets
    # /dev/null: a read must never inherit ours and turn into a write.
    feed = {"stdin": subprocess.DEVNULL}
    if data is not None:
        cmd += ["-d", "@-"]
        feed = {"input": json.dumps(data)}
    head = ' '.join(args[:3])
    try:
        r = subprocess.run(cmd, capture_output=True, text=True,
                           timeout=TIMEOUT, **feed)
    except subprocess.TimeoutExpired:
        msg = f"ntn {head} timed out after {TIMEOUT:g}s"
        raise _NtnError(msg, msg, timed_out=True)
    if r.returncode != 0:
        err = r.stderr.strip()[:500]
        raise _NtnError(f"ntn {head} failed: {err}", err)
    return json.loads(r.stdout) if r.stdout.strip() else {}


def _retryable(args: list, exc: _NtnError) -> bool:
    if is_read(args):
        return exc.timed_out or bool(TRANSIENT_RE.search(exc.err))
    return bool(RATE_LIMIT_RE.search(exc.err))


def run_ntn(args: list, data: dict | None = None):
    for attempt in range(ATTEMPTS):
        try:
            return _once(args, data)
        except _NtnError as exc:
            if attempt == ATTEMPTS - 1 or not _retryable(args, exc):
                raise SystemExit(str(exc))
            wait = BACKOFF[min(attempt, len(BACKOFF) - 1)]
            print(f"ntn {' '.join(args[:3])} transient failure, retry "
                  f"{attempt + 1}/{ATTEMPTS - 1} in {wait:g}s",
                  file=sys.stderr, flush=True)
            time.sleep(wait)
