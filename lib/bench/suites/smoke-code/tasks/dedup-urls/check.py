"""Hand-verified seeds (N3): every expected list below was worked by hand
against the normalization rules in task.md before any model ran the task."""
import sys

sys.path.insert(0, ".")
from solution import dedup_urls  # noqa: E402

CASES = [
    # trailing slash
    (["http://a.com/x", "http://a.com/x/"], ["http://a.com/x"]),
    # scheme + host case-insensitive, first occurrence wins
    (["HTTP://Example.com/path", "http://example.com/path"], ["HTTP://Example.com/path"]),
    # fragment ignored
    (["http://a.com/x#top", "http://a.com/x"], ["http://a.com/x#top"]),
    # query significant
    (["http://a.com/x?q=1", "http://a.com/x?q=2"], ["http://a.com/x?q=1", "http://a.com/x?q=2"]),
    # default ports
    (["http://a.com:80/x", "http://a.com/x"], ["http://a.com:80/x"]),
    (["https://a.com:443/x", "https://a.com/x"], ["https://a.com:443/x"]),
    # non-default port is significant
    (["http://a.com:8080/x", "http://a.com/x"], ["http://a.com:8080/x", "http://a.com/x"]),
    # path is case-sensitive
    (["http://a.com/X", "http://a.com/x"], ["http://a.com/X", "http://a.com/x"]),
    # host vs root path
    (["http://a.com", "http://a.com/"], ["http://a.com"]),
    # junk strings dedup by exact match, order preserved
    (["not a url", "not a url", "also junk"], ["not a url", "also junk"]),
    # order preservation across kinds
    (["http://b.com/1", "http://a.com/2", "http://b.com/1/"], ["http://b.com/1", "http://a.com/2"]),
    ([], []),
]

passed = 0
for arg, want in CASES:
    try:
        got = dedup_urls(list(arg))
    except Exception as e:
        got = f"<raised {type(e).__name__}>"
    if got == want:
        passed += 1
    else:
        print(f"FAIL dedup_urls({arg!r}) = {got!r}, want {want!r}")

print(f"PASSED {passed}/{len(CASES)}")
sys.exit(0 if passed == len(CASES) else 1)
