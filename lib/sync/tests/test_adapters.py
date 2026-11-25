"""The adapter loader (lib/sync/adapters.py): the manifest grammar, lazy import, the directory rules, the
hooks and constants. The bash twin is checked against it by lib/adapters/tests/test-adapters.sh."""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import adapters  # noqa: E402

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "adapters"
STUB_PY = "from __future__ import annotations\n\n\ndef build(app, opts, ctx):\n    return SENTINEL\n"


@pytest.fixture(autouse=True)
def clean_process(monkeypatch):
    """Adapter modules, their siblings and sys.path edits never leak from one test into the next."""
    before_path, before_mods = list(sys.path), set(sys.modules)
    monkeypatch.delenv("KIT_ADAPTERS_DIR", raising=False)
    yield
    sys.path[:] = before_path
    for name in set(sys.modules) - before_mods:
        if name.startswith("kit_adapter_") or name.startswith("zz_"):
            del sys.modules[name]


def make(root: Path, name: str, manifest: str, py: str = STUB_PY, extra: dict | None = None) -> Path:
    d = root / name
    d.mkdir(parents=True, exist_ok=True)
    (d / "adapter.tsv").write_text(manifest)
    if py is not None:
        (d / "adapter.py").write_text(py)
    for fname, text in (extra or {}).items():
        (d / fname).write_text(text)
    return d


def use(monkeypatch, root: Path) -> None:
    monkeypatch.setenv("KIT_ADAPTERS_DIR", str(root))


def test_fixture_adapter_parses_every_row_kind(monkeypatch):
    use(monkeypatch, FIXTURE)
    reg = adapters.load()
    assert reg.apps == {"fake-two": ("fake", "two-way"), "fake-create": ("fake", "create-only"),
                        "fake-pull": ("fake", "pull-only")}
    assert reg.create_only_apps() == {"fake-create"} and reg.pull_only_apps() == {"fake-pull"}
    assert reg.mode("fake-pull") == "pull-only"
    assert [(o.flag, o.key, o.scope) for o in reg.opts] == [("fake-name", "fake_name", "-"),
                                                            ("fake-url", "fake_url", "root")]
    assert reg.const("mirror-label", "x") == "Fixture"
    assert reg.const("inbox-heading", "x") == "### Fixture inbox"
    assert reg.const("nosuch", "dflt") == "dflt"
    assert reg.rows("secret") == [(str(FIXTURE / "fake"), ["FAKE_TOKEN", "fake_token_ref"])]
    assert reg.verb("fakeverb") == (str(FIXTURE / "fake" / "run.sh"), ["first-arg"])
    assert reg.verb("next") is None and reg.verb("nosuch") is None


def test_help_text_doubles_percent_and_keeps_spaces(tmp_path, monkeypatch):
    make(tmp_path, "a", "opt\tflag-a\tkey_a\t-\t100% of a field with spaces\n", py=None)
    use(monkeypatch, tmp_path)
    assert adapters.load().opts[0].help == "100%% of a field with spaces"


def test_a_help_of_dash_means_the_flag_has_no_help_text(tmp_path, monkeypatch):
    make(tmp_path, "a", "opt\tflag-a\tkey_a\t-\t-\nopt\tflag-b\tkey_b\t-\t- not alone\n", py=None)
    use(monkeypatch, tmp_path)
    opts = adapters.load().opts
    assert opts[0].help is None and opts[1].help == "- not alone"


def test_unknown_kind_warns_and_the_rest_loads(tmp_path, monkeypatch):
    make(tmp_path, "a", "mystery\tx\napp\tx\ttwo-way\n")
    use(monkeypatch, tmp_path)
    seen = []
    reg = adapters.load(warn=seen.append)
    assert list(reg.apps) == ["x"]
    assert seen == ["adapters: %s:1: unknown row kind 'mystery' (ignored)" % (tmp_path / "a" / "adapter.tsv")]


@pytest.mark.parametrize("manifest,message", [
    ("opt\tflag-a\tkey_a\tmaybe\thelp\n", "bad scope 'maybe' (want - or root)"),
    ("secret\tlower\tkey_a\n", "bad ENV name 'lower'"),
    ("secret\tKIT_TOKEN\tkey_a\n", "reserved ENV prefix 'KIT_' in 'KIT_TOKEN'"),
    ("verb\tgo\t../x.sh\n", "bad script path '../x.sh' (relative, inside the adapter directory, no ..)"),
    ("opt\tflag-a\tkey_a\t-\th\nopt\tflag-a\tkey_b\t-\th\n", "duplicate flag 'flag-a' (also in %(file)s:1)"),
    ("opt\tapps\tfake_apps\t-\th\n", "flag 'apps' is a core engine flag"),
    ("sweep-opt\tposter\tFAKE_P\th\n", "flag 'poster' is a core sweep flag"),
    ("verb\tnext\tx.sh\n", "verb 'next' is a core verb"),
    ("secret\tFAKE_T\tfake_ref\nopt\tfake-url\tfake_url\t-\th\n",
     "opt key 'fake_url' has scope - and sits beside a secret row"),
    ("app\tx\n", "app needs 2 fields"),
    ("app\tx\t\n", "empty field"),
    ("app\tx\ttwo-way\n", "adapter.py is missing"),
])
def test_grammar_errors_name_file_and_line(tmp_path, monkeypatch, manifest, message):
    d = make(tmp_path, "a", manifest, py=None)
    use(monkeypatch, tmp_path)
    with pytest.raises(SystemExit) as err:
        adapters.load()
    text = str(err.value.code)
    assert text.startswith("adapters: %s:" % (d / "adapter.tsv"))
    assert (message % {"file": d / "adapter.tsv"}) in text


