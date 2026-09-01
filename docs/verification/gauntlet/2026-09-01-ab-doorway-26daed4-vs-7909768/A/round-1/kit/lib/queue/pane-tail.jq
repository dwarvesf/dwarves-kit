fromjson? // empty |
# Codepoint-filter, not a `\uNNNN` regex character class: jq/Oniguruma's `\uNNNN` escape does
# not parse as a single-codepoint match inside a bracket expression here (verified: it silently
# matches the wrong character set, defeating the strip), so the control-byte cut is done on
# `explode`d codepoints instead -- unambiguous, no escape-syntax landmine. Strips C0 (0x00-0x08,
# 0x0b-0x1f) and C1 (0x7f-0x9f) control bytes; tab (0x09) and newline (0x0a) fall outside both
# ranges and survive.
def viz: explode | map(select(((. >= 0 and . <= 8) or (. >= 11 and . <= 31) or (. >= 127 and . <= 159)) | not)) | implode;
def cap: if (length > 2000) then .[0:2000] + "...[truncated]" else . end;
if .type == "assistant" then
  (.message.content // [])[]?
  | if .type == "text" then (.text // "")
    elif .type == "tool_use" then
      "-> " + (.name // "?") + " " + ((.input // {}) | tostring | .[0:80])
    else empty
    end
elif .type == "user" then
  (.message.content // [])[]?
  | select(.type == "tool_result")
  | "<- result (" + ((.content | tostring | length) | tostring) + " chars)"
else empty
end
| select(type == "string" and length > 0)
| viz
| cap
