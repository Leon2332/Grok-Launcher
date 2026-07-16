# Grok Flatpak Launcher

A simple Flatpak wrapper that provides a desktop icon and menu entry for **Grok** (xAI's powerful terminal coding agent / Grok Build).

When launched, it:
- Opens your system's preferred terminal emulator
- Looks for an existing Grok install
- Runs the official installer if the binary is missing
- Starts the interactive Grok TUI

This makes Grok easily accessible to normal users who prefer clicking an icon over typing commands, while still using the native `grok` CLI on the host (so it has full access to your projects, git, etc.).

## Requirements (on your host system)
- Flatpak installed (`flatpak --version`)
- flatpak-builder (for building from source)
- A terminal emulator (gnome-terminal, konsole, alacritty, kitty, etc. — the launcher auto-detects most common ones)
- Internet connection for the one-time install of Grok Build

## Build & Install

```bash
cd Grok-Launcher-main/   # or your checkout directory

# Build and install for your user
flatpak-builder --user --install --force-clean build-dir org.grokbuild.Launcher.yml

# Or system-wide (requires root/sudo for some steps)
# flatpak-builder --system --install --force-clean build-dir org.grokbuild.Launcher.yml
```

After installation, you should see **Grok** in your application menu / launcher, with the official Grok icon.

You can also run it from command line:
```bash
flatpak run org.grokbuild.Launcher

# Start in a specific project directory
flatpak run org.grokbuild.Launcher /path/to/project
```

## Open with Grok (file manager context menu)

Right-click a **folder** and choose **Open with Grok** to launch Grok already `cd`'d into that directory.

<p align="center">
  <img src="docs/Screenshot%20From%202026-07-16%2022-03-16.png" alt="Right-click a folder and choose Open with Grok" width="720" />
  <br />
  <em>Right-click a project folder → Open with Grok</em>
</p>

<p align="center">
  <img src="docs/Screenshot%20From%202026-07-16%2022-04-09.png" alt="Grok Build opened in the selected project directory" width="720" />
  <br />
  <em>Grok opens in a terminal already set to that directory</em>
</p>

### Install the context menu entries

After installing the Flatpak:

```bash
flatpak run org.grokbuild.Launcher --install-context-menu
```

Or from the app menu: right-click the **Grok** launcher → **Install File Manager Integration** (on desktops that show desktop actions).

Check / remove:

```bash
flatpak run org.grokbuild.Launcher --status-context-menu
flatpak run org.grokbuild.Launcher --uninstall-context-menu
```

### Desktop environment support

<table>
  <tr>
    <th>Environment</th>
    <th>File manager</th>
    <th>How it appears</th>
  </tr>
  <tr>
    <td><strong>GNOME</strong></td>
    <td>Nautilus (Files)</td>
    <td>Top-level <strong>Open with Grok</strong> (via <code>python3-nautilus</code> extension)</td>
  </tr>
  <tr>
    <td><strong>KDE Plasma</strong></td>
    <td>Dolphin</td>
    <td>Top-level <strong>Open with Grok</strong> (service menu)</td>
  </tr>
  <tr>
    <td><strong>Cinnamon</strong></td>
    <td>Nemo</td>
    <td>Top-level <strong>Open with Grok</strong> (Nemo action)</td>
  </tr>
  <tr>
    <td><strong>COSMIC</strong></td>
    <td>COSMIC Files</td>
    <td>Custom context menus are <a href="https://github.com/pop-os/cosmic-files/issues/1445">not supported yet</a>. Use <strong>Open With → Grok</strong> if offered, or <code>flatpak run org.grokbuild.Launcher /path/to/project</code></td>
  </tr>
</table>

**GNOME note:** top-level menu items need the host package `python3-nautilus` (Debian/Ubuntu) or `nautilus-python` (Fedora/Arch). Without it, install that package, re-run `--install-context-menu`, then `nautilus -q`.

**Open With** is also registered for folders on any desktop that honors the shared desktop entry (`MimeType=inode/directory`): right-click folder → Open With → **Grok**.

You may need to restart the file manager once after installing the integrations (`nautilus -q`, `nemo -q`, or re-open Dolphin).

## Notes & Customization

- **First launch**: It will install Grok if missing. This requires internet and will show progress in the opened terminal.
- **Authentication**: On first `grok` run it opens a browser window for xAI login (SuperGrok / Premium+ required for Grok Build).
- **Project directory**: App-menu launch starts in your `$HOME`. Prefer **Open with Grok** on a project folder, or pass a path on the command line (see above).
- **Terminal preference**: The launcher tries common terminals in this order: gnome-terminal, konsole, xfce4-terminal, mate-terminal, lxterminal, alacritty, kitty, wezterm, foot, xterm.
  If your favorite terminal isn't launched, you can edit `grok-launcher.sh` and adjust the `TERMINALS` array + the `launch_in_terminal()` case.
- **Uninstall**:
  ```bash
  flatpak run org.grokbuild.Launcher --uninstall-context-menu   # optional cleanup
  flatpak uninstall org.grokbuild.Launcher
  flatpak uninstall --unused   # cleanup
  ```

## Why a Flatpak for this?

Grok is a fantastic CLI tool, but many Linux users (especially less technical ones) appreciate having a polished desktop icon that "just works". This Flatpak does exactly that without packaging the Grok binary itself (it re-uses the official host installation for maximum compatibility and access to your files).

## License / Disclaimer

Source code is licensed under the [MIT License](LICENSE.md).

This is an unofficial community launcher created for convenience. Grok and Grok Build are trademarks of xAI. The actual Grok CLI is installed from the official xAI servers.

---

Enjoy.
