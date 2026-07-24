"""Offline self-check for bench.py: no model calls, plain asserts."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import bench  # noqa: E402

SUITE = Path(__file__).resolve().parents[1] / "suites" / "smoke-code"


def test_suite_loads_and_hash_is_stable():
    meta, tasks = bench.load_suite(SUITE)
    assert meta["name"] == "smoke-code"
    assert set(tasks) == set(meta["tasks"])
    h1, h2 = bench.suite_hash(SUITE), bench.suite_hash(SUITE)
    assert h1 == h2 and len(h1) == 12


def test_strip_fences():
    assert bench.strip_fences("def f():\n    pass\n") == "def f():\n    pass\n"
    fenced = "intro\n```python\ndef f():\n    pass\n```\nafter"
    assert bench.strip_fences(fenced) == "def f():\n    pass\n"
    two = "```\nshort\n```\ntext\n```python\nlonger_block = 1\nx = 2\n```"
    assert "longer_block" in bench.strip_fences(two)


def test_parse_check_output():
    assert bench.parse_check_output("FAIL x\nPASSED 11/14\n") == (11, 14)
    assert bench.parse_check_output("garbage") == (0, 0)


def test_checks_pass_on_reference_solutions():
    """The suite's own checks accept a known-good solution (meta-verification:
    a check nothing can pass measures nothing)."""
    refs = {
        "parse-semver": '''
import re
P = re.compile(r"^(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)(?:-([0-9A-Za-z.-]+))?(?:\\+([0-9A-Za-z.-]+))?$")
def parse_semver(v):
    if not isinstance(v, str):
        return None
    m = P.match(v)
    if not m:
        return None
    return {"major": int(m[1]), "minor": int(m[2]), "patch": int(m[3]),
            "prerelease": m[4], "build": m[5]}
''',
        "dedup-urls": '''
from urllib.parse import urlsplit
def _norm(u):
    try:
        s = urlsplit(u)
        if not s.scheme or not s.netloc:
            return u
    except ValueError:
        return u
    host = s.netloc.lower()
    for scheme, port in (("http", ":80"), ("https", ":443")):
        if s.scheme.lower() == scheme and host.endswith(port):
            host = host[: -len(port)]
    path = s.path[:-1] if s.path.endswith("/") else s.path
    return (s.scheme.lower(), host, path, s.query)
def dedup_urls(urls):
    seen, out = set(), []
    for u in urls:
        k = _norm(u)
        if k not in seen:
            seen.add(k)
            out.append(u)
    return out
''',
    }
    for task, code in refs.items():
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "solution.py").write_text(code)
            check = (SUITE / "tasks" / task / "check.py").read_text()
            Path(tmp, "check.py").write_text(check)
            r = subprocess.run([sys.executable, "check.py"], cwd=tmp,
                               capture_output=True, text=True)
            assert r.returncode == 0, f"{task} reference rejected:\n{r.stdout}"


def _row(**kw):
    base = {"ts": "2026-07-25T00:00:00+00:00", "suite": "s", "suite_hash": "abc",
            "task": "t1", "model": "m", "executor": "model", "repeat": 0,
            "kit_version": None, "session_id": None, "pass": True,
            "tests_passed": 5, "tests_total": 5, "duration_s": 10.0,
            "model_duration_s": 8.0, "cost_usd": 0.01, "turns": 1,
            "tokens_in": 100, "tokens_out": 200, "error": None}
    base.update(kw)
    return base


def test_summarize_and_render():
    rows = [_row(), _row(task="t2", **{"pass": False}), _row(model="m2")]
    s = bench.summarize(rows)
    m1 = next(x for x in s if x["model"] == "m")
    assert m1["cells"] == 2 and m1["first_pass_yield"] == 0.5
    html = bench.render_html(rows, s)
    assert "scoreboard" in html and "t2" in html and "m2" in html


def test_diff_detects_regression():
    with tempfile.TemporaryDirectory() as tmp:
        b, c = Path(tmp, "b.jsonl"), Path(tmp, "c.jsonl")
        b.write_text(json.dumps(_row()) + "\n")
        c.write_text(json.dumps(_row(**{"pass": False})) + "\n")
        r = subprocess.run([sys.executable, str(Path(bench.__file__)), "diff",
                            "--baseline", str(b), "--candidate", str(c)],
                           capture_output=True, text=True)
        assert r.returncode == 1 and "REGRESSED" in r.stdout


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in fns:
        fn()
        print(f"ok {fn.__name__}")
    print(f"PASSED {len(fns)}/{len(fns)}")