def test_a_symlinked_script_is_a_load_error(tmp_path, monkeypatch):
    d = make(tmp_path, "a", "verb\tgo\tx.sh\n", py=None)
    (tmp_path / "real.sh").write_text("")
    os.symlink("../real.sh", d / "x.sh")
    use(monkeypatch, tmp_path)
    with pytest.raises(SystemExit, match="script 'x.sh' is a symlink"):
        adapters.load()


def test_the_same_app_in_two_adapters_names_both_files(tmp_path, monkeypatch):
    make(tmp_path, "a", "app\tx\ttwo-way\n")
    b = make(tmp_path, "b", "app\tx\ttwo-way\n")
    use(monkeypatch, tmp_path)
    with pytest.raises(SystemExit) as err:
        adapters.load()
    assert "%s:1: duplicate app 'x' (also in %s:1)" % (b / "adapter.tsv", tmp_path / "a" / "adapter.tsv") in str(err.value.code)


def test_a_missing_directory_means_zero_adapters(tmp_path, monkeypatch):
    use(monkeypatch, tmp_path / "nowhere")
    reg = adapters.load()
    assert reg.apps == {} and reg.adapters == []
    with pytest.raises(SystemExit) as err:
        reg.build("x", {}, SimpleNamespace())
    assert str(err.value.code) == "no adapter provides x (searched: %s)" % (tmp_path / "nowhere")


@pytest.mark.parametrize("value", ["", "relative/dir"])
def test_the_directory_variable_must_be_absolute(monkeypatch, value):
    monkeypatch.setenv("KIT_ADAPTERS_DIR", value)
    with pytest.raises(SystemExit) as err:
        adapters.load()
    assert str(err.value.code) == "adapters: KIT_ADAPTERS_DIR must be an absolute path"


def test_the_default_directory_ignores_cwd_and_project_variables(tmp_path):
    decoy = tmp_path / "lib" / "adapters"
    make(decoy, "decoy", "app\tdecoy-app\ttwo-way\n",
         py="from __future__ import annotations\nopen(%r, 'w').write('ran')\n\n\ndef build(app, opts, ctx):\n    return None\n"
            % str(tmp_path / "marker"))
    code = ("import sys; sys.path.insert(0, %r); import adapters; r = adapters.load(); "
            "print(r.dir, sorted(r.apps))" % str(Path(adapters.__file__).parent))
    env = {k: v for k, v in os.environ.items() if k != "KIT_ADAPTERS_DIR"}
    env.update(KIT_PROJECT_ROOT=str(tmp_path), DWARVES_KIT=str(tmp_path))
    out = subprocess.run([sys.executable, "-c", code], cwd=str(tmp_path), env=env, capture_output=True, text=True)
    assert out.returncode == 0, out.stderr
    assert out.stdout.split()[0] == str(Path(adapters.__file__).resolve().parent.parent / "adapters")
    assert "decoy-app" not in out.stdout and not (tmp_path / "marker").exists()


def test_an_adapter_module_is_imported_only_when_named(tmp_path, monkeypatch):
    make(tmp_path, "good", "app\tgood-app\ttwo-way\n", py=STUB_PY.replace("SENTINEL", "'built'"))
    make(tmp_path, "broken", "app\tbroken-app\ttwo-way\n", py="def build(:\n")
    use(monkeypatch, tmp_path)
    reg = adapters.load()
    assert "kit_adapter_good" not in sys.modules and "kit_adapter_broken" not in sys.modules
    assert reg.build("good-app", {}, SimpleNamespace()) == "built"
    assert "kit_adapter_broken" not in sys.modules
    with pytest.raises(SystemExit, match="adapters: broken: import failed: SyntaxError"):
        reg.build("broken-app", {}, SimpleNamespace())
    assert "kit_adapter_broken" not in sys.modules


def test_build_fills_every_opt_key_and_the_hook_view(tmp_path, monkeypatch):
    make(tmp_path, "a", "app\tx\ttwo-way\nopt\tflag-a\tkey_a\t-\th\nopt\tflag-b\tkey_b\troot\th\nhook\tbody_expander\n",
         py="from __future__ import annotations\n\n\ndef build(app, opts, ctx):\n    return (app, opts, ctx.hooks.get('body_expander')('b'))\n\n\n"
            "def body_expander(body):\n    return body + '!'\n")
    use(monkeypatch, tmp_path)
    app, opts, expanded = adapters.load().build("x", {"key_a": "v"}, SimpleNamespace())
    assert (app, opts, expanded) == ("x", {"key_a": "v", "key_b": None}, "b!")


