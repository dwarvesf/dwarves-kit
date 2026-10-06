"""Load a sibling sweep script (a file with no .py suffix) as a module."""
import importlib.machinery
import importlib.util
from pathlib import Path


def load(name):
    path = str(Path(__file__).resolve().parent / name)
    mod_name = name.replace("-", "_")
    loader = importlib.machinery.SourceFileLoader(mod_name, path)
    spec = importlib.util.spec_from_loader(mod_name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod
