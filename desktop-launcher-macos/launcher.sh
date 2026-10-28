#!/bin/sh
# Usage: launcher.sh install|repair|set-defaults|remove [ttt-executable]
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
utis='public.json net.daringfireball.markdown'

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
		launch="do shell script \"open -na $open_app --args $open_args \" & cmd"
	elif [ "${TERM_PROGRAM:-}" = iTerm.app ]; then
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

on run
	launchTTT({})
end run

on open theItems
	launchTTT(theItems)
end open

on launchTTT(theItems)
	set cmd to quoted form of tttExe & " --welcome"
	repeat with f in theItems
		set cmd to cmd & " " & quoted form of POSIX path of f
	end repeat
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
	plutil -replace CFBundleDocumentTypes -json '[{"CFBundleTypeName":"Text","CFBundleTypeRole":"Editor","LSHandlerRank":"Alternate","LSItemContentTypes":["public.text","public.json","net.daringfireball.markdown","public.folder"]}]' "$plist"
	cp "$here/ttt.icns" "$tmp/TTT.app/Contents/Resources/ttt.icns"
	rm -f "$tmp/TTT.app/Contents/Resources/applet.icns"
	: >"$tmp/TTT.app/Contents/Resources/ttt-managed"
	# Editing Info.plist invalidates osacompile's ad-hoc signature.
	codesign --force --sign - "$tmp/TTT.app" >/dev/null 2>&1 || true
	mkdir -p "$(dirname "$app")"
	rm -rf "$app"
	mv "$tmp/TTT.app" "$app"
	"$lsregister" -f "$app" >/dev/null 2>&1 || true
}

handler() {
	osascript -l JavaScript -e 'ObjC.import("CoreServices")' -e "function run(argv) {
		var h = \$.LSCopyDefaultRoleHandlerForContentType(argv[0], \$.kLSRolesAll)
		return h ? ObjC.castRefToObject(h).js : ''
	}" "$1"
}

set_handler() {
	osascript -l JavaScript -e 'ObjC.import("CoreServices")' -e 'function run(argv) {
		return $.LSSetDefaultRoleHandlerForContentType(argv[0], $.kLSRolesAll, argv[1])
	}' "$1" "$2" | grep -qx 0 || die "could not make ttt the default for $1"
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
	saved=''
	[ ! -f "$previous" ] || saved=$(cat "$previous")
	detect_terminal
	build
	[ -z "$saved" ] || printf '%s\n' "$saved" >"$previous"
}

set_defaults() {
	[ -e "$marker" ] || die "TTT.app is not installed; run Desktop Launcher: Repair"
	for uti in $utis; do
		current=$(handler "$uti")
		if [ "$current" != "$bundle_id" ] && ! grep -q "^$uti " "$previous" 2>/dev/null; then
			echo "$uti $current" >>"$previous"
		fi
		set_handler "$uti" "$bundle_id"
	done
}

remove() {
	[ -e "$app" ] && [ -e "$marker" ] || return 0
	if [ -f "$previous" ]; then
		while read -r uti prev; do
			[ -z "$prev" ] || set_handler "$uti" "$prev" || true
		done <"$previous"
	fi
	"$lsregister" -u "$app" >/dev/null 2>&1 || true
	rm -rf "$app"
}

case $action in
install | repair) install ;;
set-defaults) set_defaults ;;
remove) remove ;;
*) die "usage: $0 install|repair|set-defaults|remove [ttt-executable]" ;;
esac
