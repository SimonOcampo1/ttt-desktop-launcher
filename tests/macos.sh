#!/bin/sh
# Portable runtime/LaunchServices regression tests (Node and Python 3 required).
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
script=$root/desktop-launcher-macos/launcher.sh
tmp=$(mktemp -d /tmp/ttt-launcher-test.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
export TEST_BRIDGE="$tmp/bridge.js" TEST_STATE="$tmp/state.json" TEST_LOG="$tmp/events"
mkdir -p "$tmp/bin" "$tmp/home" "$tmp/config" "$tmp/temp with spaces"
cat >"$TEST_BRIDGE" <<'STUB'
const fs = require('fs'), vm = require('vm'), assert = require('assert'), path = require('path');
const [script, ...args] = process.argv.slice(4);
const state = fs.existsSync(process.env.TEST_STATE) ? JSON.parse(fs.readFileSync(process.env.TEST_STATE)) : {};
const log = s => fs.appendFileSync(process.env.TEST_LOG, s + '\n');
const wrap = js => ({js, get stringByStandardizingPath() {return wrap(path.normalize(js));}});
const $ = x => wrap(x);
$.NSUTF8StringEncoding = 4; $.kLSRolesAll = -1;
$.NSString = {stringWithContentsOfFileEncodingError(p) {try {return wrap(fs.readFileSync(p.js, 'utf8'));} catch (_) {return null;}}};
$.LSCopyDefaultRoleHandlerForContentType = t => {
    assert.equal(typeof t.js, 'string', 'CoreServices needs a bridged string');
    return wrap(state[t.js] || 'original.' + t.js);
};
// Reproduce the previous raw-JS capture bug at the actual mocked API boundary.
assert.throws(() => $.LSCopyDefaultRoleHandlerForContentType('public.json'));
$.LSSetDefaultRoleHandlerForContentType = (t, _, h) => {
    assert.equal(typeof t.js, 'string'); assert.equal(typeof h.js, 'string');
    log('set ' + t.js + ' ' + h.js);
    if (process.env.FAIL_SET === t.js) return -1;
    state[t.js] = h.js; fs.writeFileSync(process.env.TEST_STATE, JSON.stringify(state)); return 0;
};
$.UTTypeCreateAllIdentifiersForTag = (_, ext) => {
    const types = {md:'net.daringfireball.markdown', markdown:'net.daringfireball.markdown', json:'public.json',
        htm:'public.html', html:'public.html', xhtml:'public.xhtml', shtml:'public.html',
        ts:process.env.TYPE_SCRIPT || 'public.mpeg-2-transport-stream', dot:'com.microsoft.word.dot', pp:'cx.c3.pp-archive', txt:'public.plain-text', phtml:'public.html'};
    return wrap(types[ext.js] ? [types[ext.js]] : []);
};
$.NSRunningApplication = {runningApplicationWithProcessIdentifier(pid) {
    log('focus ' + pid); return {activationPolicy:process.env.FOCUS_FALLBACK ? 1 : 0,
        isTerminated:false, activateWithOptions(){return true;}};
}, runningApplicationsWithBundleIdentifier(id) {
    return {count:1, objectAtIndex(){return {activateWithOptions(){log('activate ' + id.js);}};}};
}};
const context = { $, ObjC:{import(){}, castRefToObject:x=>x, deepUnwrap:x=>x.js},
    Application:{currentApplication(){return {doShellScript(){return '1';}};}} };
try {
    vm.createContext(context); vm.runInContext(fs.readFileSync(script, 'utf8'), context);
    const value = context.run(args); if (value !== undefined) console.log(value);
} catch (err) { console.error(err); process.exit(1); }
STUB
cat >"$tmp/bin/osascript" <<'STUB'
#!/bin/sh
exec node "$TEST_BRIDGE" "$@"
STUB
cat >"$tmp/bin/osacompile" <<'STUB'
#!/bin/sh
mkdir -p "$2/Contents/Resources"
cp "$3" "$2/Contents/Resources/script.applescript"
touch "$2/Contents/Resources/droplet.icns" "$2/Contents/Resources/applet.icns" "$2/Contents/Resources/Assets.car"
STUB
cat >"$tmp/bin/plutil" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$HOME/plutil.log"
STUB
cat >"$tmp/bin/stat" <<'STUB'
#!/bin/sh
if [ "$1" = -f ]; then
    python3 -c 'import os,sys,stat; s=os.stat(sys.argv[1]); print(str(s.st_uid)+":"+format(stat.S_IMODE(s.st_mode),"o"))' "$3"
else
    /usr/bin/stat "$@"
fi
STUB
cat >"$tmp/bin/ttt" <<'STUB'
#!/bin/sh
printf 'config=%s\n' "$TTT_CONFIG_DIR" >>"$TEST_LOG"
printf 'arg=%s\n' "$@" >>"$TEST_LOG"
[ "${CLIENT_FAIL:-0}" = 0 ] || { echo 'ttt: cannot open file' >&2; exit 1; }
STUB
printf '#!/bin/sh\necho Darwin\n' >"$tmp/bin/uname"
cat >"$tmp/bin/codesign" <<'STUB'
#!/bin/sh
exit "${FAIL_SIGN:-0}"
STUB
chmod +x "$tmp/bin/"*
app=$tmp/home/Applications/TTT.app
res=$app/Contents/Resources
applet=$res/script.applescript
fail() { echo "FAIL: $*" >&2; exit 1; }
run() { env -u KITTY_WINDOW_ID -u WEZTERM_PANE -u ALACRITTY_WINDOW_ID -u GHOSTTY_RESOURCES_DIR -u TERM_PROGRAM HOME="$tmp/home" PATH="$tmp/bin:$PATH" TMPDIR="$tmp/temp with spaces/" "$@"; }
service() { run osascript -l JavaScript "$root/desktop-launcher-macos/services.js" "$@"; }
run sh "$script" install '/opt/my "apps"/ttt' "$tmp/config"
grep -qF 'property tttExe : "/opt/my \"apps\"/ttt"' "$applet" || fail 'exe quoting'
grep -qF 'tell application "Terminal"' "$applet" || fail 'terminal fallback'
for file in ttt-managed ttt.icns forward.sh services.js; do [ -e "$res/$file" ] || fail "missing $file"; done
for file in droplet.icns applet.icns Assets.car; do [ ! -e "$res/$file" ] || fail "competing icon $file"; done
grep -q 'LSUIElement -bool true' "$tmp/home/plutil.log" || fail 'Dock setting'
grep -q 'remove CFBundleIconName' "$tmp/home/plutil.log" || fail 'icon setting'
run env GHOSTTY_RESOURCES_DIR=/x sh "$script" install /usr/local/bin/ttt
grep -qF '/opt/my' "$applet" || fail 'install rebuilt existing app'
run env TYPE_SCRIPT=example.typescript osascript -l JavaScript "$res/services.js" defaults "$root/desktop-launcher-macos/extensions.txt" ts >"$tmp/ts-type"
grep -qx example.typescript "$tmp/ts-type" || fail 'valid source type not reused'
service documents "$root/desktop-launcher-macos/extensions.txt" >"$tmp/docs.json"
service defaults "$root/desktop-launcher-macos/extensions.txt" >"$tmp/defaults"
python3 - "$root" "$tmp" <<'PY'
import json,sys,pathlib
root,tmp=map(pathlib.Path,sys.argv[1:])
ext=(root/'desktop-launcher-macos/extensions.txt').read_text().splitlines()
docs=json.loads((tmp/'docs.json').read_text())[0]
assert len(ext)==155 and docs['CFBundleTypeExtensions']==ext
utis=(tmp/'defaults').read_text().splitlines()
assert len(utis)==len(set(utis))
assert not set(utis)&{'public.html','public.xhtml','public.text','public.source-code','public.data','public.plain-text',
    'public.mpeg-2-transport-stream','com.microsoft.word.dot','cx.c3.pp-archive'}
assert 'public.html' in docs['LSItemContentTypes']
PY
# Capture before changes, preserve first originals, preserve through repair, retry restore.
if run env FAIL_SET=public.json sh "$script" set-defaults '' '' md json 2>/dev/null; then fail 'partial failure hidden'; fi
grep -qx 'public.json original.public.json' "$res/previous-handlers" || fail 'failed set not journaled'
run sh "$script" set-defaults '' '' md json
cp "$res/previous-handlers" "$tmp/saved"
run sh "$script" set-defaults '' '' md json
cmp "$tmp/saved" "$res/previous-handlers"
run env GHOSTTY_RESOURCES_DIR=/x sh "$script" repair "$tmp/bin/ttt" "$tmp/config"
cmp "$tmp/saved" "$res/previous-handlers"
if run env FAIL_SIGN=1 sh "$script" repair "$tmp/bin/ttt" "$tmp/config"; then fail 'sign failure hidden'; fi
cmp "$tmp/saved" "$res/previous-handlers"
grep -qF 'do shell script "open -na Ghostty --args -e " & cmd' "$applet" || fail 'Ghostty launch'
if run env FAIL_SET=public.json sh "$script" remove 2>/dev/null; then fail 'restore failure hidden'; fi
[ -f "$res/previous-handlers" ] || fail 'recovery data lost'
run sh "$script" remove
[ ! -e "$app" ] || fail 'app not removed'
grep -q 'set public.json original.public.json' "$TEST_LOG" || fail 'original not restored'
# Runtime: real Unix socket in a spaced temp directory, no RPC implementation in helper.
run sh "$script" install "$tmp/bin/ttt" "$tmp/config"
file="$tmp/a 'quoted' file.md"; touch "$file"
forward() { run sh "$res/forward.sh" "$tmp/bin/ttt" "$tmp/config" Ghostty "$@"; }
unavailable() { rc=0; forward "$@" || rc=$?; [ "$rc" = 2 ] || fail "fallback status $rc"; }
unavailable "$file"
printf '{"reuseWindow":true}\n' >"$tmp/config/settings.json"
unavailable "$file" # Old ttt/no listener.
python3 - "$tmp" "$$" "$PPID" <<'PY'
import sys,pathlib,socket,hashlib,os
root=pathlib.Path(sys.argv[1]); d=root/'temp with spaces'/('ttt-'+str(os.getuid())); d.mkdir(mode=0o700)
prefix=hashlib.sha256(str(root/'config').encode()).hexdigest()[:8]
def base36(n):
    s=''
    while n: n,r=divmod(n,36); s='0123456789abcdefghijklmnopqrstuvwxyz'[r]+s
    return s
for start,pid in [('00000001',int(sys.argv[3])),('00000002',int(sys.argv[2])),('00000003',2147483647)]:
    s=socket.socket(socket.AF_UNIX); s.bind(str(d/(prefix+'-'+start+'-'+base36(pid)+'.sock'))); s.close()
(d/(prefix+'-zzzzzzzz-'+base36(int(sys.argv[3]))+'.sock')).touch()
# A newer listener for another config must not affect selection.
s=socket.socket(socket.AF_UNIX); s.bind(str(d/('othercfg-zzzzzzzz-'+base36(int(sys.argv[3]))+'.sock')))
PY
: >"$TEST_LOG"
forward "$file"
grep -qx "focus $$" "$TEST_LOG" || fail 'newest live editor not focused'
grep -qxF "arg=$file" "$TEST_LOG" || fail 'filename changed'
[ "$(grep -c '^arg=' "$TEST_LOG")" = 2 ] || fail 'unexpected CLI file argument'
grep -qxF "config=$tmp/config" "$TEST_LOG" || fail 'config not passed'
run env FOCUS_FALLBACK=1 osascript -l JavaScript "$res/services.js" focus "$$" Ghostty >/dev/null
grep -qx 'activate com.mitchellh.ghostty' "$TEST_LOG" || fail 'terminal fallback not activated'
: >"$TEST_LOG"
rc=0
run env CLIENT_FAIL=1 sh "$res/forward.sh" "$tmp/bin/ttt" "$tmp/config" Ghostty "$file" 2>"$tmp/error" || rc=$?
[ "$rc" = 1 ] || fail 'handoff error allowed terminal fallback'
grep -q 'cannot open file' "$tmp/error" || fail 'stderr lost'
[ "$(grep -c '^config=' "$TEST_LOG")" = 1 ] || fail 'handoff retried'
if grep -q '^focus' "$TEST_LOG"; then fail 'failed handoff focused'; fi
unavailable "$tmp" # Folders launch a terminal.
printf '{"reuseWindow":false}\n' >"$tmp/config/settings.json"
unavailable "$file"
printf '{"reuseWindow":true}\n' >"$tmp/config/settings.json"
chmod 755 "$tmp/temp with spaces/ttt-$(id -u)"
unavailable "$file"
chmod 700 "$tmp/temp with spaces/ttt-$(id -u)"
find "$tmp/temp with spaces" -type s -delete
unavailable "$file" # Only regular socket-looking files remain.
run sh "$script" remove
mkdir -p "$app"
if run sh "$script" install /usr/local/bin/ttt 2>/dev/null; then fail 'overwrote unmanaged app'; fi
run sh "$script" remove
[ -d "$app" ] || fail 'deleted unmanaged app'
echo 'macos (stubbed runtime and LaunchServices): ok'
