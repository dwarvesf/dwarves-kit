Write a Python module defining exactly one function:

    dedup_urls(urls: list[str]) -> list[str]

It removes duplicate URLs while preserving first-seen order. Two URLs are
duplicates when they are equal after normalization:

- scheme and host compared case-insensitively ("HTTP://Example.com" == "http://example.com")
- a single trailing slash on the path is ignored ("http://a.com/x/" == "http://a.com/x")
- the fragment is ignored ("http://a.com/x#top" == "http://a.com/x")
- query strings are significant and compared as-is
- default ports are ignored (":80" for http, ":443" for https)

The returned list contains the ORIGINAL strings (first occurrence wins),
not the normalized forms. Non-URL junk strings that cannot be parsed are
kept, deduplicated by exact string match.

Standard library only.
