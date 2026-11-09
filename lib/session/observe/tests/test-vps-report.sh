#!/usr/bin/env bash
# session-report signer + distiller smoke test. NO network calls.
#
# The signer test is load-bearing: a wrong HMAC signature is a SILENT 401 at
# the live endpoint, so we prove the exact bytes offline before any POST.
#
# Test [1] computes the expected signature with an INDEPENDENT reimplementation
# of tools/vps-mon/worker/src/hmac.ts::computeSignature (msg =
# `${ts}\n${host}\n${sha256hex(body)}`, key = secret string's UTF-8 bytes,
# output "sha256="+hex) and asserts session-report's own sign_request produces
# the identical value. Two independent code paths agreeing == the scheme is
# right. (The same value also matches a node-crypto cross-check run during
# development; see the impl notes.)
#
# Run: bash tests/test-vps-report.sh
# Pass: prints "vps-report: all N passed", exit 0.
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${DIR}/bin/session-report"

pass=0; fail=0
ok() { echo "  ok: $*"; pass=$((pass+1)); }
no() { echo "  FAIL: $*" >&2; fail=$((fail+1)); }

echo "[1] sign_request == independent hmac.ts-equivalent reimplementation"
got="$(python3 - "$BIN" <<'PY'
import sys, hashlib, hmac
from importlib.machinery import SourceFileLoader
import importlib.util
_ld = SourceFileLoader("ccvr", sys.argv[1]); _sp = importlib.util.spec_from_loader("ccvr", _ld)
m = importlib.util.module_from_spec(_sp); sys.modules["ccvr"] = m; _ld.exec_module(m)  # load_module() is gone in newer Pythons

KEY_STR = "test-key-32-bytes-base64-abcdEFGH"
TS, HOST, BODY = 1700000000, "cc-air", b"hello-body-bytes"

# Independent reference (mirrors hmac.ts, does NOT call session-report):
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
import importlib.util
_ld = SourceFileLoader("ccvr", sys.argv[1]); _sp = importlib.util.spec_from_loader("ccvr", _ld)
m = importlib.util.module_from_spec(_sp); sys.modules["ccvr"] = m; _ld.exec_module(m)  # load_module() is gone in newer Pythons
print(m.key_bytes("abc \n").decode() == "abc")
PY
)"
[[ "$got" == "True" ]] && ok "trim ok" || no "trim wrong: $got"

echo "[3] negative control: wrong key produces a DIFFERENT signature"
got="$(python3 - "$BIN" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
import importlib.util
_ld = SourceFileLoader("ccvr", sys.argv[1]); _sp = importlib.util.spec_from_loader("ccvr", _ld)
m = importlib.util.module_from_spec(_sp); sys.modules["ccvr"] = m; _ld.exec_module(m)  # load_module() is gone in newer Pythons
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
import importlib.util
_ld = SourceFileLoader("ccvr", sys.argv[1]); _sp = importlib.util.spec_from_loader("ccvr", _ld)
m = importlib.util.module_from_spec(_sp); sys.modules["ccvr"] = m; _ld.exec_module(m)  # load_module() is gone in newer Pythons
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
import importlib.util
_ld = SourceFileLoader("ccvr", sys.argv[1]); _sp = importlib.util.spec_from_loader("ccvr", _ld)
m = importlib.util.module_from_spec(_sp); sys.modules["ccvr"] = m; _ld.exec_module(m)  # load_module() is gone in newer Pythons
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
       | SESSION_REPORT_HMAC_KEY=test-key "$BIN" --dry-run 2>/dev/null)"
if python3 -c "import sys,json; d=json.load(sys.stdin); assert d['envelope']['schema_version']==1; assert d['X-Signature'].startswith('sha256='); print('ok')" <<<"$got" >/dev/null 2>&1; then
  ok "dry-run envelope valid"
else
  no "dry-run output bad: $got"
fi

# --- operator config seam: no built-in URL, host id, or vault reference -------------------
# Every case pins the operator and kit-root config layers to temp dirs, so a real operator
# kit.toml on the machine running the suite can never leak in.
T="$(mktemp -d "${TMPDIR:-/tmp}/vps-report.XXXXXX")" || exit 1; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/none" "$T/op"
sr() { # sr <env assignments as one string> -- run session-report with a pinned, empty config
  env -u SESSION_REPORT_URL -u SESSION_REPORT_HB_TOKEN -u SESSION_REPORT_HMAC_KEY \
    KIT_CONFIG_ROOT="$T/none" KIT_CONFIG_OPERATOR="${OPDIR:-$T/none}" "$@"
}

echo "[7] no URL anywhere: one-line message, exit 2, no crash"
out="$(OPDIR="$T/none" sr "$BIN" 2>&1 </dev/null)" && rc=0 || rc=$?
[[ $rc -eq 2 ]] && ok "exit 2 without a URL" || no "rc=$rc out=$out"
grep -q 'no vps-mon URL' <<<"$out" && ok "message names the key" || no "message: $out"
[[ "$(wc -l <<<"$out" | tr -d ' ')" == "1" ]] && ok "message is one line" || no "multi-line: $out"

echo "[8] URL from the operator config passes the gate; missing token degrades to a message"
printf '[session_report]\nurl = "http://127.0.0.1:1"\n' > "$T/op/kit.toml"
out="$(OPDIR="$T/op" sr "$BIN" 2>&1 </dev/null)" && rc=0 || rc=$?
[[ $rc -eq 2 ]] && grep -q 'no heartbeat token' <<<"$out" && ok "URL accepted, token message" || no "rc=$rc out=$out"

echo "[9] hb_token_cmd supplies the token; the unreachable URL fails soft"
printf '#!/bin/sh\necho fake-token\n' > "$T/tok"; chmod +x "$T/tok"
printf '[session_report]\nurl = "http://127.0.0.1:1"\nhb_token_cmd = "%s"\n' "$T/tok" > "$T/op/kit.toml"
out="$(OPDIR="$T/op" sr "$BIN" 2>&1 </dev/null)" && rc=0 || rc=$?
[[ $rc -eq 1 ]] && grep -q 'heartbeat: None' <<<"$out" && ok "token from command, soft failure" || no "rc=$rc out=$out"

echo "[10] host id: config key wins, else the local hostname"
printf '[session_report]\nhost_id = "acme-host"\n' > "$T/op/kit.toml"
got="$(printf '%s' '{"files":1}' | OPDIR="$T/op" sr "$BIN" --dry-run 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['X-Host-Id'])")"
[[ "$got" == "acme-host" ]] && ok "host_id from config" || no "host_id: $got"
got="$(printf '%s' '{"files":1}' | OPDIR="$T/none" sr "$BIN" --dry-run 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['X-Host-Id'])")"
[[ "$got" == "$(hostname -s)" ]] && ok "host_id defaults to the short hostname" || no "default host_id: $got"

echo "[11] a failing token command reports itself and degrades, no crash"
printf '#!/bin/sh\nexit 3\n' > "$T/badtok"; chmod +x "$T/badtok"
printf '[session_report]\nurl = "http://127.0.0.1:1"\nhb_token_cmd = "%s"\n' "$T/badtok" > "$T/op/kit.toml"
out="$(OPDIR="$T/op" sr "$BIN" 2>&1 </dev/null)" && rc=0 || rc=$?
[[ $rc -eq 2 ]] && grep -q 'hb_token_cmd exited 3' <<<"$out" && ok "failing command named, exit 2" || no "rc=$rc out=$out"

echo
if [[ $fail -gt 0 ]]; then echo "vps-report: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "vps-report: all $pass passed"
