Write a Python module defining exactly one function:

    parse_semver(version: str) -> dict | None

It parses a semantic version string per semver 2.0.0 and returns a dict with
keys: major (int), minor (int), patch (int), prerelease (str or None),
build (str or None).

Rules:
- "1.2.3" -> {"major": 1, "minor": 2, "patch": 3, "prerelease": None, "build": None}
- "1.2.3-alpha.1" -> prerelease "alpha.1"
- "1.2.3+build.5" -> build "build.5"
- "1.2.3-rc.2+build.9" -> both
- Return None for invalid input: missing parts ("1.2"), leading zeros in a
  numeric field ("01.2.3"), negative numbers, empty string, non-string input,
  a leading "v" ("v1.2.3").

Standard library only.
