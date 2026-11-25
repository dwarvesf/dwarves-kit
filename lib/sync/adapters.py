"""The adapter loader: finds the connectors under `lib/adapters/<name>/` and hands the engine, the
board dispatcher and the sweep one registry of them.

Core names no app. An adapter is a directory with a manifest `adapter.tsv` (tab separated rows, see
lib/adapters/README.md) and, when it provides an app or a hook, an entry module `adapter.py`. This
file reads manifests only and imports an adapter module when something names that adapter (an app, a
hook provider). A broken adapter module fails the runs that name it and never the rest.

The directory scanned is `$KIT_ADAPTERS_DIR` (an absolute path) or, when it is unset, `lib/adapters/`
of the running kit. Nothing else selects it: no config key, no cwd, no project file.

The bash twin is lib/sync/adapters.sh. Both read the same grammar and fail with the same
`adapters: <file>:<line>: <what is wrong>` line; lib/adapters/tests/test-adapters.sh compares them.
"""
from __future__ import annotations

import importlib.util
import os
import re
import sys
from pathlib import Path
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent          # lib/sync
SH_FILE = HERE / "adapters.sh"

ROW_KINDS = ("app", "opt", "secret", "verb", "sweep-opt", "leg", "const", "hook")
# (fewest, most) fields after the kind; most None means any number
ARITY = {"app": (2, 2), "opt": (4, None), "secret": (2, 2), "verb": (2, None),
         "sweep-opt": (3, None), "leg": (2, 2), "const": (2, None), "hook": (1, 1)}
MODES = ("two-way", "create-only", "pull-only")
PHASES = ("after-sync", "last")
HOOKS = ("guard", "body_expander", "brief_decisions")
SINGULAR_HOOKS = ("body_expander",)
SCOPES = ("-", "root")
URL_LIKE = ("_url", "_host", "_endpoint", "_target")
RESERVED_ENV = ("PATH", "HOME", "IFS", "ENV", "BASH_ENV", "SHELLOPTS", "BASHOPTS", "PS4",
                "PROMPT_COMMAND", "CDPATH")
RESERVED_PREFIX = ("LD_", "DYLD_", "PYTHON", "KIT_", "SWEEP_", "BOARD_", "GIT_", "SSH_", "OP_", "NODE_")

NAME_RE = re.compile(r"^[a-z][a-z0-9-]*$")
KEY_RE = re.compile(r"^[a-z][a-z0-9_]*$")
ENV_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")


def _sh_list(name: str) -> list:
    """A static list that adapters.sh owns (the one copy), read from its text."""
    m = re.search(r'^%s="([^"]*)"$' % re.escape(name), SH_FILE.read_text(), re.M)
    if not m:
        raise SystemExit("adapters: %s not found in %s" % (name, SH_FILE))
    return m.group(1).split()


CORE_VERBS = _sh_list("CORE_VERBS")
CORE_ENGINE_FLAGS = _sh_list("ADAPTERS_ENGINE_FLAGS")
CORE_SWEEP_FLAGS = _sh_list("ADAPTERS_SWEEP_FLAGS")


def _err(file, line, what) -> SystemExit:
    return SystemExit("adapters: %s:%s: %s" % (file, line, what))


class HookFailure(SystemExit):
    """A hook provider that declares a hook and then fails to import, or lacks the function."""

    def __init__(self, adapter: str, hook: str, exc: BaseException):
        self.adapter, self.hook, self.exc = adapter, hook, exc
        super().__init__("hook %s from %s failed: %s" % (hook, adapter, exc))


class Row:
    def __init__(self, kind: str, file: str, line: int, fields: list):
        self.kind, self.file, self.line, self.fields = kind, file, line, fields


class Adapter:
    def __init__(self, name: str, path: Path):
        self.name, self.path = name, path
        self.manifest = path / "adapter.tsv"
        self.rows: list = []

    def of(self, kind: str) -> list:
        return [r for r in self.rows if r.kind == kind]

    def declares_hook(self, name: str) -> bool:
        return any(r.fields[0] == name for r in self.of("hook"))

    @property
    def apps(self) -> list:
        return [r.fields[0] for r in self.of("app")]


