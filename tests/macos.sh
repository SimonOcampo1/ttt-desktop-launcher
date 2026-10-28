#!/bin/sh
# Runs desktop-launcher-macos/launcher.sh with osacompile, plutil, codesign and
# uname stubbed, so the generated applet can be checked off macOS.
set -eu
script=$(cd "$(dirname "$0")/.." && pwd)/desktop-launcher-macos/launcher.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"
cat >"$tmp/bin/osacompile" <<'STUB'
#!/bin/sh
mkdir -p "$2/Contents/Resources"
cp "$3" "$2/Contents/Resources/script.applescript"
STUB
printf '#!/bin/sh\necho Darwin\n' >"$tmp/bin/uname"
printf '#!/bin/sh\necho "$*" >>"$HOME/plutil.log"\n' >"$tmp/bin/plutil"
printf '#!/bin/sh\n' >"$tmp/bin/codesign"
chmod +x "$tmp/bin/"*
app=$tmp/home/Applications/TTT.app
applet=$app/Contents/Resources/script.applescript

fail() {
	echo "FAIL: $*" >&2
	exit 1
}
run() { env -u KITTY_WINDOW_ID -u WEZTERM_PANE -u ALACRITTY_WINDOW_ID -u GHOSTTY_RESOURCES_DIR -u TERM_PROGRAM HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" "$@"; }

run sh "$script" install '/opt/my "apps"/ttt'
grep -qF 'property tttExe : "/opt/my \"apps\"/ttt"' "$applet" || fail "exe literal: $(grep tttExe "$applet" | head -1)"
grep -qF 'tell application "Terminal"' "$applet" || fail "expected the Terminal.app fallback"
[ -e "$app/Contents/Resources/ttt-managed" ] || fail "marker missing"
[ -e "$app/Contents/Resources/ttt.icns" ] || fail "icon missing"
grep -q 'CFBundleIdentifier' "$tmp/home/plutil.log" || fail "bundle id not set"

run env GHOSTTY_RESOURCES_DIR=/x sh "$script" install /usr/local/bin/ttt
grep -qF '/opt/my' "$applet" || fail "install rebuilt an existing app"
run env GHOSTTY_RESOURCES_DIR=/x sh "$script" repair /usr/local/bin/ttt
grep -qF 'do shell script "open -na Ghostty --args -e " & cmd' "$applet" || fail "ghostty launch: $(grep 'do shell' "$applet")"

run sh "$script" remove
[ ! -e "$app" ] || fail "app not removed"

mkdir -p "$app"
if run sh "$script" install /usr/local/bin/ttt 2>/dev/null; then fail "install replaced a user's TTT.app"; fi
run sh "$script" remove
[ -d "$app" ] || fail "remove deleted a user's TTT.app"

echo "macos (stubbed): ok"
