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
        !['public.html', 'public.xhtml', 'public.image', 'public.audiovisual-content', 'public.archive'].some(function(p) {
            return conforms(type, p);
        });
}
function typeFor(ext) {
    var ref = $.UTTypeCreatePreferredIdentifierForTag($.kUTTagClassFilenameExtension, $(ext), null);
    return ref ? ObjC.castRefToObject(ref).js : '';
}
function run(argv) {
    var mode = argv[0];
    if (mode === 'reuse') {
        var paths = argv[1] ? [argv[1]] : [
            $(argv[2]).stringByResolvingSymlinksInPath.stringByDeletingLastPathComponent.js + '/config',
            $.NSHomeDirectory().js + '/.config/ttt'];
        for (var path of paths) {
            var value = $.NSString.stringWithContentsOfFileEncodingError($(path + '/settings.json'), $.NSUTF8StringEncoding, null);
            if (value) {
                try { return JSON.parse(value.js).reuseWindow === true ? 'yes' : 'no'; }
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
    var types = extensions.map(typeFor);
    if (mode === 'defaults' || mode === 'excluded') {
        var selected = argv.slice(2);
        return types.map(function(t, i) {
            var safe = t && !/^dyn\./.test(t) && ['htm', 'html', 'xhtml', 'shtml'].indexOf(extensions[i]) < 0 && textType(t);
            return (!selected.length || selected.indexOf(extensions[i]) >= 0) &&
                (mode === 'defaults' ? safe : !safe) ? (mode === 'defaults' ? t : extensions[i]) : '';
        }).filter(function(t, i, all) {
            return t && all.indexOf(t) === i;
        }).join(mode === 'defaults' ? '\n' : ', ');
    }
    // Only undeclared/dynamic extensions need a private declaration. Defaults above
    // use the actual resolver result again after bundle registration.
    types = types.map(function(t, i) { return !t || /^dyn\./.test(t) ? privateType(extensions[i]) : t; });
    if (mode === 'documents') return JSON.stringify([{
        CFBundleTypeName: 'Code and text', CFBundleTypeRole: 'Editor', LSHandlerRank: 'Alternate',
        CFBundleTypeExtensions: extensions, LSItemContentTypes: types.concat(['public.folder'])
    }]);
    if (mode === 'declarations') return JSON.stringify(types.map(function(t, i) {
        return { UTTypeIdentifier: t, UTTypeConformsTo: ['public.source-code'],
            UTTypeTagSpecification: { 'public.filename-extension': extensions[i] } };
    }).filter(function(t) { return t.UTTypeIdentifier.indexOf('io.github.simonocampo1.tttlauncher.code.') === 0; }));
    throw Error('unknown services operation: ' + mode);
}