def adapters_dir() -> Path:
    """The one directory scanned. The loader file's real location decides the default, never cwd."""
    if "KIT_ADAPTERS_DIR" in os.environ:
        value = os.environ["KIT_ADAPTERS_DIR"]
        if not value.startswith("/"):
            raise SystemExit("adapters: KIT_ADAPTERS_DIR must be an absolute path")
        return Path(value)
    return HERE.parent / "adapters"


def _valid_script(file, line, script: str) -> None:
    parts = script.split("/")
    if script.startswith("/") or ".." in parts:
        raise _err(file, line, "bad script path '%s' (relative, inside the adapter directory, no ..)" % script)


def _check_symlink(file, line, adapter_dir: Path, script: str) -> None:
    if os.path.islink(str(adapter_dir / script)):
        raise _err(file, line, "script '%s' is a symlink" % script)


def _env_ok(file, line, env: str) -> None:
    if not ENV_RE.match(env):
        raise _err(file, line, "bad ENV name '%s'" % env)
    if env in RESERVED_ENV:
        raise _err(file, line, "reserved ENV name '%s'" % env)
    for prefix in RESERVED_PREFIX:
        if env.startswith(prefix):
            raise _err(file, line, "reserved ENV prefix '%s' in '%s'" % (prefix, env))


def _parse(adapter: Adapter, seen: dict, warn) -> None:
    """Read one manifest into adapter.rows, validating every known row. `seen` holds what earlier
    rows, in this and earlier adapters, declared, so a duplicate names its first home."""
    file = str(adapter.manifest)
    if not NAME_RE.match(adapter.name):
        raise _err(file, 1, "bad adapter directory name '%s'" % adapter.name)

    def claim(ns: str, key: str, line: int) -> None:
        first = seen.get((ns, key))
        if first is not None:
            raise _err(file, line, "duplicate %s '%s' (also in %s)" % (ns, key, first))
        seen[(ns, key)] = "%s:%d" % (file, line)

    lines = adapter.manifest.read_text(encoding="utf-8").split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    first_entry_row = None
    for n, raw in enumerate(lines, 1):
        raw = raw[:-1] if raw.endswith("\r") else raw
        if raw.strip(" \t") == "" or raw.startswith("#"):
            continue
        f = raw.split("\t")
        kind, rest = f[0], f[1:]
        if kind not in ROW_KINDS:
            warn("adapters: %s:%d: unknown row kind '%s' (ignored)" % (file, n, kind))
            continue
        lo, hi = ARITY[kind]
        if len(rest) < lo or (hi is not None and len(rest) > hi):
            raise _err(file, n, "%s needs %s%d fields" % (kind, "" if lo == hi else "at least ", lo))
        if any(x == "" for x in rest):
            raise _err(file, n, "empty field")
        if kind == "app":
            app, mode = rest
            if not NAME_RE.match(app):
                raise _err(file, n, "bad app name '%s'" % app)
            if mode not in MODES:
                raise _err(file, n, "bad mode '%s' (want two-way, create-only or pull-only)" % mode)
            claim("app", app, n)
        elif kind == "opt":
            flag, key, scope = rest[0], rest[1], rest[2]
            if not NAME_RE.match(flag):
                raise _err(file, n, "bad flag '%s'" % flag)
            if not KEY_RE.match(key):
                raise _err(file, n, "bad key '%s'" % key)
            if scope not in SCOPES:
                raise _err(file, n, "bad scope '%s' (want - or root)" % scope)
            if flag in CORE_ENGINE_FLAGS:
                raise _err(file, n, "flag '%s' is a core engine flag" % flag)
            if key in [c.replace("-", "_") for c in CORE_ENGINE_FLAGS]:
                raise _err(file, n, "key '%s' is a core engine dest" % key)
            claim("flag", flag, n)
            claim("key", key, n)
        elif kind == "secret":
            env, key = rest
            _env_ok(file, n, env)
            if not KEY_RE.match(key):
                raise _err(file, n, "bad key '%s'" % key)
            claim("ENV", env, n)
            claim("key", key, n)
        elif kind == "verb":
            verb, script = rest[0], rest[1]
            if not NAME_RE.match(verb):
                raise _err(file, n, "bad verb '%s'" % verb)
            _valid_script(file, n, script)
            _check_symlink(file, n, adapter.path, script)
            if verb in CORE_VERBS:
                raise _err(file, n, "verb '%s' is a core verb" % verb)
            claim("verb", verb, n)
        elif kind == "sweep-opt":
            flag, env = rest[0], rest[1]
            if not NAME_RE.match(flag):
                raise _err(file, n, "bad flag '%s'" % flag)
            _env_ok(file, n, env)
            if flag in CORE_SWEEP_FLAGS:
                raise _err(file, n, "flag '%s' is a core sweep flag" % flag)
            claim("sweep flag", flag, n)
            claim("ENV", env, n)
        elif kind == "leg":
            phase, script = rest
            if phase not in PHASES:
                raise _err(file, n, "bad phase '%s' (want after-sync or last)" % phase)
            _valid_script(file, n, script)
            _check_symlink(file, n, adapter.path, script)
        elif kind == "const":
            if not NAME_RE.match(rest[0]):
                raise _err(file, n, "bad const name '%s'" % rest[0])
            claim("const", rest[0], n)
        elif kind == "hook":
            if rest[0] not in HOOKS:
                raise _err(file, n, "bad hook name '%s' (want guard, body_expander or brief_decisions)" % rest[0])
            if rest[0] in SINGULAR_HOOKS:
                claim("hook", rest[0], n)
        if kind in ("app", "hook") and first_entry_row is None:
            first_entry_row = n
        adapter.rows.append(Row(kind, file, n, rest))
    opts = adapter.of("opt")
    if adapter.of("secret"):
        for r in opts:
            if r.fields[2] == "-" and r.fields[1].endswith(URL_LIKE):
                raise _err(file, r.line, "opt key '%s' has scope - and sits beside a secret row "
                           "(a project file could aim the secret at a host); use scope root" % r.fields[1])
    if first_entry_row is not None:
        entry = adapter.path / "adapter.py"
        if os.path.islink(str(entry)):
            raise _err(file, first_entry_row, "adapter.py is a symlink")
        if not entry.is_file():
            raise _err(file, first_entry_row, "adapter.py is missing")


