#!/bin/sh
# Usage: launcher.sh install|repair|remove [ttt-executable]
#
# install leaves an existing launcher alone, so the terminal chosen at install
# time is not rewritten by a later install from another terminal; repair
# rewrites it. Only files carrying the marker are ever touched.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
action=${1:-}
exe=${2:-}
data=${XDG_DATA_HOME:-$HOME/.local/share}
entry=$data/applications/ttt.desktop
icon=$data/icons/hicolor/scalable/apps/ttt.svg
marker=X-TTT-Managed=true

die() {
	echo "$*" >&2
	exit 1
}

# Desktop Entry Exec quoting: inside double quotes `"`, "`", `$` and `\` are
# backslash-escaped, and a literal % is %% everywhere.
quote() {
	case $1 in
	'' | *[!A-Za-z0-9_./:@+=,-]*)
		printf '"%s"' "$(printf '%s' "$1" | sed -e 's/[\\"`$]/\\&/g' -e 's/%/%%/g')"
		;;
	*) printf '%s' "$1" ;;
	esac
}

detect_terminal() {
	term_bin='' term_args='' term_class=''
	if [ -n "${KITTY_WINDOW_ID:-}" ]; then
		t=kitty term_args='--class ttt -e' term_class=ttt
	elif [ -n "${WEZTERM_PANE:-}" ]; then
		t=wezterm term_args='start --class ttt --' term_class=ttt
	elif [ -n "${ALACRITTY_WINDOW_ID:-}" ]; then
		t=alacritty term_args='--class ttt -e' term_class=ttt
	elif [ -n "${GHOSTTY_RESOURCES_DIR:-}" ]; then
		t=ghostty term_args='-e'
	elif [ -n "${KONSOLE_VERSION:-}" ]; then
		t=konsole term_args='-e'
	else
		case ${TERM:-} in
		foot*) t=foot term_args='--app-id ttt' term_class=ttt ;;
		*) return 0 ;;
		esac
	fi
	# A launcher runs without the shell's PATH, so the terminal needs its
	# absolute path as much as ttt does.
	if ! term_bin=$(command -v "$t"); then
		term_bin='' term_args='' term_class=''
	fi
}

desktop_entry() {
	exec_line=''
	if [ -n "$term_bin" ]; then
		exec_line=$(quote "$term_bin")
		for a in $term_args; do exec_line="$exec_line $(quote "$a")"; done
		exec_line="$exec_line "
	fi
	exec_line="$exec_line$(quote "$exe") --welcome %F"

	cat <<ENTRY
[Desktop Entry]
Type=Application
Name=TTT Editor
GenericName=Text Editor
Comment=IDE for the terminal
Icon=ttt
Exec=$exec_line
ENTRY
	if [ -z "$term_bin" ]; then
		echo 'Terminal=true'
	else
		echo 'Terminal=false'
		[ -z "$term_class" ] || echo "StartupWMClass=$term_class"
	fi
	cat <<ENTRY
Categories=Development;IDE;TextEditor;
MimeType=text/plain;inode/directory;
Keywords=editor;ide;code;terminal;
$marker
ENTRY
}

# Replace through a rename, so a symlink there (a stowed dotfile, say) is
# replaced rather than written through to its target.
write() {
	mkdir -p "$(dirname "$1")"
	tmp=$(mktemp "$(dirname "$1")/.ttt-XXXXXX")
	cat >"$tmp"
	chmod 644 "$tmp"
	mv -f "$tmp" "$1"
}

refresh() {
	# Only refreshes the MimeType cache behind "Open With"; launchers read the
	# directory directly.
	if command -v update-desktop-database >/dev/null 2>&1; then
		update-desktop-database "$data/applications" >/dev/null 2>&1 || true
	fi
}

managed() {
	grep -qx "$marker" "$entry"
}

install() {
	if [ -e "$entry" ]; then
		managed || die "$entry was not created by ttt; leaving it alone"
		[ "$action" = repair ] || return 0
	fi
	if [ -z "$exe" ]; then
		exe=$(command -v ttt) || die "cannot find the ttt executable"
	fi
	detect_terminal
	write "$icon" <"$here/ttt.svg"
	desktop_entry | write "$entry"
	refresh
}

remove() {
	[ -e "$entry" ] && managed || return 0
	rm -f "$entry"
	if cmp -s "$icon" "$here/ttt.svg"; then
		rm -f "$icon"
	fi
	refresh
}

case $action in
install | repair) install ;;
remove) remove ;;
*) die "usage: $0 install|repair|remove [ttt-executable]" ;;
esac
