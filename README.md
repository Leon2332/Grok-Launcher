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
cd org.grokbuild.Launcher/

# Build and install for your user
flatpak-builder --user --install --force-clean build-dir org.grokbuild.Launcher.yml

# Or system-wide (requires root/sudo for some steps)
# flatpak-builder --system --install --force-clean build-dir org.grokbuild.Launcher.yml
```

After installation, you should see **Grok Build** in your application menu / launcher, with the official Grok icon.

You can also run it from command line:
```bash
flatpak run org.grokbuild.Launcher
```

## Notes & Customization

- **First launch**: It will install Grok if missing. This requires internet and will show progress in the opened terminal.
- **Authentication**: On first `grok` run it opens a browser window for xAI login (SuperGrok / Premium+ required for Grok Build).
- **Project directory**: The launcher starts in your `$HOME`. `cd` into your project folder inside the terminal if `grok` expects to be run from a specific directory.
- **Terminal preference**: The launcher tries common terminals in this order: gnome-terminal, konsole, xfce4-terminal, mate-terminal, lxterminal, alacritty, kitty, wezterm, foot, xterm. 
  If your favorite terminal isn't launched, you can edit `grok-launcher.sh` and adjust the `TERMINALS` array + the `launch_in_terminal()` case.
- **Uninstall**:
  ```bash
  flatpak uninstall org.grokbuild.Launcher
  flatpak uninstall --unused   # cleanup
  ```

## Why a Flatpak for this?

Grok is a fantastic CLI tool, but many Linux users (especially less technical ones) appreciate having a polished desktop icon that "just works". This Flatpak does exactly that without packaging the Grok binary itself (it re-uses the official host installation for maximum compatibility and access to your files).

## Future ideas

Right-click folder → "Open with Grok" (context menu integration) is planned for later. Target desktop environments: GNOME, KDE Plasma, Cinnamon, and COSMIC.

## License / Disclaimer

Source code is licensed under the [MIT License](LICENSE.md).

This is an unofficial community launcher created for convenience. Grok and Grok Build are trademarks of xAI. The actual Grok CLI is installed from the official xAI servers.

---

Enjoy.
