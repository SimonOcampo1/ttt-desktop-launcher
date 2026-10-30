// Shared LaunchServices bridge. All CFString arguments must be Objective-C strings.
ObjC.import('CoreServices');
ObjC.import('Foundation');
ObjC.import('AppKit');
function read(path) {
    var value = $.NSString.stringWithContentsOfFileEncodingError($(path), $.NSUTF8StringEncoding, null);
    return value ? value.js : '';
}
function absolute(path) {
    if (path[0] !== '/') path = $.NSFileManager.defaultManager.currentDirectoryPath.js + '/' + path;
    var parts = [];
    path.split('/').forEach(function(p) {
        if (p === '..') parts.pop(); else if (p && p !== '.') parts.push(p);
    });
    return '/' + parts.join('/');
}
function privateType(ext) {
    return 'io.github.simonocampo1.tttlauncher.code.' + ext.replace(/[^a-z0-9.]/g, function(c) {
        return '-' + c.charCodeAt(0).toString(16) + '-';
    });
}
function conforms(type, parent) { return Boolean($.UTTypeConformsTo($(type), $(parent))); }
function textType(type) {
    return ['public.text', 'public.source-code', 'public.data', 'public.content', 'public.item',
        'public.mpeg-2-transport-stream', 'com.microsoft.word.dot', 'cx.c3.pp-archive'].indexOf(type) < 0 &&
        (conforms(type, 'public.text') || conforms(type, 'public.source-code')) &&
        !['public.html', 'public.xhtml', 'public.audiovisual-content', 'public.archive'].some(function(p) {
            return conforms(type, p);
        });
}
function typesFor(ext) {
    // Include text associations even when a binary type is preferred (e.g. ts).
    var refs = $.UTTypeCreateAllIdentifiersForTag($.kUTTagClassFilenameExtension, $(ext), null);
    var types = refs ? ObjC.deepUnwrap(ObjC.castRefToObject(refs)) : [];
    return types.filter(function(t, i, all) { return t && !/^dyn\./.test(t) && all.indexOf(t) === i; });
}
function run(argv) {
    var mode = argv[0];
    if (mode === 'herdr-pane') {
        var pane = JSON.parse(argv[1]).result.root_pane.pane_id;
        if (typeof pane !== 'string' || !pane) throw Error('invalid Herdr pane');
        return pane;
    }
    if (mode === 'reuse') {
        var paths = argv[1] ? [argv[1]] : [
            $(argv[2]).stringByResolvingSymlinksInPath.stringByDeletingLastPathComponent.js + '/config',
            $.NSHomeDirectory().js + '/.config/ttt'];
        for (var path of paths) {
            var value = $.NSString.stringWithContentsOfFileEncodingError($(path + '/settings.json'), $.NSUTF8StringEncoding, null);
            if (value) {
                try {
                    var settings = JSON.parse(value.js), reuse = false;
                    Object.keys(settings).forEach(function(key) {
                        if (key.replace(/\u017f/g, 's').toLowerCase() === 'reusewindow' && settings[key] !== null) {
                            if (typeof settings[key] !== 'boolean') throw Error('invalid reuseWindow');
                            reuse = settings[key];
                        }
                    });
                    return reuse ? 'yes' : 'no';
                }
                catch (_) { return 'no'; }
            }
        }
        return 'no';
    }
    if (mode === 'absolute') return absolute(argv[1]);
    if (mode === 'focus') {
        var app = Application.currentApplication(); app.includeStandardAdditions = true;
        var pid = Number(argv[1]);
        while (pid > 1) {
            var running = $.NSRunningApplication.runningApplicationWithProcessIdentifier(pid);
            if (running && !running.isTerminated && running.activationPolicy === 0 &&
                running.activateWithOptions($.NSApplicationActivateIgnoringOtherApps)) return 'yes';
            try { pid = Number(app.doShellScript('/bin/ps -o ppid= -p ' + pid)); }
            catch (_) { break; }
        }
        var ids = {Ghostty:'com.mitchellh.ghostty', kitty:'net.kovidgoyal.kitty', WezTerm:'com.github.wez.wezterm',
            Alacritty:'org.alacritty', iTerm:'com.googlecode.iterm2', Terminal:'com.apple.Terminal'};
        var terminals = $.NSRunningApplication.runningApplicationsWithBundleIdentifier($(ids[argv[2]]));
        if (terminals.count > 0) terminals.objectAtIndex(0).activateWithOptions($.NSApplicationActivateIgnoringOtherApps);
        return 'yes';
    }
    if (mode === 'get') {
        var h = $.LSCopyDefaultRoleHandlerForContentType($(argv[1]), $.kLSRolesAll);
        return h ? ObjC.castRefToObject(h).js : '';
    }
    if (mode === 'set') return $.LSSetDefaultRoleHandlerForContentType($(argv[1]), $.kLSRolesAll, $(argv[2]));
    var extensions = read(argv[1]).trim().split(/\s+/);
    var types = extensions.map(typesFor);
    if (mode === 'defaults' || mode === 'excluded') {
        var selected = argv.slice(2), result = [];
        types.forEach(function(resolved, i) {
            if (selected.length && selected.indexOf(extensions[i]) < 0) return;
            var safe = ['htm', 'html', 'xhtml', 'shtml'].indexOf(extensions[i]) < 0 ? resolved.filter(textType) : [];
            result = result.concat(mode === 'defaults' ? safe : (safe.length ? [] : [extensions[i]]));
        });
        return result.filter(function(t, i, all) { return all.indexOf(t) === i; }).join(mode === 'defaults' ? '\n' : ', ');
    }
    // Only genuinely undeclared extensions need a private declaration. Recheck
    // actual associations after registration before choosing defaults.
    var declarations = [];
    types = types.reduce(function(all, resolved, i) {
        var type = privateType(extensions[i]);
        if (!resolved.length || resolved.every(function(t) { return t === type; })) {
            declarations.push({ UTTypeIdentifier: type, UTTypeConformsTo: ['public.source-code'],
                UTTypeTagSpecification: { 'public.filename-extension': extensions[i] } });
            resolved = [type];
        }
        return all.concat(resolved);
    }, []);
    if (mode === 'documents') return JSON.stringify([{
        CFBundleTypeName: 'Code and text', CFBundleTypeRole: 'Editor', LSHandlerRank: 'Alternate',
        CFBundleTypeExtensions: extensions, LSItemContentTypes: types.filter(function(t, i, all) { return all.indexOf(t) === i; }).concat(['public.folder'])
    }]);
    if (mode === 'declarations') return JSON.stringify(declarations);
    throw Error('unknown services operation: ' + mode);
}
