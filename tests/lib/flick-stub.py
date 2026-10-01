#!/usr/bin/env python3
"""Test-only stub for the flick decision CLI. Never shipped, never run outside tests.

Usage: flick-stub.py <state-dir>
Binds 127.0.0.1 on a free port and writes the port to <state-dir>/port once it listens.
The first URL path segment picks the behaviour (FLICK_URL=http://127.0.0.1:<port>/<mode>):

  ok          valid answer for every question id in the request body
  401, 500    that HTTP status with a small body
  slow        sleeps 4 s, then answers like ok
  malformed   200 with a body that is not JSON
  noanswers   200 with JSON that has no answers object
  badprobs    probabilities sum to 0.5
  tie         the two top probabilities are equal
  extrakey    an answer for an id that was never requested
  missingkey  drops the first requested id
  extraprob   a probability for a choice that was never offered
  wrongchoice the stated choice is not the highest-probability one

Every request is recorded in <state-dir>: `count` (one line per request), `last.json` (the last
body), `bodies.log` (all bodies, one per line), `auth.log` (whether an Authorization header arrived,
never its value).
"""
import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STATE = sys.argv[1]


def answers_for(body, mode):
    ids = list(body.get("questions", {}).keys())
    out = {}
    for qid in ids:
        keys = list(body["questions"][qid].get("criteria", {}).keys())
        if not keys:
            continue
        rest = [k for k in keys[1:]]
        probs = {keys[0]: 0.7}
        for k in rest:
            probs[k] = round(0.3 / len(rest), 6) if rest else 0.0
        if not rest:
            probs[keys[0]] = 1.0
        if mode == "badprobs":
            probs = {k: v / 2 for k, v in probs.items()}
        if mode == "tie" and len(keys) >= 2:
            probs = {k: 0.0 for k in keys}
            probs[keys[0]] = probs[keys[1]] = 0.5 if len(keys) == 2 else 0.4
            for k in keys[2:]:
                probs[k] = 0.2 / (len(keys) - 2)
        if mode == "extraprob":
            probs["zz-extra"] = 0.0
        choice = max(probs, key=probs.get)
        if mode == "wrongchoice":
            choice = keys[-1]
        out[qid] = {"type": "choice", "choice": choice, "probabilities": probs}
    if mode == "extrakey":
        out["q99"] = {"type": "choice", "choice": "none", "probabilities": {"none": 1.0}}
    if mode == "missingkey" and out:
        out.pop(sorted(out)[0])
    return {"answers": out}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length)
        with open(os.path.join(STATE, "count"), "a") as f:
            f.write("1\n")
        with open(os.path.join(STATE, "last.json"), "wb") as f:
            f.write(raw)
        with open(os.path.join(STATE, "bodies.log"), "ab") as f:
            f.write(raw.replace(b"\n", b" ") + b"\n")
        with open(os.path.join(STATE, "auth.log"), "a") as f:
            f.write("bearer\n" if self.headers.get("Authorization", "").startswith("Bearer ") else "none\n")
        mode = self.path.strip("/").split("/")[0].split("?")[0] or "ok"
        if mode in ("401", "500"):
            return self.send(int(mode), b'{"error":"stub"}')
        if mode == "malformed":
            return self.send(200, b"this is not json {")
        if mode == "noanswers":
            return self.send(200, b'{"hello":"world"}')
        if mode == "slow":
            time.sleep(4)
        try:
            body = json.loads(raw)
        except ValueError:
            return self.send(422, b'{"error":"bad body"}')
        self.send(200, json.dumps(answers_for(body, mode)).encode())

    def send(self, status, payload):
        try:
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        except (BrokenPipeError, ConnectionResetError):
            pass


if __name__ == "__main__":
    os.makedirs(STATE, exist_ok=True)
    srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    with open(os.path.join(STATE, "port.tmp"), "w") as f:
        f.write(str(srv.server_address[1]))
    os.replace(os.path.join(STATE, "port.tmp"), os.path.join(STATE, "port"))
    srv.serve_forever()
