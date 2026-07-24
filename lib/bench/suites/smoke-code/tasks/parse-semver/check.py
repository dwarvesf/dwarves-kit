"""Hand-verified seeds (N3): every expected value below was worked by hand
against semver 2.0.0 before any model ever ran the task."""
import sys

sys.path.insert(0, ".")
from solution import parse_semver  # noqa: E402

CASES = [
    ("1.2.3", {"major": 1, "minor": 2, "patch": 3, "prerelease": None, "build": None}),
    ("0.0.0", {"major": 0, "minor": 0, "patch": 0, "prerelease": None, "build": None}),
    ("1.2.3-alpha.1", {"major": 1, "minor": 2, "patch": 3, "prerelease": "alpha.1", "build": None}),
    ("1.2.3+build.5", {"major": 1, "minor": 2, "patch": 3, "prerelease": None, "build": "build.5"}),
    ("1.2.3-rc.2+build.9", {"major": 1, "minor": 2, "patch": 3, "prerelease": "rc.2", "build": "build.9"}),
    ("10.20.30", {"major": 10, "minor": 20, "patch": 30, "prerelease": None, "build": None}),
    ("1.2", None),
    ("1.2.3.4", None),
    ("01.2.3", None),
    ("1.02.3", None),
    ("v1.2.3", None),
    ("", None),
    ("-1.2.3", None),
    (None, None),
]

passed = 0
for arg, want in CASES:
    try:
        got = parse_semver(arg)
    except Exception:
        got = "<raised>"
    if got == want:
        passed += 1
    else:
        print(f"FAIL parse_semver({arg!r}) = {got!r}, want {want!r}")

print(f"PASSED {passed}/{len(CASES)}")
sys.exit(0 if passed == len(CASES) else 1)
