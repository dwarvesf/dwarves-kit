#!/usr/bin/env bash
# cc-vps-report signer + distiller smoke test. NO network calls.
#
# The signer test is load-bearing: a wrong HMAC signature is a SILENT 401 at
# the live endpoint, so we prove the exact bytes offline before any POST.
#
# Test [1] computes the expected signature with an INDEPENDENT reimplementation
# of tools/vps-mon/worker/src/hmac.ts::computeSignature (msg =
# `${ts}\n${host}\n${sha256hex(body)}`, key = secret string's UTF-8 bytes,
# output "sha256="+hex) and asserts cc-vps-report's own sign_request produces
# the identical value. Two independent code paths agreeing == the scheme is
# right. (The same value also matches a node-crypto cross-check run during
# development; see the impl notes.)
#
# Run: bash tests/test-vps-report.sh
# Pass: prints "vps-report: all N passed", exit 0.
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${DIR}/bin/cc-vps-report"

pass=0; fail=0
ok() { echo "  ok: $*"; pass=$((pass+1)); }
no() { echo "  FAIL: $*" >&2; fail=$((fail+1)); }

echo "[1] sign_request == independent hmac.ts-equivalent reimplementation"
got="$(python3 - "$BIN" <<'PY'
import sys, hashlib, hmac
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("ccvr", sys.argv[1]).load_module()

KEY_STR = "test-key-32-bytes-base64-abcdEFGH"
TS, HOST, BODY = 1700000000, "cc-air", b"hello-body-bytes"

# Independent reference (mirrors hmac.ts, does NOT call cc-vps-report):
ref_msg = f"{TS}\n{HOST}\n{hashlib.sha256(BODY).hexdigest()}".encode()
ref_sig = "sha256=" + hmac.new(KEY_STR.encode(), ref_msg, hashlib.sha256).hexdigest()

# Under test:
got_sig = m.sign_request(m.key_bytes(KEY_STR), TS, HOST, BODY)
print("MATCH" if got_sig == ref_sig else f"MISMATCH got={got_sig} ref={ref_sig}")
PY
)"
[[ "$got" == "MATCH" ]] && ok "signature matches independent reference" || no "$got"

echo "[2] key_bytes strips trailing whitespace (matches keyFromSecret/load_key)"
got="$(python3 - "$BIN" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("ccvr", sys.argv[1]).load_module()
print(m.key_bytes("abc \n").decode() == "abc")
PY
)"
[[ "$got" == "True" ]] && ok "trim ok" || no "trim wrong: $got"

echo "[3] negative control: wrong key produces a DIFFERENT signature"
got="$(python3 - "$BIN" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("ccvr", sys.argv[1]).load_module()
a = m.sign_request(m.key_bytes("right-key"), 1700000000, "cc-air", b"body")
b = m.sign_request(m.key_bytes("WRONG-key"), 1700000000, "cc-air", b"body")
print(a != b)
PY
)"
[[ "$got" == "True" ]] && ok "wrong key differs" || no "wrong key collided"

echo "[4] distill: headline metrics from this-branch report json shape"
got="$(python3 - "$BIN" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("ccvr", sys.argv[1]).load_module()
report = {
  "files": 42,
  "skills": [{"skill":"prose-rag","count":5,"errors":1}],
  "tools": [{"tool":"Bash","count":100,"errors":3},{"tool":"Read","count":50,"errors":0}],
  "hooks": [{"hook":"x.sh","count":3,"p50_ms":1,"p95_ms":2,"max_ms":9}],
  "hook_errors": 2,
  "subagents": {
    "by_day": [{"day":"2026-06-14","spawns":4,"prompts":2}],
    "by_type": [{"subagent_type":"Explore","count":3},{"subagent_type":"fork","count":1}],
  },
}
d = m.distill(report)
assert d["transcripts"] == 42, d
assert d["subagent_per100"] == 200.0, d
assert d["subagent_total"] == 4, d
assert d["subagent_top_type"] == "Explore", d
assert d["tool_total"] == 150, d
assert d["tool_errors"] == 3, d
assert d["hook_errors"] == 2, d
assert "friction_count" in d, d
print("OK")
PY
)"
[[ "$got" == "OK" ]] && ok "distill correct" || no "distill wrong: $got"

echo "[5] distill defensive: richer (PR #333/#337) fields read via .get()"
got="$(python3 - "$BIN" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("ccvr", sys.argv[1]).load_module()
report = {"files":1,"friction":{"total":7},"cost":{"total_usd":1.23,"cache_hit_ratio":0.88}}
d = m.distill(report)
assert d["friction_count"] == 7, d
assert d["cost_total_usd"] == 1.23, d
assert d["cost_cache_hit"] == 0.88, d
print("OK")
PY
)"
[[ "$got" == "OK" ]] && ok "richer fields tolerated" || no "richer fields wrong: $got"

echo "[6] --dry-run prints a valid envelope + signature, no network"
got="$(printf '%s' '{"files":3,"subagents":{"by_day":[],"by_type":[]}}' \
       | CC_VPS_HMAC_KEY=test-key "$BIN" --dry-run 2>/dev/null)"
if python3 -c "import sys,json; d=json.load(sys.stdin); assert d['envelope']['schema_version']==1; assert d['X-Signature'].startswith('sha256='); print('ok')" <<<"$got" >/dev/null 2>&1; then
  ok "dry-run envelope valid"
else
  no "dry-run output bad: $got"
fi

echo
if [[ $fail -gt 0 ]]; then echo "vps-report: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "vps-report: all $pass passed"
