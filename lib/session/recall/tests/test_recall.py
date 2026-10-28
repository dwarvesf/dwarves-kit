#!/usr/bin/env python3
"""Stdlib tests for session-recall. Run: python3 -m unittest discover -s tests"""
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)

import session_recall as r  # noqa: E402

SEED = os.path.join(ROOT, "fixtures", "seed.jsonl")
BIN = os.path.join(ROOT, "bin", "session-recall")
NONDICT = os.path.join(ROOT, "tests", "nondict-edge", "nondict.jsonl")  # OUTSIDE fixtures/: hostile, not a seed
NONDICT_MSG = os.path.join(ROOT, "tests", "nondict-edge", "nondict-message.jsonl")  # valid objects, hostile `message`
TAIL_BASIC = os.path.join(ROOT, "fixtures", "tail-basic.jsonl")           # 14 kept turns, no noise
TAIL_DROPPED = os.path.join(ROOT, "fixtures", "tail-dropped-kinds.jsonl")  # one entry per dropped kind
FINAL_BACKTICK = os.path.join(ROOT, "fixtures", "final-backtick.jsonl")   # trailing thinking/tool_use-only turns, ``` fences
FINAL_TILDE = os.path.join(ROOT, "fixtures", "final-tilde.jsonl")         # ~~~~markdown holding ``` and ~~~ blocks
FINAL_NO_TEXT = os.path.join(ROOT, "fixtures", "final-no-text.jsonl")     # assistant turns with no text at all
RESULT_JSON = os.path.join(ROOT, "fixtures", "result-json.jsonl")         # two assistant msgs; the last: prose + one JSON object
RESULT_BAD_JSON = os.path.join(ROOT, "fixtures", "result-bad-json.jsonl")  # last assistant msg holds a malformed {...}
WRITTEN_WRITE = os.path.join(ROOT, "fixtures", "written-write.jsonl")     # two Writes to /scratch/plan.md, one other
WRITTEN_HEREDOC = os.path.join(ROOT, "fixtures", "written-heredoc.jsonl")  # Bash heredocs to /scratch/notes.md, no Write
WRITTEN_EDIT = os.path.join(ROOT, "fixtures", "written-edit.jsonl")       # Edit, Write, then two Edits on /scratch/plan.md


