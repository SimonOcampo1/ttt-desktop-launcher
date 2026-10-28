# ttt desktop launcher

Plugins that add [ttt](https://github.com/eugenioenko/ttt) to your desktop, one per OS. Installing the plugin installs the launcher; uninstalling it removes the launcher.

| Plugin | What it adds |
|---|---|
| `desktop-launcher-linux` | `ttt.desktop` and its icon under `$XDG_DATA_HOME` (`~/.local/share`), so ttt shows up in your app launcher and in "Open With". |
| `desktop-launcher-macos` | `~/Applications/TTT.app`, an AppleScript applet that opens ttt and the files you double-click in Finder. **Experimental:** not yet tested on a Mac. |

The launcher opens ttt in the terminal ttt was running in when you installed the plugin: kitty, WezTerm, Alacritty, Ghostty, foot or Konsole on Linux; Ghostty, kitty, WezTerm, Alacritty, iTerm or Terminal.app on macOS. On Linux, with no known terminal, the desktop picks one (`Terminal=true`).

## Install

From the **Plugins** panel, search for "Desktop Launcher". Or copy the folder for your OS into `~/.config/ttt/plugins/` and restart ttt:

```sh
git clone https://github.com/SimonOcampo1/ttt-desktop-launcher /tmp/ttt-desktop-launcher
cp -r /tmp/ttt-desktop-launcher/desktop-launcher-linux ~/.config/ttt/plugins/
```

Both plugins ask for two permissions: registering commands, and running `sh`, which runs the plugin's own `launcher.sh`.

## Commands

- **Desktop Launcher: Repair**: rewrite the launcher, for instance after moving ttt or to switch it to the terminal you are in now.
- **Desktop Launcher: Open Markdown and JSON with ttt** (macOS): make TTT.app the default for `.md` and `.json` in Finder. The previous default apps are remembered and restored when you uninstall the plugin.

## Safety

The scripts only touch files they created: `ttt.desktop` carries `X-TTT-Managed=true`, and `TTT.app` carries a `ttt-managed` marker. If you already have your own `ttt.desktop` or `TTT.app`, install fails without changing it.

## Tests

```sh
sh tests/linux.sh
sh tests/macos.sh   # stubs osacompile and plutil, runs anywhere
```
