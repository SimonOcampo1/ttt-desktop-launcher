#!/bin/sh
# 2 means unavailable (safe to open a terminal); 1 means an attempted handoff failed.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
exe=$1 config=$2 terminal=$3
shift 3
[ "$#" -gt 0 ] || exit 2
for file do
	[ -f "$file" ] || exit 2
done
[ "$(osascript -l JavaScript "$here/services.js" reuse "$config")" = yes ] || exit 2
prefix=$(printf '%s' "$config" | shasum -a 256 | cut -c 1-8)
temp=${TMPDIR:-$(getconf DARWIN_USER_TEMP_DIR)}
dir=${temp%/}/ttt-$(id -u)
[ -d "$dir" ] && [ ! -L "$dir" ] || exit 2
[ "$(stat -f '%u:%Lp' "$dir")" = "$(id -u):700" ] || exit 2
# Read lines rather than splitting the temp directory or socket path on spaces.
selected=$(find "$dir" -type s -name "$prefix-*.sock" -print | LC_ALL=C sort -r | while IFS= read -r socket; do
	encoded=${socket##*-}; encoded=${encoded%.sock}
	case $encoded in ''|*[!0-9a-z]*) continue ;; esac
	candidate=$(printf '%s\n' "$encoded" | awk '{n=0; for(i=1;i<=length;i++) n=n*36+index("0123456789abcdefghijklmnopqrstuvwxyz",substr($0,i,1))-1; printf "%.0f",n}')
	if [ "$candidate" -le 0 ] || ! kill -0 "$candidate" 2>/dev/null; then continue; fi
	printf '%s' "$candidate"
	break
done)
[ -n "$selected" ] || exit 2
err=$(mktemp)
trap 'rm -f "$err"' EXIT
TTT_CONFIG_DIR=$config "$exe" --welcome "$@" </dev/null >/dev/null 2>"$err" &
client=$!
# Keep the CLI's 30-second RPC bound; also stop a listener-disappearance race
# from leaving a terminal-less editor running indefinitely.
(sleep 32; echo 'ttt: handoff timed out' >>"$err"; kill "$client" 2>/dev/null) &
watchdog=$!
status=0
wait "$client" || status=$?
kill "$watchdog" 2>/dev/null || true
wait "$watchdog" 2>/dev/null || true
if [ "$status" -ne 0 ]; then
	cat "$err" >&2
	exit 1
fi
osascript -l JavaScript "$here/services.js" focus "$selected" "$terminal" >/dev/null 2>&1 || true
