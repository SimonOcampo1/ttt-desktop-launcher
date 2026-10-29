#!/bin/sh
# Portable runtime/LaunchServices regression tests (Node and Python 3 required).
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d /tmp/ttt-launcher-test.XXXXXX)
fixture=''
cp -R "$root/desktop-launcher-macos" "$tmp/plugin"
script=$tmp/plugin/launcher.sh
trap '[ -z "$fixture" ] || { kill "$fixture" 2>/dev/null || true; wait "$fixture" 2>/dev/null || true; }; rm -rf "$tmp"' EXIT
export TEST_BRIDGE="$tmp/bridge.js" TEST_STATE="$tmp/state.json" TEST_LOG="$tmp/events"
mkdir -p "$tmp/bin" "$tmp/home" "$tmp/config" "$tmp/temp with spaces"
cat >"$TEST_BRIDGE" <<'STUB'
const fs = require('fs'), vm = require('vm'), assert = require('assert'), path = require('path');
const [script, ...args] = process.argv.slice(4);
const state = fs.existsSync(process.env.TEST_STATE) ? JSON.parse(fs.readFileSync(process.env.TEST_STATE)) : {};
const log = s => fs.appendFileSync(process.env.TEST_LOG, s + '\n');
const wrap = js => ({js, get stringByStandardizingPath() {return wrap(path.normalize(js).replace(/^\/private\//, '/'));},
    get stringByResolvingSymlinksInPath() {return wrap(fs.realpathSync(js));},
    get stringByDeletingLastPathComponent() {return wrap(path.dirname(js));}});
const $ = x => wrap(x);
$.NSFileManager = {defaultManager:{currentDirectoryPath:wrap(process.cwd())}};
$.NSHomeDirectory = () => wrap(process.env.HOME);
$.NSUTF8StringEncoding = 4; $.kLSRolesAll = -1;
$.NSString = {stringWithContentsOfFileEncodingError(p) {try {return wrap(fs.readFileSync(p.js, 'utf8'));} catch (_) {return null;}}};
$.LSCopyDefaultRoleHandlerForContentType = t => {
    assert.equal(typeof t.js, 'string', 'CoreServices needs a bridged string');
    return wrap(state[t.js] || 'original.' + t.js);
};
$.LSSetDefaultRoleHandlerForContentType = (t, _, h) => {
    assert.equal(typeof t.js, 'string'); assert.equal(typeof h.js, 'string');
    log('set ' + t.js + ' ' + h.js);
    if (process.env.FAIL_SET === t.js) return -1;
    state[t.js] = h.js; fs.writeFileSync(process.env.TEST_STATE, JSON.stringify(state)); return 0;
};
$.UTTypeConformsTo = (t, p) => t.js === p.js || (['public.text','public.source-code'].includes(p.js) &&
    (/^(net.daringfireball|example.typescript|io.github.simonocampo1|public.json|public.plain-text)/.test(t.js) || ['public.html','public.xhtml'].includes(t.js)));
$.UTTypeCreatePreferredIdentifierForTag = (_, ext) => {
    const types = {md:'net.daringfireball.markdown', markdown:'net.daringfireball.markdown', json:'public.json',
        htm:'public.html', html:'public.html', xhtml:'public.xhtml', shtml:'public.html',
        ts:process.env.TYPE_SCRIPT || 'public.mpeg-2-transport-stream', dot:'com.microsoft.word.dot', pp:'cx.c3.pp-archive', txt:'public.plain-text', phtml:'public.html'};
    return wrap(types[ext.js] || (fs.existsSync(process.env.HOME + '/Applications/TTT.app/Contents/Resources/ttt-managed') && !process.env.UNDECLARED ?
        'io.github.simonocampo1.tttlauncher.code.' + ext.js.replace(/[^a-z0-9.]/g,c=>'-'+c.charCodeAt(0).toString(16)+'-') : 'dyn.unknown'));
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
[ "${CLIENT_HANG:-0}" = 0 ] || exec python3 -c 'import time; time.sleep(60)'
[ "${CLIENT_FAIL:-0}" = 0 ] || { echo 'ttt: cannot open file' >&2; exit 1; }
STUB
cat >"$tmp/bin/nc" <<'STUB'
#!/usr/bin/env python3
import socket,sys
assert sys.argv[1:4] == ['-U','-w','1']
s=socket.socket(socket.AF_UNIX); s.settimeout(1)
try: s.connect(sys.argv[4])
except OSError: sys.exit(1)
STUB
cat >"$tmp/bin/sleep" <<'STUB'
#!/bin/sh
echo "$$" >>"$HOME/timers"
exec /bin/sleep "${TIMER_SECONDS:-$1}"
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
run() { env -u TTT_CONFIG_DIR -u KITTY_WINDOW_ID -u WEZTERM_PANE -u ALACRITTY_WINDOW_ID -u GHOSTTY_RESOURCES_DIR -u TERM_PROGRAM HOME="$tmp/home" PATH="$tmp/bin:$PATH" TMPDIR="$tmp/temp with spaces/" "$@"; }
service() { run osascript -l JavaScript "$root/desktop-launcher-macos/services.js" "$@"; }
run sh "$script" install '/opt/my "apps"/ttt' "$tmp/config"
grep -qF 'property tttExe : "/opt/my \"apps\"/ttt"' "$applet" || fail 'exe quoting'
grep -qF 'tell application "Terminal"' "$applet" || fail 'terminal fallback'
for file in ttt-managed ttt.icns forward.sh services.js launcher.sh extensions.txt; do [ -e "$res/$file" ] || fail "missing $file"; done
for file in droplet.icns applet.icns Assets.car; do [ ! -e "$res/$file" ] || fail "competing icon $file"; done
grep -q 'LSUIElement -bool true' "$tmp/home/plutil.log" || fail 'Dock setting'
grep -q 'remove CFBundleIconName' "$tmp/home/plutil.log" || fail 'icon setting'
run env GHOSTTY_RESOURCES_DIR=/x sh "$script" install /usr/local/bin/ttt
grep -qF '/opt/my' "$applet" || fail 'install rebuilt existing app'
run env TYPE_SCRIPT=example.typescript osascript -l JavaScript "$res/services.js" defaults "$root/desktop-launcher-macos/extensions.txt" ts >"$tmp/ts-type"
grep -qx example.typescript "$tmp/ts-type" || fail 'valid source type not reused'
service documents "$root/desktop-launcher-macos/extensions.txt" >"$tmp/docs.json"
service defaults "$root/desktop-launcher-macos/extensions.txt" >"$tmp/defaults"
service excluded "$root/desktop-launcher-macos/extensions.txt" >"$tmp/excluded"
python3 - "$root" "$tmp" <<'PY'
import json,sys,pathlib
root,tmp=map(pathlib.Path,sys.argv[1:])
ext=(root/'desktop-launcher-macos/extensions.txt').read_text().splitlines()
docs=json.loads((tmp/'docs.json').read_text())[0]
assert len(ext)==155 and docs['CFBundleTypeExtensions']==ext
utis=(tmp/'defaults').read_text().splitlines()
assert len(utis)==len(set(utis))
assert 'public.plain-text' in utis
assert not set(utis)&{'public.html','public.xhtml','public.text','public.source-code','public.data',
    'public.mpeg-2-transport-stream','com.microsoft.word.dot','cx.c3.pp-archive'}
assert 'public.html' in docs['LSItemContentTypes']
assert set((tmp/'excluded').read_text().strip().split(', ')) == {'htm','html','xhtml','shtml','phtml','ts','dot','pp'}
PY
[ "$(service absolute /private/tmp/a/../b)" = /private/tmp/b ] || fail 'config alias changed'
printf 'bash_login\nc++\ncplus\n' >"$tmp/types"
service declarations "$tmp/types" >"$tmp/private.json"
[ -z "$(run env UNDECLARED=1 osascript -l JavaScript "$res/services.js" defaults "$tmp/types")" ] || fail 'unresolved types defaulted'
python3 - "$tmp/private.json" <<'PYT'
import json,sys,re
ids=[t['UTTypeIdentifier'] for t in json.load(open(sys.argv[1]))]
assert len(ids)==3 and len(set(ids))==3 and all(re.fullmatch('[a-z0-9.-]+',s) for s in ids)
PYT
mkdir -p "$tmp/bin/config" "$tmp/home/.config/ttt"
printf '{"reuseWindow":true}' >"$tmp/home/.config/ttt/settings.json"
[ "$(service reuse '' "$tmp/bin/ttt")" = yes ] || fail 'home settings missed'
printf 'invalid' >"$tmp/bin/config/settings.json"
[ "$(service reuse '' "$tmp/bin/ttt")" = no ] || fail 'invalid sidecar fell through'
printf '{"reuseWindow":true}' >"$tmp/bin/config/settings.json"
[ "$(service reuse "$tmp/config" "$tmp/bin/ttt")" = no ] || fail 'override searched sidecar'
ln -s "$tmp/bin/ttt" "$tmp/linked-ttt"
[ "$(service reuse '' "$tmp/linked-ttt")" = yes ] || fail 'executable symlink settings missed'
run env TTT_CONFIG_DIR= sh "$script" repair "$tmp/bin/ttt"
grep -qF 'property configDir : ""' "$applet" || fail 'normal search forced an override'
# Capture before changes, preserve first originals, preserve through repair, retry restore.
if run env FAIL_SET=public.json sh "$script" set-defaults '' '' md json 2>/dev/null; then fail 'partial failure hidden'; fi
grep -qx 'public.json original.public.json' "$res/previous-handlers" || fail 'failed set not journaled'
run sh "$script" set-defaults '' '' md json
cp "$res/previous-handlers" "$tmp/saved"
run sh "$script" set-defaults '' '' md json
cmp "$tmp/saved" "$res/previous-handlers"
run env GHOSTTY_RESOURCES_DIR=/x TTT_CONFIG_DIR="$tmp/config" sh "$script" repair "$tmp/bin/ttt"
cmp "$tmp/saved" "$res/previous-handlers"
if run env FAIL_SIGN=1 sh "$script" repair "$tmp/bin/ttt" "$tmp/config"; then fail 'sign failure hidden'; fi
cmp "$tmp/saved" "$res/previous-handlers"
grep -qF 'do shell script "open -na Ghostty --args -e " & cmd' "$applet" || fail 'Ghostty launch'
if run env FAIL_SET=public.json sh "$script" remove 2>/dev/null; then fail 'restore failure hidden'; fi
[ -f "$res/previous-handlers" ] || fail 'recovery data lost'
service set net.daringfireball.markdown later.choice >/dev/null
rm -rf "$tmp/plugin"
run sh "$res/launcher.sh" remove
[ "$(service get net.daringfireball.markdown)" = later.choice ] || fail 'later choice overwritten'
[ ! -e "$app" ] || fail 'app not removed'
grep -q 'set public.json original.public.json' "$TEST_LOG" || fail 'original not restored'
cp -R "$root/desktop-launcher-macos" "$tmp/plugin"
# Runtime: real Unix socket in a spaced temp directory, no RPC implementation in helper.
run sh "$script" install "$tmp/bin/ttt" "$tmp/config"
file="$tmp/a 'quoted' file.md"; touch "$file"
forward() { run sh "$res/forward.sh" "$tmp/bin/ttt" "$tmp/config" Ghostty "$@"; }
unavailable() { rc=0; forward "$@" || rc=$?; [ "$rc" = 2 ] || fail "fallback status $rc"; }
unavailable "$file"
printf '{"reuseWindow":true}\n' >"$tmp/config/settings.json"
unavailable "$file" # Old ttt/no listener.
# Linux has no macOS nc: use a real connect-only shim in the bundled helper.
if [ "$(uname)" != Darwin ]; then sed "s|/usr/bin/nc|$tmp/bin/nc|" "$res/forward.sh" >"$tmp/forward"; cp "$tmp/forward" "$res/forward.sh"; fi
python3 - "$tmp" "$$" <<'PYT' &
import sys,pathlib,socket,hashlib,os,selectors
root=pathlib.Path(sys.argv[1]); d=root/'temp with spaces'/('ttt-'+str(os.getuid())); d.mkdir(mode=0o700)
prefix=hashlib.sha256(str(root/'config').encode()).hexdigest()[:8]
def base36(n):
    s=''
    while n: n,r=divmod(n,36); s='0123456789abcdefghijklmnopqrstuvwxyz'[r]+s
    return s
sel=selectors.DefaultSelector()
for config,stamp,pid,live in [(prefix,'00000001',os.getpid(),True),(prefix,'00000002',int(sys.argv[2]),True),
    (prefix,'00000003',int(sys.argv[2]),False),(prefix,'bad',os.getpid(),True),('othercfg','zzzzzzzz',os.getpid(),True)]:
    s=socket.socket(socket.AF_UNIX); s.bind(str(d/(config+'-'+stamp+'-'+base36(pid)+'.sock')))
    if live: s.listen(); sel.register(s,selectors.EVENT_READ)
    else: s.close()
(root/'ready').touch()
while True:
    for key,_ in sel.select():
        conn,_=key.fileobj.accept(); conn.close()
PYT
fixture=$!
while [ ! -e "$tmp/ready" ]; do /bin/sleep .05; done
: >"$TEST_LOG"
run python3 - "$res/forward.sh" "$tmp/bin/ttt" "$tmp/config" "$file" <<'PYT'
import subprocess,sys,time,os,pathlib,signal
start=time.monotonic()
p=subprocess.Popen(['sh',*sys.argv[1:4],'Ghostty',sys.argv[4]],stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
try: out,err=p.communicate(timeout=3)
finally:
    try: os.killpg(p.pid,signal.SIGKILL)
    except ProcessLookupError: pass
assert p.returncode==0,err
timers=pathlib.Path(os.environ['HOME'])/'timers'
for pid in timers.read_text().splitlines() if timers.exists() else []:
    try: os.kill(int(pid),0)
    except ProcessLookupError: continue
    raise AssertionError('timer survived: '+pid)
print('captured handoff completed in %.3fs; timer processes reaped'%(time.monotonic()-start))
PYT
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
rc=0
run env CLIENT_HANG=1 TIMER_SECONDS=.2 sh "$res/forward.sh" "$tmp/bin/ttt" "$tmp/config" Ghostty "$file" 2>"$tmp/error" || rc=$?
[ "$rc" = 1 ] || fail 'watchdog exit status'
grep -q 'handoff timed out' "$tmp/error" || fail 'watchdog failed to bound client'
unavailable "$tmp" # Folders launch a terminal.
printf '{"reuseWindow":false}\n' >"$tmp/config/settings.json"
unavailable "$file"
printf '{"reuseWindow":true}\n' >"$tmp/config/settings.json"
chmod 755 "$tmp/temp with spaces/ttt-$(id -u)"
unavailable "$file"
chmod 700 "$tmp/temp with spaces/ttt-$(id -u)"
kill "$fixture"; wait "$fixture" 2>/dev/null || true; fixture=
unavailable "$file" # Stale sockets with live shell PID are unavailable.
run sh "$script" remove
mkdir -p "$app"
if run sh "$script" install /usr/local/bin/ttt 2>/dev/null; then fail 'overwrote unmanaged app'; fi
run sh "$script" remove
[ -d "$app" ] || fail 'deleted unmanaged app'
echo 'macos (stubbed runtime and LaunchServices): ok'
