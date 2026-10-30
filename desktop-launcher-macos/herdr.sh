#!/bin/sh
# Failure lets the applet use its original terminal. Never start a server here.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
herdr=$1 command=$2 host=$3
cwd=${4:-$HOME}
if [ ! -d "$cwd" ]; then
	# Finder paths are absolute; avoid command substitution stripping newlines.
	cwd=${cwd%/*}
	[ -n "$cwd" ] || cwd=/
fi
reply=$("$herdr" tab create --focus --cwd "$cwd" --label ttt)
pane=$(osascript -l JavaScript "$here/services.js" herdr-pane "$reply")
"$herdr" pane run "$pane" "$command"
# Activation failure must not launch a second editor after pane run succeeded.
if [ -n "$host" ]; then
	osascript -l JavaScript "$here/services.js" focus 1 "$host" >/dev/null 2>&1 || true
fi
