// Shared LaunchServices bridge. All CFString arguments must be Objective-C strings.
ObjC.import('CoreServices');
ObjC.import('Foundation');
ObjC.import('AppKit');
function read(path) {
    var value = $.NSString.stringWithContentsOfFileEncodingError($(path), $.NSUTF8StringEncoding, null);
    return value ? value.js : '';
}
function typeFor(ext) {
    // These extensions have unrelated video, Word and archive registrations.
    var unsafe = ['public.mpeg-2-transport-stream', 'com.microsoft.word.dot', 'cx.c3.pp-archive'];
    for (var parent of ['public.source-code', 'public.text']) {
        var refs = $.UTTypeCreateAllIdentifiersForTag($.kUTTagClassFilenameExtension, $(ext), $(parent));
        var types = refs ? ObjC.deepUnwrap(ObjC.castRefToObject(refs)) : [];
        for (var type of types) {
            if (!/^dyn\./.test(type) && unsafe.indexOf(type) < 0 &&
                ['public.text', 'public.source-code', 'public.data', 'public.content', 'public.item',
                 'public.plain-text', 'public.utf8-plain-text', 'public.utf16-plain-text'].indexOf(type) < 0 &&
                (['public.html', 'public.xhtml'].indexOf(type) < 0 || ['htm', 'html', 'xhtml', 'shtml'].indexOf(ext) >= 0)) return type;
        }
    }
    return 'io.github.simonocampo1.tttlauncher.code.' + ext.replace(/\+/g, 'plus');
}
function run(argv) {
    var mode = argv[0];
    if (mode === 'reuse') {
        try { return JSON.parse(read(argv[1] + '/settings.json')).reuseWindow === true ? 'yes' : 'no'; }
        catch (_) { return 'no'; }
    }
    if (mode === 'absolute') return $(argv[1]).stringByStandardizingPath.js;
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
    if (mode === 'defaults') {
        var selected = argv.slice(2);
        return types.filter(function(t, i) {
            return ['htm', 'html', 'xhtml', 'shtml'].indexOf(extensions[i]) < 0 &&
                (!selected.length || selected.indexOf(extensions[i]) >= 0);
        }).filter(function(t, i, all) { return all.indexOf(t) === i; }).join('\n');
    }
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
