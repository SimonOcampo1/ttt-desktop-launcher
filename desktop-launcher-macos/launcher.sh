#!/bin/sh
# Usage: launcher.sh install|repair|set-defaults|remove [ttt-executable] [config-directory] [extensions...]
#
# Finder hands files to a registered .app as an Apple Event, not argv, so the
# launcher is an AppleScript applet. install leaves an existing TTT.app alone;
# repair rebuilds it. Only an app carrying the marker is ever touched.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
action=${1:-}
exe=${2:-}
app=$HOME/Applications/TTT.app
res=$app/Contents/Resources
marker=$res/ttt-managed
previous=$res/previous-handlers
bundle_id=io.github.simonocampo1.tttlauncher
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
config=${3-${TTT_CONFIG_DIR:-}}
services() { osascript -l JavaScript "$here/services.js" "$@"; }

die() {
	echo "$*" >&2
	exit 1
}

applescript_string() {
	printf '"%s"' "$(printf '%s' "$1" | sed 's/[\\"]/\\&/g')"
}

# Sets launch to AppleScript that starts `cmd` (a shell-quoted ttt command
# line) in the terminal ttt was running in when the plugin was installed.
detect_terminal() {
	open_app=''
	terminal=Terminal
	if [ -n "${GHOSTTY_RESOURCES_DIR:-}" ] || [ "${TERM_PROGRAM:-}" = ghostty ]; then
		open_app=Ghostty open_args='-e'
	elif [ -n "${KITTY_WINDOW_ID:-}" ]; then
		open_app=kitty open_args=''
	elif [ -n "${WEZTERM_PANE:-}" ]; then
		open_app=WezTerm open_args='start --'
	elif [ -n "${ALACRITTY_WINDOW_ID:-}" ]; then
		open_app=Alacritty open_args='-e'
	fi
	if [ -n "$open_app" ]; then
		terminal=$open_app
		launch="do shell script \"open -na $open_app --args $open_args \" & cmd"
	elif [ "${TERM_PROGRAM:-}" = iTerm.app ]; then
		terminal=iTerm
		launch='tell application "iTerm"
		activate
		create window with default profile command cmd
	end tell'
	else
		launch='tell application "Terminal"
		activate
		do script cmd
	end tell'
	fi
}

applet() {
	cat <<SCRIPT
property tttExe : $(applescript_string "$exe")
property configDir : $(applescript_string "$config")
property terminalApp : $(applescript_string "$terminal")

on run
	launchTTT({})
end run

on open theItems
	launchTTT(theItems)
end open

on launchTTT(theItems)
	set resources to POSIX path of (path to resource "forward.sh")
	set forwardCmd to "/bin/sh " & quoted form of resources & " " & quoted form of tttExe & " " & quoted form of configDir & " " & quoted form of terminalApp
	set cmd to "env TTT_CONFIG_DIR=" & quoted form of configDir & " " & quoted form of tttExe & " --welcome"
	repeat with f in theItems
		set cmd to cmd & " " & quoted form of POSIX path of f
		set forwardCmd to forwardCmd & " " & quoted form of POSIX path of f
	end repeat
	try
		do shell script forwardCmd
		return
	on error messageText number errorNumber
		if errorNumber is not 2 then
			display notification messageText with title "ttt: could not open files"
			return
		end if
	end try
	$launch
end launchTTT
SCRIPT
}

build() {
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	applet >"$tmp/ttt.applescript"
	osacompile -o "$tmp/TTT.app" "$tmp/ttt.applescript"
	plist=$tmp/TTT.app/Contents/Info.plist
	plutil -replace CFBundleIdentifier -string "$bundle_id" "$plist"
	plutil -replace CFBundleName -string TTT "$plist"
	plutil -replace CFBundleIconFile -string ttt "$plist"
	plutil -replace LSUIElement -bool true "$plist"
	plutil -remove CFBundleIconName "$plist" 2>/dev/null || true
	plutil -replace CFBundleDocumentTypes -json "$(services documents "$here/extensions.txt")" "$plist"
	plutil -replace UTExportedTypeDeclarations -json "$(services declarations "$here/extensions.txt")" "$plist"
	cp "$here/ttt.icns" "$tmp/TTT.app/Contents/Resources/ttt.icns"
	rm -f "$tmp/TTT.app/Contents/Resources/applet.icns" "$tmp/TTT.app/Contents/Resources/droplet.icns" "$tmp/TTT.app/Contents/Resources/Assets.car"
	cp "$here/forward.sh" "$here/services.js" "$here/launcher.sh" "$here/extensions.txt" "$tmp/TTT.app/Contents/Resources/"
	[ ! -f "$previous" ] || cp "$previous" "$tmp/TTT.app/Contents/Resources/previous-handlers"
	: >"$tmp/TTT.app/Contents/Resources/ttt-managed"
	# Editing Info.plist invalidates osacompile's ad-hoc signature.
	codesign --force --sign - "$tmp/TTT.app" >/dev/null 2>&1
	mkdir -p "$(dirname "$app")"
	rm -rf "$app"
	mv "$tmp/TTT.app" "$app"
	"$lsregister" -f "$app" >/dev/null 2>&1 || true
}

handler() { services get "$1"; }

set_handler() {
	[ "$(services set "$1" "$2")" = 0 ] || die "could not change the default for $1"
}

install() {
	[ "$(uname)" = Darwin ] || die "this plugin is for macOS; use desktop-launcher-linux on Linux"
	if [ -e "$app" ]; then
		[ -e "$marker" ] || die "$app was not created by ttt; leaving it alone"
		[ "$action" = repair ] || return 0
	fi
	if [ -z "$exe" ]; then
		exe=$(command -v ttt) || die "cannot find the ttt executable"
	fi
	[ -z "$config" ] || config=$(services absolute "$config")
	detect_terminal
	build
}

set_defaults() {
	[ -e "$marker" ] || die "TTT.app is not installed; run Desktop Launcher: Repair"
	# Optional extension arguments let Mac verification touch md/json only.
	if [ "$#" -ge 3 ]; then shift 3; else set --; fi
	"$lsregister" -f "$app" >/dev/null 2>&1 || true
	utis=$(services defaults "$here/extensions.txt" "$@")
	applied=0
	for uti in $utis; do
		current=$(handler "$uti")
		if [ "$current" != "$bundle_id" ] && ! awk -v key="$uti" '$1 == key {found=1} END {exit !found}' "$previous" 2>/dev/null; then
			printf '%s %s\n' "$uti" "$current" >>"$previous"
		fi
		set_handler "$uti" "$bundle_id"
		applied=$((applied + 1))
	done
	skipped=$(services excluded "$here/extensions.txt" "$@")
	printf 'Finder defaults: %s text types applied. Excluded extensions: %s\n' "$applied" "${skipped:-none}"
}

remove() {
	[ -e "$app" ] && [ -e "$marker" ] || return 0
	if [ -f "$previous" ]; then
		while read -r uti prev; do
			[ -n "$prev" ] || continue
			current=$(handler "$uti") || die "could not read the default for $uti; keeping recovery data"
			if [ "$current" = "$bundle_id" ]; then set_handler "$uti" "$prev"; fi
		done <"$previous"
	fi
	"$lsregister" -u "$app" >/dev/null 2>&1 || true
	rm -rf "$app"
}

case $action in
install | repair) install ;;
set-defaults) set_defaults "$@" ;;
remove) remove ;;
*) die "usage: $0 install|repair|set-defaults|remove [ttt-executable] [config-directory] [extensions...]" ;;
esac
