Output hook-cancelled-fix.gif

Set Shell "bash"
Set FontSize 16
Set Width 1200
Set Height 640
Set Theme "Dracula"
Set TypingSpeed 40ms
Set Padding 20

Type "clear"
Enter
Sleep 500ms

Type "printf '\033[7m ▶ PRE-FIX hooks.py, SessionEnd timeout=5s, extractor takes 6s \033[0m\n'"
Enter
Sleep 1s

Type "./demo-run-prefix.sh"
Enter
Sleep 13s

Sleep 3s

Type "clear"
Enter
Sleep 500ms

Type "printf '\033[7m ▶ FIXED hooks.py, SAME 5s timeout, SAME 6s-slow extractor \033[0m\n'"
Enter
Sleep 1s

Type "./demo-run-fixed.sh"
Enter
Sleep 8s

Sleep 3s
