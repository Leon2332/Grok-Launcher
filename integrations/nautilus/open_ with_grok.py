# Nautilus extension: top-level "Open with Grok" (no Scripts submenu).
# Requires host package: python3-nautilus (Debian/Ubuntu) or nautilus-python (Fedora).
# Install path: ~/.local/share/nautilus-python/extensions/open_with_grok.py
# Reload: nautilus -q

from __future__ import annotations

import subprocess
from urllib.parse import unquote, urlparse

from gi.repository import GObject, Nautilus


class OpenWithGrokMenuProvider(GObject.GObject, Nautilus.MenuProvider):
    def _paths_from_files(self, files):
        paths = []
        for f in files:
            if f.get_uri_scheme() != "file":
                continue
            path = unquote(urlparse(f.get_uri()).path)
            if f.is_directory():
                paths.append(path)
            else:
                # If a file is selected, open its parent project folder.
                parent = f.get_parent()
                if parent is not None and parent.get_uri_scheme() == "file":
                    paths.append(unquote(urlparse(parent.get_uri()).path))
        # Preserve order, drop duplicates
        seen = set()
        unique = []
        for p in paths:
            if p not in seen:
                seen.add(p)
                unique.append(p)
        return unique

    def _launch(self, _menu, files):
        for path in self._paths_from_files(files):
            try:
                subprocess.Popen(
                    ["flatpak", "run", "org.grokbuild.Launcher", path],
                    start_new_session=True,
                )
            except OSError:
                pass

    def get_file_items(self, *args):
        # Nautilus 3.x: (window, files); Nautilus 4.x: (files,)
        files = args[-1]
        if not files:
            return []

        # Show only when selection is folders (or a single file → parent).
        has_local = False
        for f in files:
            if f.get_uri_scheme() == "file":
                has_local = True
                break
        if not has_local:
            return []

        item = Nautilus.MenuItem(
            name="GrokOpenWith::OpenWithGrok",
            label="Open with Grok",
            tip="Open this folder in Grok Build",
        )
        item.connect("activate", self._launch, files)
        return [item]

    def get_background_items(self, *args):
        # Right-click empty space in a folder → open current directory.
        folder = args[-1]
        if folder is None or folder.get_uri_scheme() != "file":
            return []

        item = Nautilus.MenuItem(
            name="GrokOpenWith::OpenWithGrokBackground",
            label="Open with Grok",
            tip="Open this folder in Grok Build",
        )
        item.connect("activate", self._launch, [folder])
        return [item]
