#!/usr/bin/env python3
"""Stdlib tests for session-recall. Run: python3 -m unittest discover -s tests"""
import hashlib
import os
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)

import session_recall as r  # noqa: E402

SEED = os.path.join(ROOT, "fixtures", "seed.jsonl")
BIN = os.path.join(ROOT, "bin", "session-recall")


class TestRecall(unittest.TestCase):
    def test_known_decision_hits_right_turn(self):
        entries = r.load(SEED)
        hits = r.search(entries, "manual backoff loop because we avoid")
        self.assertEqual(len(hits), 1)
        idx, entry, n = hits[0]
        self.assertEqual(idx, 2)
        self.assertEqual(r._role(entry), "assistant")

    def test_negative_control_empty(self):
        hits = r.search(r.load(SEED), "string-that-does-not-exist-zzz")
        self.assertEqual(hits, [])

    def test_negative_control_cli_clean_exit(self):
        p = subprocess.run([sys.executable, BIN, "string-that-does-not-exist-zzz",
                            "--file", SEED], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, "negative control must exit clean (0)")
        self.assertEqual(p.stdout, "", "negative control must produce no stdout")

    def test_matches_across_block_types(self):
        # a file path lives only inside tool_use input / tool_result, not prose
        hits = r.search(r.load(SEED), "src/fetch_client.py")
        self.assertGreaterEqual(len(hits), 2)

    def test_turn_grouped_output_has_indicator(self):
        out = r.render(r.search(r.load(SEED), "backoff retry wrapper"), "backoff retry wrapper")
        self.assertIn("── turn", out)
        self.assertIn("»backoff retry wrapper«", out)

    @staticmethod
    def _digest(path):
        with open(path, "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()

    def test_read_only_does_not_mutate(self):
        before = self._digest(SEED)
        r.search(r.load(SEED), "backoff")
        subprocess.run([sys.executable, BIN, "backoff", "--file", SEED], capture_output=True)
        self.assertEqual(before, self._digest(SEED), "recall must never mutate the transcript")

    def test_determinism(self):
        a = subprocess.run([sys.executable, BIN, "backoff", "--file", SEED],
                           capture_output=True, text=True).stdout
        b = subprocess.run([sys.executable, BIN, "backoff", "--file", SEED],
                           capture_output=True, text=True).stdout
        self.assertEqual(a, b)


if __name__ == "__main__":
    unittest.main()