def test_hooks_and_the_first_provider(tmp_path, monkeypatch):
    make(tmp_path, "a", "app\tapp-a\ttwo-way\nhook\tguard\n",
         py="from __future__ import annotations\n\n\ndef build(a, o, c):\n    return None\n\n\ndef guard(n, o):\n    return 'a'\n")
    make(tmp_path, "b", "app\tapp-b\ttwo-way\nhook\tguard\nhook\tbody_expander\n",
         py="from __future__ import annotations\n\n\ndef build(a, o, c):\n    return None\n\n\n"
            "def guard(n, o):\n    return 'b'\n\n\ndef body_expander(x):\n    return x\n")
    use(monkeypatch, tmp_path)
    reg = adapters.load()
    assert [h(None, None) for h in reg.hooks("guard")] == ["a", "b"]
    assert [h(None, None) for h in reg.hooks("guard", only=["app-b"])] == ["b"]
    assert reg.hooks("guard", only=["nothing"]) == []
    assert reg.hook("body_expander")("z") == "z"
    assert reg.hook("brief_decisions") is None


def test_a_declared_hook_that_cannot_load_is_a_failure(tmp_path, monkeypatch):
    make(tmp_path, "a", "app\tx\ttwo-way\nhook\tbody_expander\n")
    make(tmp_path, "b", "app\ty\ttwo-way\nhook\tguard\n", py="def build(:\n")
    use(monkeypatch, tmp_path)
    reg = adapters.load()
    with pytest.raises(adapters.HookFailure) as err:
        reg.hook("body_expander")
    assert str(err.value.code) == "hook body_expander from a failed: module 'kit_adapter_a' has no attribute 'body_expander'"
    with pytest.raises(adapters.HookFailure) as err:
        reg.hooks("guard")
    assert err.value.adapter == "b" and err.value.hook == "guard"
    assert str(err.value.code).startswith("hook guard from b failed: ")


def test_providers_survive_a_bad_provider(tmp_path, monkeypatch):
    make(tmp_path, "a", "hook\tbrief_decisions\n",
         py="from __future__ import annotations\n\n\ndef brief_decisions(h, c, f):\n    return [((6, 0), 'a')]\n")
    make(tmp_path, "b", "hook\tbrief_decisions\n", py="def brief_decisions(:\n")
    make(tmp_path, "c", "hook\tbrief_decisions\n", py="X = 1\n")
    make(tmp_path, "d", "hook\tbrief_decisions\n", py="raise SystemExit('exits at import')\n")
    make(tmp_path, "e", "const\tmirror-label\tE\n", py=None)
    use(monkeypatch, tmp_path)
    got = adapters.load().providers("brief_decisions")
    assert [g[0] for g in got] == ["a", "b", "c", "d"]
    assert got[3][1] is None and isinstance(got[3][2], SystemExit)
    assert got[0][1](None, None, None) == [((6, 0), "a")] and got[0][2] is None
    assert got[1][1] is None and isinstance(got[1][2], SyntaxError)
    assert got[2][1] is None and isinstance(got[2][2], AttributeError)
    assert adapters.load().providers("guard") == []


def test_constants_come_from_the_first_adapter_in_name_order(tmp_path, monkeypatch):
    make(tmp_path, "b", "const\tmirror-label\tSecond\n", py=None)
    make(tmp_path, "a", "const\tmirror-label\tFirst\n", py=None)
    use(monkeypatch, tmp_path)
    # a constant named by two adapters is a load error, so the first-wins rule only reads across distinct names
    with pytest.raises(SystemExit, match="duplicate const 'mirror-label'"):
        adapters.load()
    make(tmp_path, "b", "const\tinbox-heading\t### B inbox\n", py=None)
    reg = adapters.load()
    assert reg.const("mirror-label", "d") == "First" and reg.const("inbox-heading", "d") == "### B inbox"


def test_a_sibling_module_that_shadows_a_loaded_module_is_refused(tmp_path, monkeypatch):
    mod = SimpleNamespace(__file__=str(tmp_path / "elsewhere" / "zz_helper.py"))
    monkeypatch.setitem(sys.modules, "zz_helper", mod)
    make(tmp_path, "a", "app\tx\ttwo-way\n", extra={"zz_helper.py": "VALUE = 1\n"})
    use(monkeypatch, tmp_path)
    with pytest.raises(SystemExit, match="adapters: a: module name zz_helper already provided by"):
        adapters.load().build("x", {}, SimpleNamespace())


def test_the_loader_skips_tests_and_hidden_directories(tmp_path, monkeypatch):
    make(tmp_path, "real", "app\tx\ttwo-way\n")
    (tmp_path / "tests").mkdir()
    make(tmp_path, ".hidden", "app\ty\ttwo-way\n")
    make(tmp_path, "_private", "app\tz\ttwo-way\n")
    (tmp_path / "README.md").write_text("not an adapter")
    use(monkeypatch, tmp_path)
    assert list(adapters.load().apps) == ["x"]
