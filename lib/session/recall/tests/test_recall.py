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

    # --- --project short names and --sessions -----------------------------------
    # Motivating miss: `session recall whathas --project ops-toolkit` printed
    # "no matches" (the dir was never found), and the turn view never named the
    # transcript, so a session hand-rolled jq over ~/.claude/projects instead.

    def _fake_projects(self):
        import shutil
        import tempfile
        import time
        base = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, base)
        main_slug = os.path.join(base, "-Users-me-workspace-zzrepo")
        wt_slug = os.path.join(base, "-Users-me-workspace-zzrepo--claude-worktrees-agent-1")
        os.makedirs(main_slug)
        os.makedirs(wt_slug)
        old = os.path.join(main_slug, "old-session.jsonl")
        new = os.path.join(main_slug, "new-session.jsonl")
        shutil.copy(SEED, old)
        shutil.copy(SEED, new)
        # the worktree slug carries the term too; it must NOT be swept in by the short name
        shutil.copy(SEED, os.path.join(wt_slug, "wt-session.jsonl"))
        now = time.time()
        os.utime(old, (now - 3600, now - 3600))
        os.utime(new, (now, now))
        return base, main_slug

    def test_short_project_name_resolves_to_suffix_match_only(self):
        base, main_slug = self._fake_projects()
        orig = r.PROJECTS
        r.PROJECTS = base
        try:
            self.assertEqual(r.resolve_project_dirs("zzrepo"), [main_slug])
            self.assertEqual(r.resolve_project_dirs("-Users-me-workspace-zzrepo"), [main_slug])
            self.assertEqual(r.resolve_project_dirs("no-such-repo-zzz"), [])
        finally:
            r.PROJECTS = orig

    def test_unknown_project_is_exit_1_not_no_matches(self):
        base, _ = self._fake_projects()
        env = dict(os.environ)
        code = ("import sys, session_recall as r; r.PROJECTS=%r; "
                "sys.exit(r.main(['backoff', '--project', 'no-such-repo-zzz']))") % base
        p = subprocess.run([sys.executable, "-c", code], cwd=ROOT, env=env,
                           capture_output=True, text=True)
        self.assertEqual(p.returncode, 1)
        self.assertIn("no project dir", p.stderr)
        self.assertNotIn("no matches", p.stderr)

    def test_sessions_view_one_line_per_transcript_newest_first(self):
        base, _ = self._fake_projects()
        code = ("import sys, session_recall as r; r.PROJECTS=%r; "
                "sys.exit(r.main(['backoff', '--project', 'zzrepo', '--sessions']))") % base
        p = subprocess.run([sys.executable, "-c", code], cwd=ROOT,
                           capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        lines = p.stdout.strip().splitlines()
        self.assertEqual(lines[0], "# sessions matching 'backoff': 2")
        self.assertEqual(lines[1], r.DATA_MARKER)
        self.assertIn("new-session", lines[2])
        self.assertIn("old-session", lines[3])
        self.assertNotIn("wt-session", p.stdout)
        # the seed fixture has no plain-string user turn, so the opening ask is empty here
        self.assertRegex(lines[2], r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}  new-session\s+\d+ hits  ")

    # --- battery fixes (2026-09-04) -----------------------------------------------

    def test_traversal_and_empty_names_never_resolve(self):
        # `..` IS a dir under PROJECTS, so a guard placed after the isdir check was unreachable
        base, _ = self._fake_projects()
        orig = r.PROJECTS
        r.PROJECTS = base
        try:
            for bad in ("..", ".", "../x", "a/b", ""):
                self.assertEqual(r.resolve_project_dirs(bad), [], bad)
        finally:
            r.PROJECTS = orig

    def test_project_flag_without_value_is_usage_exit_2(self):
        base, _ = self._fake_projects()
        code = ("import sys, session_recall as r; r.PROJECTS=%r; "
                "sys.exit(r.main(['backoff', '--project']))") % base
        p = subprocess.run([sys.executable, "-c", code], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(p.returncode, 2)
        self.assertIn("usage:", p.stderr)

    def test_opening_ask_list_content_and_redaction_and_hook_skip(self):
        entries = [
            {"type": "user", "message": {"role": "user", "content": "<system-reminder>hook noise</system-reminder>"}},
            {"type": "user", "message": {"role": "user", "content": [
                {"type": "text", "text": "rotate the key op://Vault/item/field and ship it"},
                {"type": "image", "source": {}}]}},
        ]
        ask = r.opening_ask(entries)
        self.assertTrue(ask.startswith("rotate the key [redacted] and ship it"))
        self.assertNotIn("op://", ask)

    def test_sessions_view_stops_at_limit_and_says_so(self):
        base, _ = self._fake_projects()
        code = ("import sys, session_recall as r; r.PROJECTS=%r; "
                "sys.exit(r.main(['backoff', '--project', 'zzrepo', '--sessions', '--limit', '1']))") % base
        p = subprocess.run([sys.executable, "-c", code], cwd=ROOT, capture_output=True, text=True)
        lines = p.stdout.strip().splitlines()
        self.assertEqual(lines[0], "# sessions matching 'backoff': 1 (capped by --limit, raise it for more)")
        self.assertIn("new-session", lines[2])  # newest first, the older one never loaded
        self.assertNotIn("old-session", p.stdout)

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