def _stderr_warn(_msg: str) -> None:
    sys.stderr.write(_msg + "\n")


class _HookView:
    """What a source builder sees as ctx.hooks: .get(name) is the first provider's callable or None."""

    def __init__(self, registry: "Registry"):
        self._registry = registry

    def get(self, name: str):
        return self._registry.hook(name)


class Registry:
    def __init__(self, directory: Path, adapters: list):
        self.dir = directory
        self.adapters = adapters
        self._mods: dict = {}
        self.apps = {}
        for a in adapters:
            for r in a.of("app"):
                self.apps[r.fields[0]] = (a.name, r.fields[1])
        # a help text of `-` is the placeholder for a flag that has none
        self.opts = [SimpleNamespace(adapter=a.name, flag=r.fields[0], key=r.fields[1], scope=r.fields[2],
                                     help=(None if r.fields[3:] == ["-"]
                                           else " ".join(r.fields[3:]).replace("%", "%%")))
                     for a in adapters for r in a.of("opt")]

    def mode(self, app: str) -> str:
        return self.apps[app][1]

    def create_only_apps(self) -> set:
        return {a for a, (_n, m) in self.apps.items() if m == "create-only"}

    def pull_only_apps(self) -> set:
        return {a for a, (_n, m) in self.apps.items() if m == "pull-only"}

    def rows(self, kind: str) -> list:
        """(adapter dir, fields) per row of one kind, adapters in name order: what adapters_rows prints."""
        return [(str(a.path), r.fields) for a in self.adapters for r in a.of(kind)]

    def verb(self, name: str):
        """(script path, args) for an adapter verb, or None (also for a core verb)."""
        if name in CORE_VERBS:
            return None
        for a in self.adapters:
            for r in a.of("verb"):
                if r.fields[0] == name:
                    return str(a.path / r.fields[1]), r.fields[2:]
        return None

    def const(self, name: str, default: str) -> str:
        for a in self.adapters:
            for r in a.of("const"):
                if r.fields[0] == name:
                    return " ".join(r.fields[1:])
        return default

    def _adapter(self, name: str) -> Adapter:
        return next(a for a in self.adapters if a.name == name)

    def _import(self, adapter: Adapter):
        mod = self._mods.get(adapter.name)
        if mod is not None:
            return mod
        entry = adapter.path / "adapter.py"
        sync = str(HERE)
        for p in (str(HERE.parent / "config"), str(HERE / "sweep"), sync):
            while p in sys.path:
                sys.path.remove(p)
            sys.path.insert(0, p)
        if str(adapter.path) not in sys.path:
            sys.path.append(str(adapter.path))
        here = adapter.path.resolve()
        for f in sorted(adapter.path.glob("*.py")):
            if f.stem == "adapter":
                continue
            held = sys.modules.get(f.stem)
            origin = getattr(held, "__file__", None)
            if held is not None and origin and not Path(origin).resolve().is_relative_to(here):
                raise SystemExit("adapters: %s: module name %s already provided by %s" % (adapter.name, f.stem, origin))
        modname = "kit_adapter_" + adapter.name
        spec = importlib.util.spec_from_file_location(modname, str(entry))
        mod = importlib.util.module_from_spec(spec)
        sys.modules[modname] = mod
        try:
            spec.loader.exec_module(mod)
        except BaseException:
            sys.modules.pop(modname, None)
            raise
        self._mods[adapter.name] = mod
        return mod

    def build(self, app: str, opts: dict, ctx):
        """The source object for `app`, or None when the adapter skips it this run."""
        if app not in self.apps:
            raise SystemExit("no adapter provides %s (searched: %s)" % (app, self.dir))
        adapter = self._adapter(self.apps[app][0])
        try:
            mod = self._import(adapter)
        except Exception as exc:  # noqa: BLE001
            raise SystemExit("adapters: %s: import failed: %s: %s" % (adapter.name, type(exc).__name__, exc))
        full = {o.key: None for o in self.opts}
        full.update(opts or {})
        if not hasattr(ctx, "hooks"):
            ctx.hooks = _HookView(self)
        return mod.build(app, full, ctx)

    def _hook_fn(self, adapter: Adapter, name: str):
        try:
            return getattr(self._import(adapter), name)
        except Exception as exc:  # noqa: BLE001
            raise HookFailure(adapter.name, name, exc)

    def hooks(self, name: str, only=None) -> list:
        """The named hook from each adapter that declares it, limited to adapters that provide an app
        in `only` when it is given. A provider that cannot supply it raises HookFailure."""
        out = []
        for a in self.adapters:
            if not a.declares_hook(name):
                continue
            if only is not None and not any(app in only for app in a.apps):
                continue
            out.append(self._hook_fn(a, name))
        return out

    def hook(self, name: str):
        """The first provider's callable, or None when no adapter declares the hook at all."""
        for a in self.adapters:
            if a.declares_hook(name):
                return self._hook_fn(a, name)
        return None


def load(warn=_stderr_warn) -> Registry:
    """Read every manifest under the adapter directory. Manifest errors are global by design."""
    directory = adapters_dir()
    if not directory.exists():
        return Registry(directory, [])
    if not os.access(str(directory), os.R_OK | os.X_OK) or not directory.is_dir():
        raise SystemExit("adapters: cannot read %s" % directory)
    try:
        names = sorted(os.listdir(str(directory)))
    except OSError:
        raise SystemExit("adapters: cannot read %s" % directory)
    adapters, seen = [], {}
    for name in names:
        path = directory / name
        if name.startswith((".", "_")) or not path.is_dir() or not (path / "adapter.tsv").is_file():
            continue
        adapter = Adapter(name, path)
        _parse(adapter, seen, warn)
        adapters.append(adapter)
    return Registry(directory, adapters)