def _slurp(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def _sha(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


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

    def test_load_skips_non_dict_top_level_line(self):
        # A JSONL line that decodes to valid JSON but not an object (e.g. `["x"]`)
        # must not crash load(); the valid entry after it is still returned.
        entries = r.load(NONDICT)
        self.assertEqual(len(entries), 1)
        self.assertEqual(r._role(entries[0]), "user")

    def test_second_level_non_dict_message_never_crashes(self):
        # A valid object whose `message` is a string or a list is one level deeper than
        # the case above. Every reader must survive it and the valid entry after it
        # must still be found. `_role` falls back to the top-level `type`.
        entries = r.load(NONDICT_MSG)
        self.assertEqual(len(entries), 3)
        for e in entries:
            self.assertIsInstance(r.searchable_text(e), str)
        self.assertEqual(r._role(entries[0]), "user")
        self.assertEqual(r._role(entries[1]), "assistant")
        self.assertIn("still findable", r.opening_ask(entries))
        self.assertEqual(len(r.search(entries, "still findable")), 1)

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

    def test_redaction_is_bounded_on_keyword_runs(self):
        # SECRET_SHAPE_RE is cubic on repeated PASSWORD/TOKEN runs: 4,095 chars of "TOKEN"
        # cost ~20 s unbounded. The text is cut to a prefix before the regex, so both the
        # first-turn ask and the tail line finish fast and still redact a leading secret.
        # Each case runs in a subprocess with a hard timeout, so the unfixed code goes red
        # in seconds instead of hanging the suite.
        import time
        probe = (
            "import sys, session_recall as r\n"
            "text = 'PASSWORD=hunter2 ' + sys.argv[2] * int(sys.argv[3])\n"
            "if sys.argv[1] == 'ask':\n"
            "    out = r.opening_ask([{'type': 'user', 'message': {'role': 'user', 'content': text}}])\n"
            "else:\n"
            "    out = r._clean_tail_text(text)\n"
            "print(out)\n"
        )
        for word, count in (("TOKEN", 2000), ("PASSWORD", 1000)):
            for mode in ("ask", "tail"):
                t0 = time.monotonic()
                try:
                    p = subprocess.run([sys.executable, "-c", probe, mode, word, str(count)],
                                       cwd=ROOT, capture_output=True, text=True, timeout=5)
                except subprocess.TimeoutExpired:
                    self.fail(f"{mode} on {word}*{count} still running after 5 s")
                elapsed = time.monotonic() - t0
                self.assertEqual(p.returncode, 0, p.stderr)
                self.assertLess(elapsed, 1.0, f"{mode} on {word}*{count} took {elapsed:.2f}s")
                self.assertTrue(p.stdout.startswith("[redacted]"), f"{mode}: {p.stdout[:40]!r}")
                self.assertNotIn("hunter2", p.stdout)

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

    # --- --tail (SPEC-309) --------------------------------------------------------

    def _run_main(self, argv):
        import contextlib
        import io
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = r.main(argv)
        return code, out.getvalue(), err.getvalue()

    def _fake_tail_tree(self):
        import shutil
        import tempfile
        base = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, base)
        main_slug = os.path.join(base, "-Users-me-workspace-x")
        wt_slug = os.path.join(base, "-Users-me-workspace-x--claude-worktrees-y")
        os.makedirs(main_slug)
        os.makedirs(wt_slug)
        wt_file = os.path.join(wt_slug, "abc12345-session.jsonl")
        shutil.copy(SEED, wt_file)
        return base, main_slug, wt_slug, wt_file

    def test_tail_default_and_limit_ascending(self):
        # AC1: 14 kept turns, default prints last 10, --limit 3 prints last 3, ascending
        entries = r.load(TAIL_BASIC)
        kept = r.tail_turns(entries, 10)
        self.assertEqual(len(kept), 10)
        self.assertEqual(kept[0][0], "prompt 3: keep it minimal")
        self.assertEqual(kept[-1][0], "reply 7: two commits, feat then docs")
        kept3 = r.tail_turns(entries, 3)
        self.assertEqual([t[0] for t in kept3], [
            "reply 6: done, one sentence in step 7b",
            "prompt 7: commit it",
            "reply 7: two commits, feat then docs",
        ])

    def test_tail_drops_every_kind_and_renders_slash_command(self):
        # AC2: every dropped kind never prints (isMeta, isCompactSummary, isSidechain,
        # tool_result, interrupt marker, <system-reminder>, a non-user/assistant role,
        # an assistant turn that is only a tool call); a <command-name>-first turn
        # renders /x <args>, and so does a <command-message>-first turn (review
        # finding 1: a real slash-command turn opens with <command-message>, not
        # directly with <command-name>).
        entries = r.load(TAIL_DROPPED)
        kept = r.tail_turns(entries, 50)
        self.assertEqual([t[0] for t in kept], [
            "real prompt: what is the status",
            "/status --verbose",
            "/commit",
            "real reply: still running",
        ])

    def test_tail_text_cleaning_redacts_secret_and_esc_and_caps(self):
        # AC3: a secret shape redacts (including one straddling char 200); ESC prints as ?
        esc = "\x1b"
        fake_token = "ghp_" + "a" * 30  # obviously-fake, built at runtime, never a real shape
        cleaned = r._clean_tail_text(f"before{esc}after token {fake_token} end")
        self.assertIn("[redacted]", cleaned)
        self.assertNotIn(fake_token, cleaned)
        self.assertIn("?", cleaned)

        # redaction runs BEFORE the cap, so a token straddling char 200 is fully
        # redacted first; the cap may then truncate into the "[redacted]" marker
        # itself, but never leaks a byte of the original secret.
        padding = "x" * 190
        straddle_token = "ghp_" + "b" * 40
        cleaned2 = r._clean_tail_text(padding + " " + straddle_token)
        self.assertNotIn(straddle_token, cleaned2)
        self.assertNotIn("ghp_", cleaned2)
        self.assertLessEqual(len(cleaned2), 200)

    def test_tail_extra_secret_shapes_redact(self):
        # AC3 / review finding 7: TAIL_EXTRA_SECRET_RE widens redaction beyond the
        # shared SECRET_SHAPE_RE. Every token below is built at runtime by string
        # concatenation, obviously fake, so no credential-shaped literal sits in
        # this committed file.
        cases = {
            "github_pat": "github_pat_" + "a" * 30,
            "gho": "gh" + "o_" + "b" * 30,
            "ghu": "gh" + "u_" + "b" * 30,
            "sk_live": "sk" + "_live_" + "c" * 20,
            "sk_test": "sk" + "_test_" + "c" * 20,
            "rk_live": "rk" + "_live_" + "c" * 20,
            "jwt": "eyJ" + "d" * 10 + "." + "eyJ" + "e" * 10 + "." + "f" * 10,
            "bearer": "Bearer " + "g" * 20,
            "key_assign_upper": "STRIPE_KEY" + "=" + "h" * 20,
            "key_assign_colon": "api_key" + ": " + "i" * 20,
            "password_colon": "password" + ": " + "j" * 10,
            "password_eq": "password" + "=" + "k" * 10,
        }
        for label, token in cases.items():
            cleaned = r._clean_tail_text(f"before {token} after")
            self.assertIn("[redacted]", cleaned, label)
            self.assertNotIn(token, cleaned, label)

        dashes = "-" * 5
        pem_begin = dashes + "BEGIN" + " RSA PRIVATE KEY" + dashes
        pem_end = dashes + "END" + " RSA PRIVATE KEY" + dashes
        pem_body = pem_begin + "\n" + "m" * 40 + "\n" + "n" * 40 + "\n" + pem_end
        cleaned_pem = r._clean_tail_text(f"key follows {pem_body} done")
        self.assertIn("[redacted]", cleaned_pem)
        self.assertNotIn("m" * 40, cleaned_pem)
        self.assertNotIn(pem_begin, cleaned_pem)

    def test_tail_secret_shape_re_byte_unchanged(self):
        # review finding 7: SECRET_SHAPE_RE itself must stay byte-identical (shared
        # with lib/precedent/inventory.py, pinned by tests/test-precedent.sh); the
        # widening lives in TAIL_EXTRA_SECRET_RE instead.
        self.assertTrue(hasattr(r, "TAIL_EXTRA_SECRET_RE"))
        self.assertIsNot(r.SECRET_SHAPE_RE, r.TAIL_EXTRA_SECRET_RE)

    def test_tail_unicode_control_categories_redact(self):
        # review finding 8: Cf/Co/Cs unicode categories, not just C0/C1, become `?`
        rlo = "\u202e"  # RIGHT-TO-LEFT OVERRIDE, category Cf
        zwsp = "\u200b"  # ZERO WIDTH SPACE, category Cf
        cleaned = r._clean_tail_text(f"before{rlo}mid{zwsp}after")
        self.assertNotIn(rlo, cleaned)
        self.assertNotIn(zwsp, cleaned)
        self.assertIn("?", cleaned)

    def test_tail_c1_control_char_redacts(self):
        # review finding 12: a C1 control char (not just ESC) becomes `?`
        c1 = "\x9b"
        cleaned = r._clean_tail_text(f"before{c1}after")
        self.assertNotIn(c1, cleaned)
        self.assertIn("?", cleaned)

    def test_tail_mode_conflicts_and_limit_validation_exit_2(self):
        # AC4: every mode-conflict and --limit validation case exits 2 with usage
        base, _, _, _ = self._fake_tail_tree()
        orig = r.PROJECTS
        r.PROJECTS = base
        try:
            cases = [
                ["--tail"],                                    # missing value
                ["--tail", "--sessions"],                       # value starts with -
                ["query", "--tail", "abc12345"],                 # query beside --tail
                ["--tail", "abc12345", "--sessions"],            # --sessions beside --tail
                ["--tail", "abc12345", "--json"],                # --json beside --tail
                ["--tail", "abc12345", "--limit", "0"],
                ["--tail", "abc12345", "--limit", "-1"],
                ["--tail", "abc12345", "--limit", "abc"],
                ["something", "--limit", "0"],                   # limit validation, every mode
                ["something", "--limit", "-1"],
                ["something", "--limit", "abc"],
            ]
            for argv in cases:
                code, _, err = self._run_main(argv)
                self.assertEqual(code, 2, f"{argv} -> exit {code}")
                self.assertIn("usage:", err)
        finally:
            r.PROJECTS = orig

    def test_tail_unknown_prefix_exit_1_ambiguous_exit_2(self):
        # AC4: unknown prefix exits 1; ambiguous prefix exits 2 naming every match
        import shutil
        base, main_slug, _, _ = self._fake_tail_tree()
        shutil.copy(SEED, os.path.join(main_slug, "dup-one.jsonl"))
        shutil.copy(SEED, os.path.join(main_slug, "dup-two.jsonl"))
        orig = r.PROJECTS
        r.PROJECTS = base
        try:
            code, _, err = self._run_main(["--tail", "no-such-prefix-zzz"])
            self.assertEqual(code, 1)
            self.assertIn("no transcript matching", err)

            with self.assertRaises(r.TailResolutionError) as cm:
                r.resolve_tail_target("dup")
            self.assertEqual(cm.exception.code, 2)
            self.assertIn("dup-one", cm.exception.message)
            self.assertIn("dup-two", cm.exception.message)
        finally:
            r.PROJECTS = orig

    def test_tail_no_match_default_sweep_message_is_a_count_not_a_list(self):
        # review finding 4: the default all-projects sweep names how many project
        # dirs were searched, never every dir name (that list can run hundreds of
        # lines); --project narrowed still names the dirs it searched.
        base, main_slug, wt_slug, _ = self._fake_tail_tree()
        orig = r.PROJECTS
        r.PROJECTS = base
        try:
            with self.assertRaises(r.TailResolutionError) as cm:
                r.resolve_tail_target("no-such-prefix-zzz")
            self.assertIn("2 project dirs", cm.exception.message)
            self.assertNotIn(os.path.basename(main_slug), cm.exception.message)
            self.assertNotIn(os.path.basename(wt_slug), cm.exception.message)

            with self.assertRaises(r.TailResolutionError) as cm2:
                r.resolve_tail_target("no-such-prefix-zzz", project="x")
            self.assertIn(os.path.basename(main_slug), cm2.exception.message)
        finally:
            r.PROJECTS = orig

    def test_tail_ambiguous_prefix_list_capped_at_ten(self):
        # review finding 4: an ambiguous prefix lists at most 10 ids, then "... and N more"
        import shutil
        base, main_slug, _, _ = self._fake_tail_tree()
        for i in range(13):
            shutil.copy(SEED, os.path.join(main_slug, f"dup-{i:02d}.jsonl"))
        orig = r.PROJECTS
        r.PROJECTS = base
        try:
            with self.assertRaises(r.TailResolutionError) as cm:
                r.resolve_tail_target("dup")
            msg = cm.exception.message
            self.assertEqual(cm.exception.code, 2)
            self.assertEqual(msg.count("dup-"), 10)
            self.assertIn("... and 3 more", msg)
        finally:
            r.PROJECTS = orig

    def test_tail_error_messages_and_header_control_chars_cleaned(self):
        # review finding 5: sid (header) and matched ids / dir names (error messages)
        # go through the same control-char replacement as a kept turn's text.
        import shutil
        base, main_slug, _, _ = self._fake_tail_tree()
        esc = "\x1b"
        bad_name = f"dup{esc}one.jsonl"
        shutil.copy(SEED, os.path.join(main_slug, bad_name))
        shutil.copy(SEED, os.path.join(main_slug, f"dup{esc}two.jsonl"))
        orig = r.PROJECTS
        r.PROJECTS = base
        try:
            with self.assertRaises(r.TailResolutionError) as cm:
                r.resolve_tail_target("dup")
            self.assertNotIn(esc, cm.exception.message)
            self.assertIn("?", cm.exception.message)
        finally:
            r.PROJECTS = orig

        # a --file target whose basename carries a control char: cleaned sid reaches
        # resolve_tail_target's return value and then the tail header
        newline_path = os.path.join(main_slug, f"weird{esc}sid.jsonl")
        shutil.copy(SEED, newline_path)
        _, sid = r.resolve_tail_target("ignored", file=newline_path)
        self.assertNotIn(esc, sid)
        header = r.render_tail(sid, [], 1758000000.0)
        self.assertNotIn(esc, header)

    def test_tail_project_validation_runs_before_tail_branch(self):
        # review finding 10: the --project-without-value guard and the "no project
        # dir" message apply to --tail too, not only the query path.
        base, main_slug, _, wt_file = self._fake_tail_tree()
        orig = r.PROJECTS
        r.PROJECTS = base
        try:
            code, _, err = self._run_main(["--tail", "abc12345", "--project"])
            self.assertEqual(code, 2)
            self.assertIn("usage:", err)

            code, _, err = self._run_main(["--tail", "abc12345", "--project", "no-such-repo-zzz"])
            self.assertEqual(code, 1)
            self.assertIn("no project dir", err)
            self.assertNotIn("no transcript matching", err)
        finally:
            r.PROJECTS = orig

    def test_tail_resolution_default_project_file(self):
        # AC5: default sweeps a worktree-slug dir; --project narrows past it; --file bypasses
        base, main_slug, wt_slug, wt_file = self._fake_tail_tree()
        orig = r.PROJECTS
        r.PROJECTS = base
        try:
            path, sid = r.resolve_tail_target("abc12345")
            self.assertEqual(path, wt_file)
            self.assertEqual(sid, "abc12345-session")

            with self.assertRaises(r.TailResolutionError) as cm:
                r.resolve_tail_target("abc12345", project="x")
            self.assertEqual(cm.exception.code, 1)

            path2, sid2 = r.resolve_tail_target("ignored-prefix", file=wt_file)
            self.assertEqual(path2, wt_file)
            self.assertEqual(sid2, "abc12345-session")
        finally:
            r.PROJECTS = orig

    def test_tail_cli_subprocess_on_fixture_with_limit(self):
        # review finding 2: the CLI, not just the library functions, run end to end:
        # header, DATA marker, exactly 3 turn lines, footer, exit 0.
        p = subprocess.run([sys.executable, BIN, "--tail", "ignored-prefix",
                             "--file", TAIL_BASIC, "--limit", "3"],
                            capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        lines = p.stdout.rstrip("\n").splitlines()
        self.assertTrue(lines[0].startswith("# tail of "))
        self.assertEqual(lines[1], r.DATA_MARKER)
        turn_lines = lines[2:-1]
        self.assertEqual(len(turn_lines), 3)
        self.assertEqual(lines[-1], "# end of tail data")

    def test_read_tail_chunk_matches_full_load_with_small_chunk_size(self):
        # review finding 6: patch _TAIL_CHUNK_BYTES small so the byte-range read
        # path actually runs (tail-basic.jsonl exceeds it). A chunk that still
        # holds >= `limit` kept turns must derive the same last-`limit` turns as
        # a full load; a chunk too small to ever hold `limit` kept turns must
        # fall back to load() and return the identical full entries list.
        full = r.load(TAIL_BASIC)
        orig_chunk = r._TAIL_CHUNK_BYTES
        try:
            r._TAIL_CHUNK_BYTES = 300
            chunk_entries = r.read_tail_chunk(TAIL_BASIC, limit=3)
            self.assertEqual(r.tail_turns(chunk_entries, 3), r.tail_turns(full, 3))

            r._TAIL_CHUNK_BYTES = 50  # too small to ever hold 3 kept turns
            fallback_entries = r.read_tail_chunk(TAIL_BASIC, limit=3)
            self.assertEqual(fallback_entries, full)
        finally:
            r._TAIL_CHUNK_BYTES = orig_chunk

    def test_query_and_sessions_output_byte_identical_to_master(self):
        # AC6: query and --sessions output on fixtures/seed.jsonl unchanged by this branch.
        # This must FAIL, not skip, when origin/master is unavailable: a silent skip lets
        # a real regression through unnoticed (review finding 12).
        import shutil
        import tempfile
        proc = subprocess.run(["git", "show", "origin/master:lib/session/recall/session_recall.py"],
                               cwd=ROOT, capture_output=True, text=True)
        if proc.returncode != 0 or not proc.stdout.strip():
            self.fail("origin/master:lib/session/recall/session_recall.py not available here; "
                      "AC6 cannot be verified (fetch origin/master, do not skip this test)")
        tmp_root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp_root)
        session_dir = os.path.join(tmp_root, "lib", "session")
        recall_dir = os.path.join(session_dir, "recall")
        os.makedirs(recall_dir)
        shutil.copy(os.path.join(ROOT, "..", "parse_transcript.py"), session_dir)
        master_path = os.path.join(recall_dir, "session_recall.py")
        with open(master_path, "w") as fh:
            fh.write(proc.stdout)
        cases = [
            ["backoff", "--file", SEED],
            ["backoff", "--file", SEED, "--json"],
            ["backoff", "--file", SEED, "--sessions"],
            ["backoff", "--file", SEED, "--sessions", "--json"],
        ]
        for args in cases:
            new_out = subprocess.run([sys.executable, BIN] + args, capture_output=True, text=True)
            old_out = subprocess.run([sys.executable, master_path] + args, capture_output=True, text=True)
            self.assertEqual(new_out.stdout, old_out.stdout, f"stdout differs for {args}")
            self.assertEqual(new_out.returncode, old_out.returncode, f"exit code differs for {args}")

    def test_readme_and_wrap_document_tail(self):
        # AC7
        with open(os.path.join(ROOT, "README.md")) as fh:
            readme = fh.read()
        self.assertIn("--tail", readme)
        self.assertIn("confirm", readme.lower())
        kit_root = os.path.dirname(os.path.dirname(os.path.dirname(ROOT)))
        with open(os.path.join(kit_root, "commands", "wrap.md")) as fh:
            wrap_md = fh.read()
        self.assertIn("--tail", wrap_md)

    def test_tail_local_time_and_subagents_mtime(self):
        # AC8: turn times print in local time; last write counts <sid>/subagents/*.jsonl
        import time
        orig_tz = os.environ.get("TZ")
        os.environ["TZ"] = "America/New_York"
        time.tzset()
        try:
            self.assertEqual(r._local_hhmm("2026-06-29T09:00:00.000Z"), "05:00")  # EDT = UTC-4
            self.assertEqual(r._local_hhmm(""), "--:--")
            self.assertEqual(r._local_hhmm("not-a-timestamp"), "--:--")
        finally:
            if orig_tz is None:
                os.environ.pop("TZ", None)
            else:
                os.environ["TZ"] = orig_tz
            time.tzset()

        import shutil
        import tempfile
        base = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, base)
        sid = "subagent-mtime-session"
        main_file = os.path.join(base, sid + ".jsonl")
        shutil.copy(SEED, main_file)
        sub_dir = os.path.join(base, sid, "subagents")
        os.makedirs(sub_dir)
        sub_file = os.path.join(sub_dir, "worker.jsonl")
        shutil.copy(SEED, sub_file)
        now = time.time()
        os.utime(main_file, (now - 3600, now - 3600))
        os.utime(sub_file, (now, now))
        self.assertAlmostEqual(r._last_write_mtime(main_file, sid), now, delta=2)

    def test_tail_empty_state_and_full_render_shape(self):
        # Edge case: no kept turns -> header, "(no prompts or replies yet)", footer
        empty = r.render_tail("no-turns-sid", [], 1758000000.0)
        self.assertIn("# tail of no-turns-sid:", empty)
        self.assertIn(r.DATA_MARKER, empty)
        self.assertIn("(no prompts or replies yet)", empty)
        self.assertTrue(empty.endswith("# end of tail data"))

        import time
        orig_tz = os.environ.get("TZ")
        os.environ["TZ"] = "UTC"
        time.tzset()
        try:
            entries = r.load(TAIL_BASIC)
            kept = r.tail_turns(entries, 10)
            rendered = r.render_tail("real-sid", kept, os.path.getmtime(TAIL_BASIC))
        finally:
            if orig_tz is None:
                os.environ.pop("TZ", None)
            else:
                os.environ["TZ"] = orig_tz
            time.tzset()
        self.assertIn("10:00  asst  reply 7: two commits, feat then docs", rendered)

    # --- --final: the last assistant reply, or one fenced block of it ---------------
    # Motivating miss: a background subagent returns its report as one fenced block in
    # its final reply, and the lead hand-rolled jq over the output JSONL to save it.

    def _final(self, path, *extra):
        return subprocess.run([sys.executable, BIN, "--final", path, *extra],
                              capture_output=True, text=True)

    def test_final_picks_last_text_message_and_skips_trailing_no_text_turns(self):
        # The file ends with a thinking-only turn and a tool_use-only turn; the answer
        # is the last assistant entry that has text, with its text items joined by newline.
        text = r.final_reply_text(r.load(FINAL_BACKTICK))
        self.assertTrue(text.startswith("Final report follows.\n```markdown\n# Not this one"))
        self.assertNotIn("early draft", text)
        res = self._final(FINAL_BACKTICK)
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout, text + "\n")

    def test_final_fence_backtick_takes_last_block_and_keeps_inner_fence(self):
        # Two ```markdown blocks in the reply: the LAST wins. Its inner ```bash block
        # (same fence length, has an info string) is content, not the closer.
        res = self._final(FINAL_BACKTICK, "--fence", "markdown")
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout, "# Report\n\nIntro line.\n\n```bash\nls -la\n```\n\nDone section.\n")
        self.assertNotIn("Not this one", res.stdout)

    def test_final_fence_other_tag_selects_that_block(self):
        res = self._final(FINAL_BACKTICK, "--fence", "text")
        self.assertEqual(res.stdout, "after\n")

    def test_final_fence_tilde_keeps_shorter_and_other_char_fences(self):
        res = self._final(FINAL_TILDE, "--fence", "markdown")
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout,
                         "# Doc\n\n```\nplain inner\n```\n\n~~~\nshort tilde\n~~~\n\nTail.\n")

    def test_final_fence_not_found_exits_1(self):
        res = self._final(FINAL_BACKTICK, "--fence", "yaml")
        self.assertEqual(res.returncode, 1)
        self.assertEqual(res.stdout, "")
        self.assertEqual(len(res.stderr.strip().splitlines()), 1)
        self.assertIn("yaml", res.stderr)
        # a block that never closes is not a block
        self.assertIsNone(r.last_fenced_block("```markdown\nno closer", "markdown"))

    def test_final_no_assistant_text_exits_1(self):
        res = self._final(FINAL_NO_TEXT)
        self.assertEqual(res.returncode, 1)
        self.assertEqual(res.stdout, "")
        self.assertEqual(len(res.stderr.strip().splitlines()), 1)

    def test_final_missing_file_exits_1_and_bad_combos_exit_2(self):
        self.assertEqual(self._final(os.path.join(ROOT, "no-such.jsonl")).returncode, 1)
        for extra in (["--sessions"], ["--tail", "abc"], ["backoff"]):
            self.assertEqual(self._final(SEED, *extra).returncode, 2, extra)
        bare_fence = subprocess.run([sys.executable, BIN, "--fence", "markdown"],
                                    capture_output=True, text=True)
        self.assertEqual(bare_fence.returncode, 2)

    def test_final_output_is_verbatim_not_redacted(self):
        # The report is saved to a file by the caller, so --final never rewrites it
        # (--tail redacts because its output is pasted into a session).
        secret = "see op://vault/item/field for the key"
        self.assertEqual(r.last_fenced_block("```markdown\n" + secret + "\n```", "markdown"), secret)


    # --- --final --json / --out / --max-bytes: a task-output file's result ---------
    # A background subagent's result lands in <session>/tasks/<agent-id>.output (the same
    # JSONL). Reading it whole overflows the lead's context; these pull out just the answer.

    def test_result_plain_prints_last_assistant_text_only(self):
        res = self._final(RESULT_JSON)
        self.assertEqual(res.returncode, 0)
        self.assertTrue(res.stdout.startswith("Audit finished. Result:\n{"))
        self.assertTrue(res.stdout.endswith("End of report.\n"))
        self.assertNotIn("Early draft", res.stdout)

    def test_result_json_prints_outermost_object(self):
        res = self._final(RESULT_JSON, "--json")
        self.assertEqual(res.returncode, 0, res.stderr)
        obj = json.loads(res.stdout)
        self.assertEqual(obj["verdict"], "pass")
        self.assertEqual(obj["count"], 3)
        self.assertEqual(obj["findings"][0]["note"], "a {brace} in a string")

    def test_result_out_writes_file_and_prints_one_line_summary(self):
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "result.json")
            res = self._final(RESULT_JSON, "--json", "--out", out)
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertEqual(len(res.stdout.strip().splitlines()), 1)
            self.assertIn("top-level keys: verdict, count, findings", res.stdout)
            self.assertNotIn("Audit finished", res.stdout)
            body = _slurp(out)
            self.assertEqual(json.loads(body)["count"], 3)
            self.assertIn(f"wrote {len(body.encode('utf-8'))} bytes to {out}", res.stdout)
            # plain --out writes the prose, with no key list
            out2 = os.path.join(d, "result.txt")
            res2 = self._final(RESULT_JSON, "--out", out2)
            self.assertNotIn("top-level keys", res2.stdout)
            self.assertTrue(_slurp(out2).startswith("Audit finished."))

    def test_result_no_assistant_message_is_clear_error_exit_1(self):
        for flags in ([], ["--json"]):
            res = self._final(FINAL_NO_TEXT, *flags)
            self.assertEqual(res.returncode, 1, flags)
            self.assertEqual(res.stdout, "")
            self.assertIn("no assistant text", res.stderr)

    def test_result_malformed_json_is_clear_error_exit_1(self):
        res = self._final(RESULT_BAD_JSON, "--json")
        self.assertEqual(res.returncode, 1)
        self.assertEqual(res.stdout, "")
        self.assertEqual(len(res.stderr.strip().splitlines()), 1)
        self.assertIn("not valid JSON", res.stderr)
        # prose with no object, and braces that are not JSON
        with self.assertRaises(ValueError):
            r.outermost_json_object("just prose, no object")
        with self.assertRaises(ValueError):
            r.outermost_json_object("see {not json} here")

    def test_result_stdout_is_byte_capped_and_out_is_not(self):
        res = self._final(RESULT_JSON, "--max-bytes", "20")
        self.assertEqual(res.returncode, 0)
        self.assertEqual(len(res.stdout.encode("utf-8")), 20)
        self.assertIn("truncated", res.stderr)
        # a cut never splits a multibyte character
        self.assertEqual(r.cap_bytes("a\u00e9b", 2), "a")
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "full.txt")
            self._final(RESULT_JSON, "--max-bytes", "20", "--out", out)
            self.assertTrue(_slurp(out).endswith("End of report.\n"))

    def test_result_flag_misuse_exits_2_and_never_clobbers_the_transcript(self):
        for extra in (["--max-bytes", "0"], ["--max-bytes", "x"], ["--out"], ["--out", "-x"]):
            self.assertEqual(self._final(RESULT_JSON, *extra).returncode, 2, extra)
        for bare in (["--out", "x.txt"], ["--max-bytes", "5"]):
            p = subprocess.run([sys.executable, BIN, "backoff", "--file", SEED, *bare],
                               capture_output=True, text=True)
            self.assertEqual(p.returncode, 2, bare)
        before = _sha(RESULT_JSON)
        res = self._final(RESULT_JSON, "--out", RESULT_JSON)
        self.assertEqual(res.returncode, 2)
        self.assertEqual(_sha(RESULT_JSON), before)


    # --- --written: the last content a session wrote to one path -----------------

    def _written(self, path, *extra):
        return subprocess.run([sys.executable, BIN, "--written", path, *extra],
                              capture_output=True, text=True)

    def test_written_last_write_wins_and_is_verbatim(self):
        res = self._written("/scratch/plan.md", "--file", WRITTEN_WRITE)
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout, "# plan v2\n- second cut, no trailing newline")
        self.assertEqual(res.stderr, "")
        # a different path in the same transcript reads its own content
        self.assertEqual(self._written("/scratch/other.md", "--file", WRITTEN_WRITE).stdout, "unrelated\n")

    def test_written_heredoc_fallback_takes_last_and_keeps_body_verbatim(self):
        res = self._written("/scratch/notes.md", "--file", WRITTEN_HEREDOC)
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout, "notes v2\n  indented line\n\nafter blank\n")
        # the first heredoc alone (other path) and the echo after it never leak in
        self.assertEqual(self._written("/scratch/other.md", "--file", WRITTEN_HEREDOC).stdout, "not this one\n")

    def test_written_heredoc_forms(self):
        body = lambda cmd: r.heredoc_body(cmd, "/t/x")
        self.assertEqual(body("cat > /t/x <<'A'\nl1\nA\n"), "l1\n")
        self.assertEqual(body('cat >| "/t/x" <<"A"\nl1\nA\n'), "l1\n")
        self.assertEqual(body("cat > /t/x <<-A\n\tl1\n\tA\n"), "\tl1\n")
        self.assertEqual(body("cat > /t/x <<'A'\nl1\n"), None)          # never closed
        self.assertEqual(body("cat >> /t/x <<'A'\nl1\nA\n"), None)     # append is not a write of the whole file
        self.assertEqual(body("cat > /t/xy <<'A'\nl1\nA\n"), None)     # exact path only

    def test_written_write_beats_a_later_heredoc(self):
        entries = [
            {"type": "assistant", "message": {"role": "assistant", "content": [
                {"type": "tool_use", "name": "Write", "input": {"file_path": "/t/x", "content": "from write\n"}}]}},
            {"type": "assistant", "message": {"role": "assistant", "content": [
                {"type": "tool_use", "name": "Bash", "input": {"command": "cat > /t/x <<'E'\nfrom heredoc\nE\n"}}]}},
        ]
        self.assertEqual(r.written_content(iter(entries), "/t/x")[:2], ("Write", "from write\n"))

    def test_written_later_edits_are_noted_on_stderr_not_applied(self):
        res = self._written("/scratch/plan.md", "--file", WRITTEN_EDIT)
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout, "# plan base\n")
        self.assertEqual(res.stderr, "NOTE: 2 later Edit call(s) on this path are not applied\n")
        # no Edit after the write: no NOTE
        self.assertEqual(self._written("/scratch/plan.md", "--file", WRITTEN_WRITE).stderr, "")

    def test_written_no_match_exits_1_with_one_stderr_line(self):
        res = self._written("/scratch/never.md", "--file", WRITTEN_WRITE)
        self.assertEqual(res.returncode, 1)
        self.assertEqual(res.stdout, "")
        self.assertEqual(len(res.stderr.strip().splitlines()), 1)
        self.assertIn("/scratch/never.md", res.stderr)
        self.assertEqual(self._written("/scratch/plan.md", "--file", os.path.join(ROOT, "no-such.jsonl")).returncode, 1)

    def test_written_combinations_and_missing_source_exit_2(self):
        for extra in (["--file", WRITTEN_WRITE, "somequery"], ["--file", WRITTEN_WRITE, "--sessions"],
                      ["--file", WRITTEN_WRITE, "--tail", "abc"], ["--file", WRITTEN_WRITE, "--final", WRITTEN_WRITE],
                      ["--file", WRITTEN_WRITE, "--json"], ["--file", WRITTEN_WRITE, "--fence", "md"],
                      ["--file", WRITTEN_WRITE, "--max-bytes", "5"], ["--file", WRITTEN_WRITE, "--session", "abc"],
                      [], ["--file", ""], ["--session", "-x"], ["--file", WRITTEN_WRITE, "--out", "-x"]):
            self.assertEqual(self._written("/scratch/plan.md", *extra).returncode, 2, extra)
        self.assertEqual(self._written("").returncode, 2)
        self.assertEqual(self._written("-x", "--file", WRITTEN_WRITE).returncode, 2)
        # --session is only for --written
        p = subprocess.run([sys.executable, BIN, "--session", "abc"], capture_output=True, text=True)
        self.assertEqual(p.returncode, 2)

    def test_written_out_writes_exact_bytes_and_never_clobbers_the_transcript(self):
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "plan.md")
            res = self._written("/scratch/plan.md", "--file", WRITTEN_WRITE, "--out", out)
            self.assertEqual(res.returncode, 0)
            self.assertEqual(_slurp(out), "# plan v2\n- second cut, no trailing newline")
            self.assertEqual(res.stdout, f"wrote {len(_slurp(out).encode())} bytes to {out}\n")
        before = _sha(WRITTEN_WRITE)
        res = self._written("/scratch/plan.md", "--file", WRITTEN_WRITE, "--out", WRITTEN_WRITE)
        self.assertEqual(res.returncode, 2)
        self.assertEqual(_sha(WRITTEN_WRITE), before)

    def test_written_session_prefix_resolves_like_tail(self):
        with tempfile.TemporaryDirectory() as home:
            proj = os.path.join(home, "-proj")
            os.makedirs(proj)
            for name in ("abc111", "abc222", "def333"):
                with open(WRITTEN_WRITE, "rb") as src, open(os.path.join(proj, name + ".jsonl"), "wb") as dst:
                    dst.write(src.read())
            code = ("import sys; sys.path.insert(0, %r); import session_recall as r; r.PROJECTS = %r; "
                    "raise SystemExit(r.main(sys.argv[1:]))" % (ROOT, home))
            run = lambda *a: subprocess.run([sys.executable, "-c", code, "--written", "/scratch/plan.md", *a],
                                            capture_output=True, text=True)
            ok = run("--session", "def")
            self.assertEqual((ok.returncode, ok.stdout), (0, "# plan v2\n- second cut, no trailing newline"))
            amb = run("--session", "abc")
            self.assertEqual(amb.returncode, 2)
            self.assertIn("ambiguous", amb.stderr)
            self.assertEqual(run("--session", "zzz").returncode, 1)


    def test_determinism(self):
        a = subprocess.run([sys.executable, BIN, "backoff", "--file", SEED],
                           capture_output=True, text=True).stdout
        b = subprocess.run([sys.executable, BIN, "backoff", "--file", SEED],
                           capture_output=True, text=True).stdout
        self.assertEqual(a, b)


if __name__ == "__main__":
    unittest.main()
