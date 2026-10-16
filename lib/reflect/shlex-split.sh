#!/bin/bash
# shlex-split.sh -- sourced helper: split a command line the way Python's shlex.split does
# (POSIX mode, no comments), for the hooks whose extractor or source command is a string.
# shlex_split <string> fills the array SHLEX_ARGV and returns 0; it returns 1 on an
# unterminated quote or a trailing backslash (shlex raises ValueError there), leaving the
# array empty. No eval, no globbing, no expansion: the string is data.
shlex_split() {
  local s="$1" i=0 n ch tok="" in_tok=0 q=""
  SHLEX_ARGV=()
  n=${#s}
  while [ "$i" -lt "$n" ]; do
    ch="${s:$i:1}"; i=$((i + 1))
    if [ -z "$q" ]; then
      case "$ch" in
        ' '|$'\t'|$'\r'|$'\n')
          if [ "$in_tok" = 1 ]; then SHLEX_ARGV[${#SHLEX_ARGV[@]}]="$tok"; tok=""; in_tok=0; fi ;;
        "'") q="'"; in_tok=1 ;;
        '"') q='"'; in_tok=1 ;;
        '\')
          [ "$i" -lt "$n" ] || { SHLEX_ARGV=(); return 1; }
          tok="$tok${s:$i:1}"; i=$((i + 1)); in_tok=1 ;;
        *) tok="$tok$ch"; in_tok=1 ;;
      esac
    elif [ "$q" = "'" ]; then
      if [ "$ch" = "'" ]; then q=""; else tok="$tok$ch"; fi
    else
      if [ "$ch" = '"' ]; then q=""
      elif [ "$ch" = '\' ]; then
        [ "$i" -lt "$n" ] || { SHLEX_ARGV=(); return 1; }
        case "${s:$i:1}" in
          '"'|'\') tok="$tok${s:$i:1}"; i=$((i + 1)) ;;
          *) tok="$tok\\" ;;
        esac
      else tok="$tok$ch"; fi
    fi
  done
  [ -z "$q" ] || { SHLEX_ARGV=(); return 1; }
  if [ "$in_tok" = 1 ]; then SHLEX_ARGV[${#SHLEX_ARGV[@]}]="$tok"; fi
  return 0
}
