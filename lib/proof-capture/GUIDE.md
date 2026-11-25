# Craft guide: making a capture worth reading

The tool makes a file. This guide is about making the file worth a reviewer's time. It holds only neutral craft, no setup of any one person.

## Storyboard first

Write the frames down before you capture: what is on screen at the start, what changes, what the reviewer must see at the end. One story, under 30 s for a GIF. If the story needs a second idea, make a second capture.

## The frame check

Before a capture is committed or uploaded, open the image and look at it. A byte count proves nothing.

- Is the right content on screen, in the state you meant to show?
- Does any frame leak a path, a hostname, a token, an account name or a person's name? A terminal prompt, a window title and a browser address bar are the usual places.
- For a GIF, look at the first frame, a middle frame and the last frame.

If anything leaks, fix the source (a clean prompt, a neutral URL, a fresh profile) and capture again. Do not blur it and ship it.

## Theme fidelity

Capture the page or terminal in the theme the user will see: the real stylesheet, the real font, the real colors. A tool default (a white page where the product is dark, a stock terminal palette) shows a screen nobody uses, and the reviewer will judge the wrong thing.

## Gotchas

- A browser can write the file and never exit. That is normal here: the tool treats the file as the result and ends the browser's own process group.
- On macOS `/tmp` is a symlink, and the tool refuses a symlink as the output directory it is given (it checks that directory and `<out>`, not the parts above). Pass a real directory, such as one under `$TMPDIR`.
- A locale without UTF-8 turns box-drawing glyphs into raw bytes in a tape. Set `LANG` on the tape's first line (`Env LANG "en_US.UTF-8"`).
- A page that animates or fetches after load needs `--wait MS` (virtual time), or the shot is of the first paint.
- A tape runs its commands as you. Read it first.

## Debugging a page that does not render

Run the browser by hand with the same flags the tool uses, with `--user-data-dir` set to a fresh temp directory and the stderr redirect removed so you can read the browser's own messages:

```
<browser> --headless=new --disable-gpu --no-first-run --disable-sync --disable-extensions --hide-scrollbars --use-mock-keychain --password-store=basic --user-data-dir=<fresh temp dir> --window-size=1280,800 --screenshot=<out.png> <url>
```

If the file appears but the command never returns, that is the browser behavior the tool is built around. If no file appears at all, that browser does not support headless screenshots in this way; name another one in `PROOF_CAPTURE_BROWSER`.
