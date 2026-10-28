#!/bin/sh
# Runs desktop-launcher-linux/launcher.sh against a temporary XDG_DATA_HOME.
set -eu
script=$(cd "$(dirname "$0")/.." && pwd)/desktop-launcher-linux/launcher.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export XDG_DATA_HOME="$tmp/data"
entry=$XDG_DATA_HOME/applications/ttt.desktop
icon=$XDG_DATA_HOME/icons/hicolor/scalable/apps/ttt.svg
mkdir -p "$tmp/bin"
printf '#!/bin/sh\n' >"$tmp/bin/kitty"
chmod +x "$tmp/bin/kitty"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}
run() { env -u KITTY_WINDOW_ID -u WEZTERM_PANE -u ALACRITTY_WINDOW_ID -u GHOSTTY_RESOURCES_DIR -u KONSOLE_VERSION TERM=xterm PATH="$tmp/bin:/usr/bin:/bin" "$@"; }

run sh "$script" install "/opt/my apps/ttt"
grep -qx 'Exec="/opt/my apps/ttt" --welcome %F' "$entry" || fail "no-terminal Exec: $(grep Exec "$entry")"
grep -qx 'Terminal=true' "$entry" || fail "expected Terminal=true"
[ -f "$icon" ] || fail "icon not written"

run env KITTY_WINDOW_ID=1 sh "$script" install /usr/bin/ttt
grep -q '/opt/my apps/ttt' "$entry" || fail "install rewrote an existing launcher"

run env KITTY_WINDOW_ID=1 sh "$script" repair /usr/bin/ttt
grep -qx "Exec=$tmp/bin/kitty --class ttt -e /usr/bin/ttt --welcome %F" "$entry" || fail "kitty Exec: $(grep Exec "$entry")"
grep -qx 'StartupWMClass=ttt' "$entry" || fail "expected StartupWMClass"

run sh "$script" install '/odd/50%$x/ttt'
run sh "$script" repair '/odd/50%$x/ttt'
grep -qxF 'Exec="/odd/50%%\$x/ttt" --welcome %F' "$entry" || fail "escaping: $(grep Exec "$entry")"

run sh "$script" remove
[ ! -e "$entry" ] || fail "entry not removed"
[ ! -e "$icon" ] || fail "icon not removed"
run sh "$script" remove || fail "remove with nothing installed failed"

printf '[Desktop Entry]\nName=Mine\n' >"$entry"
if run sh "$script" install /usr/bin/ttt 2>/dev/null; then fail "install overwrote a user's launcher"; fi
run sh "$script" remove
grep -q Mine "$entry" || fail "remove deleted a user's launcher"

echo "linux: ok"
