#!/bin/bash
# Grok Build Launcher for Flatpak
# Detects a host terminal emulator and starts the host-installed Grok CLI.
# Optional: open a project directory (file-manager "Open with Grok" integration).

set -euo pipefail

INTEGRATIONS_DIR="/app/share/grok-launcher/integrations"

usage() {
    cat <<'EOF'
Usage: grok-launcher [OPTIONS] [DIRECTORY]

Launch Grok Build in a host terminal. If DIRECTORY is given, Grok starts
after changing into that folder (used by file-manager context menus).

Options:
  -h, --help                 Show this help
  --install-context-menu     Install "Open with Grok" for Nautilus, Dolphin, Nemo
  --uninstall-context-menu   Remove the context-menu integrations
  --status-context-menu      Show whether integrations are installed
EOF
}

host_home() {
    flatpak-spawn --host sh -c 'printf %s "$HOME"'
}

host_run() {
    flatpak-spawn --host "$@"
}

# Convert file:// URLs and trim; return a filesystem path.
normalize_path_arg() {
    local raw="$1"
    local path

    case "$raw" in
        file://*)
            path="${raw#file://}"
            # Decode a few common percent-encodings (file managers usually pass decoded %f).
            path="${path//%20/ }"
            path="${path//%27/\'}"
            path="${path//%28/(}"
            path="${path//%29/)}"
            ;;
        *)
            path="$raw"
            ;;
    esac

    printf '%s\n' "$path"
}

# Resolve a path to a directory on the host (directory itself, or parent of a file).
resolve_host_directory() {
    local path
    path=$(normalize_path_arg "$1")

    if host_run test -d "$path"; then
        host_run realpath "$path" 2>/dev/null || printf '%s\n' "$path"
        return 0
    fi

    if host_run test -f "$path"; then
        local parent
        parent=$(host_run dirname "$path")
        host_run realpath "$parent" 2>/dev/null || printf '%s\n' "$parent"
        return 0
    fi

    return 1
}

# Escape a string for safe inclusion inside single quotes in a generated shell script.
shell_single_quote() {
    local s="$1"
    # 'foo'bar' -> 'foo'\''bar'
    printf "%s" "${s//\'/\'\\\'\'}"
}

create_host_launch_script() {
    local work_dir="$1"
    local tmp_script
    local quoted_dir

    tmp_script=$(flatpak-spawn --host mktemp --tmpdir=/tmp grok-launch-XXXXXX.sh)
    quoted_dir=$(shell_single_quote "$work_dir")

    # Embed TARGET_DIR then append the fixed host script body (unexpanded).
    {
        printf '%s\n' '#!/bin/bash'
        printf "TARGET_DIR='%s'\n" "$quoted_dir"
        cat << 'HOSTEOF'
# Do not use set -e: stay open if failed.

# Host session PATH might lack interactive-shell additions (.bashrc).
# Grok's official installer puts the binary in ~/.grok/bin.
export PATH="${HOME}/.grok/bin:${HOME}/.local/bin:${HOME}/bin:${PATH:-/usr/bin:/bin}"

# Same 8-frame braille spinner Grok uses ({spinner:.cyan} in the CLI).
SPINNER_FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧)
SPINNER_INTERVAL=0.08

spin_countdown() {
    local seconds="${1:-3}"
    local message="${2:-Starting}"
    local i frame n=${#SPINNER_FRAMES[@]}
    local end=$((SECONDS + seconds))
    local fi=0
    while (( SECONDS < end )); do
        frame="${SPINNER_FRAMES[$((fi % n))]}"
        i=$((end - SECONDS))
        ((i < 1)) && i=1
        printf "\r\033[0;36m%s\033[0m %s in %d second(s)... " "$frame" "$message" "$i"
        sleep "$SPINNER_INTERVAL"
        fi=$((fi + 1))
    done
    printf "\r\033[K"
}

# Same spinner while a background PID is still running (for long installs).
spin_while_pid() {
    local pid="$1"
    local message="${2:-Working}"
    local frame n=${#SPINNER_FRAMES[@]} fi=0
    while kill -0 "$pid" 2>/dev/null; do
        frame="${SPINNER_FRAMES[$((fi % n))]}"
        printf "\r\033[0;36m%s\033[0m %s... " "$frame" "$message"
        sleep "$SPINNER_INTERVAL"
        fi=$((fi + 1))
    done
    printf "\r\033[K"
    wait "$pid" 2>/dev/null
    return $?
}

resolve_grok() {
    if command -v grok >/dev/null 2>&1; then
        command -v grok
        return 0
    fi
    local candidate
    for candidate in \
        "${HOME}/.grok/bin/grok" \
        "${HOME}/.local/bin/grok" \
        "${HOME}/bin/grok" \
        /usr/local/bin/grok \
        /usr/bin/grok
    do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

if [ -d "$TARGET_DIR" ]; then
    cd "$TARGET_DIR" || {
        printf "\033[1;33mCould not cd to %s; using home.\033[0m\n" "$TARGET_DIR"
        cd "$HOME" 2>/dev/null || true
    }
else
    printf "\033[1;33mDirectory not found: %s; using home.\033[0m\n" "$TARGET_DIR"
    cd "$HOME" 2>/dev/null || true
fi

GROK_BIN=""
if ! GROK_BIN=$(resolve_grok); then
    printf "\033[1;36mGrok Build CLI not found on your system.\033[0m\n"
    printf "\033[1;33mInstalling now (internet connection required)...\033[0m\n\n"

    # Run the official installer in the background; show twirly thing until it finishes.
    (
        curl -fsSL https://x.ai/cli/install.sh | bash
    ) &
    install_pid=$!

    if ! spin_while_pid "$install_pid" "Installing Grok Build"; then
        printf "\033[1;31mInstall failed.\033[0m See https://x.ai/ or run manually:\n"
        printf "  curl -fsSL https://x.ai/cli/install.sh | bash\n"
        exec "${SHELL:-/bin/bash}" -l
    fi

    export PATH="${HOME}/.grok/bin:${HOME}/.local/bin:${HOME}/bin:${PATH}"
    if ! GROK_BIN=$(resolve_grok); then
        printf "\033[1;31mInstall finished but 'grok' was still not found.\033[0m\n"
        printf "Expected something like: %s/.grok/bin/grok\n" "$HOME"
        exec "${SHELL:-/bin/bash}" -l
    fi

    printf "\033[1;32mGrok Build installed successfully.\033[0m\n"
    printf "\033[0;90mUsing: %s\033[0m\n\n" "$GROK_BIN"
    spin_countdown 3 "Starting Grok"
else
    spin_countdown 2 "Starting Grok"
fi

printf "\033[1;34mStarting Grok Build...\033[0m\n"
printf "\033[0;90m%s\033[0m\n" "$GROK_BIN"
printf "\033[0;90mWorking directory: %s\033[0m\n\n" "$(pwd)"
"$GROK_BIN"
status=$?

if [ "$status" -ne 0 ]; then
    printf "\n\033[1;33mGrok exited with status %s.\033[0m\n" "$status"
fi

# Keep an interactive login shell open after Grok exits.
exec "${SHELL:-/bin/bash}" -l
HOSTEOF
    } | flatpak-spawn --host tee "$tmp_script" > /dev/null

    flatpak-spawn --host chmod +x "$tmp_script"
    printf '%s\n' "$tmp_script"
}

TERMINALS=(
    "gnome-terminal"
    "konsole"
    "xfce4-terminal"
    "mate-terminal"
    "lxterminal"
    "alacritty"
    "kitty"
    "wezterm"
    "foot"
    "xterm"
)

launch_in_terminal() {
    local term="$1"
    local script_path="$2"

    case "$term" in
        gnome-terminal)
            flatpak-spawn --host gnome-terminal -- "$script_path"
            ;;
        konsole)
            flatpak-spawn --host konsole -e "$script_path"
            ;;
        xfce4-terminal)
            flatpak-spawn --host xfce4-terminal --command="$script_path"
            ;;
        mate-terminal)
            flatpak-spawn --host mate-terminal -e "$script_path"
            ;;
        lxterminal)
            flatpak-spawn --host lxterminal -e "$script_path"
            ;;
        alacritty)
            flatpak-spawn --host alacritty -e "$script_path"
            ;;
        kitty)
            flatpak-spawn --host kitty -e "$script_path"
            ;;
        wezterm)
            flatpak-spawn --host wezterm start -- "$script_path"
            ;;
        foot)
            flatpak-spawn --host foot -- "$script_path"
            ;;
        xterm)
            flatpak-spawn --host xterm -e "$script_path"
            ;;
        *)
            return 1
            ;;
    esac
}

install_host_file() {
    local src="$1"
    local dest="$2"
    local mode="${3:-644}"

    if [ ! -f "$src" ]; then
        echo "Missing integration source: $src" >&2
        return 1
    fi

    host_run mkdir -p "$(dirname "$dest")"
    # Stream file content from the sandbox into the host path.
    flatpak-spawn --host tee "$dest" < "$src" > /dev/null
    host_run chmod "$mode" "$dest"
    printf '  installed %s\n' "$dest"
}

remove_host_file() {
    local dest="$1"
    if host_run test -e "$dest"; then
        host_run rm -f "$dest"
        printf '  removed %s\n' "$dest"
    fi
}

context_menu_paths() {
    local hh
    hh=$(host_home)
    # Paths printed as: label|path|mode|source-relative
    cat <<EOF
kde-plasma6|${hh}/.local/share/kio/servicemenus/org.grokbuild.Launcher-open-folder.desktop|755|kde/org.grokbuild.Launcher-open-folder.desktop
kde-plasma5|${hh}/.local/share/kservices5/ServiceMenus/org.grokbuild.Launcher-open-folder.desktop|755|kde/org.grokbuild.Launcher-open-folder.desktop
nemo|${hh}/.local/share/nemo/actions/open-with-grok.nemo_action|644|nemo/open-with-grok.nemo_action
nautilus|${hh}/.local/share/nautilus-python/extensions/open_with_grok.py|644|nautilus/open_with_grok.py
EOF
}

# Legacy Nautilus Scripts entry (sub-menu) — remove on install/uninstall.
legacy_nautilus_script_path() {
    printf '%s\n' "$(host_home)/.local/share/nautilus/scripts/Open with Grok"
}

host_has_nautilus_python() {
    # python3-nautilus / nautilus-python provides the Nautilus GI typelib for extensions.
    if host_run sh -c 'python3 -c "import gi; gi.require_version(\"Nautilus\", \"4.0\"); from gi.repository import Nautilus" 2>/dev/null'; then
        return 0
    fi
    if host_run sh -c 'python3 -c "import gi; gi.require_version(\"Nautilus\", \"3.0\"); from gi.repository import Nautilus" 2>/dev/null'; then
        return 0
    fi
    # Package present even if import check is awkward in minimal envs
    if host_run sh -c 'command -v dpkg >/dev/null && dpkg -s python3-nautilus 2>/dev/null | grep -q "^Status: install ok"'; then
        return 0
    fi
    if host_run sh -c 'command -v rpm >/dev/null && rpm -q python3-nautilus nautilus-python 2>/dev/null | grep -qv "not installed"'; then
        return 0
    fi
    return 1
}

install_context_menu() {
    echo "Installing file-manager context menu integrations..."
    if [ ! -d "$INTEGRATIONS_DIR" ]; then
        echo "Error: integration files not found at $INTEGRATIONS_DIR" >&2
        echo "Rebuild/reinstall the Flatpak so integrations are packaged." >&2
        exit 1
    fi

    # Drop the old Scripts-submenu entry if present.
    remove_host_file "$(legacy_nautilus_script_path)"

    local label dest mode rel
    while IFS='|' read -r label dest mode rel; do
        [ -n "$label" ] || continue
        install_host_file "$INTEGRATIONS_DIR/$rel" "$dest" "$mode"
    done < <(context_menu_paths)

    if ! host_has_nautilus_python; then
        cat <<'EOF' >&2

Note (GNOME / Nautilus): top-level "Open with Grok" needs python3-nautilus.
  Debian/Ubuntu:  sudo apt install python3-nautilus
  Fedora:         sudo dnf install nautilus-python
  Arch:           sudo pacman -S nautilus-python
Then run: nautilus -q
EOF
    fi

    cat <<'EOF'

Done. "Open with Grok" should appear as a top-level item after:

  • GNOME (Nautilus): right-click a folder → Open with Grok
    (requires python3-nautilus; restart with: nautilus -q)
  • KDE Plasma (Dolphin): right-click a folder → Open with Grok
  • Cinnamon (Nemo): right-click a folder → Open with Grok
    (nemo -q if needed)

  COSMIC Files does not yet support custom context-menu actions.
  Use Open With (if offered) or: flatpak run org.grokbuild.Launcher /path/to/project

Also available where the desktop entry is exported:
  right-click folder → Open With → Grok
EOF
}

uninstall_context_menu() {
    echo "Removing file-manager context menu integrations..."
    local label dest mode rel
    while IFS='|' read -r label dest mode rel; do
        [ -n "$label" ] || continue
        remove_host_file "$dest"
    done < <(context_menu_paths)
    remove_host_file "$(legacy_nautilus_script_path)"
    echo "Done."
}

status_context_menu() {
    echo "Context menu integration status:"
    local label dest mode rel
    while IFS='|' read -r label dest mode rel; do
        [ -n "$label" ] || continue
        if host_run test -e "$dest"; then
            printf '  [OK]  %-12s %s\n' "$label" "$dest"
        else
            printf '  [--]  %-12s %s\n' "$label" "$dest"
        fi
    done < <(context_menu_paths)
}

# --- CLI -------------------------------------------------------------------

WORK_DIR=""
MODE="launch"

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --install-context-menu)
            MODE="install-cm"
            shift
            ;;
        --uninstall-context-menu)
            MODE="uninstall-cm"
            shift
            ;;
        --status-context-menu)
            MODE="status-cm"
            shift
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            break
            ;;
    esac
done

case "$MODE" in
    install-cm)
        install_context_menu
        exit 0
        ;;
    uninstall-cm)
        uninstall_context_menu
        exit 0
        ;;
    status-cm)
        status_context_menu
        exit 0
        ;;
esac

# Remaining args: optional directory (or file → parent dir).
# Desktop Exec=%u may pass an empty argument when launched from the app menu.
if [ $# -gt 0 ] && [ -n "${1:-}" ]; then
    if resolved=$(resolve_host_directory "$1"); then
        WORK_DIR="$resolved"
    else
        echo "Warning: not a valid path on host: $1 (starting in home)" >&2
        WORK_DIR=$(host_home)
    fi
else
    WORK_DIR=$(host_home)
fi

echo "Preparing Grok Build launcher..."
echo "Project directory: $WORK_DIR"
SCRIPT_PATH=$(create_host_launch_script "$WORK_DIR" | tail -n1)

for term in "${TERMINALS[@]}"; do
    if flatpak-spawn --host sh -c "command -v $term >/dev/null 2>&1"; then
        echo "Launching Grok Build using $term..."
        if launch_in_terminal "$term" "$SCRIPT_PATH"; then
            exit 0
        fi
        echo "Warning: failed to start $term, trying next..." >&2
    fi
done

echo "Error: Could not find a supported terminal emulator." >&2
echo "Please install one (e.g. gnome-terminal, konsole, alacritty, kitty) or run 'grok' manually." >&2
echo "" >&2
echo "Grok is already installed if you have: ~/.grok/bin/grok" >&2

flatpak-spawn --host notify-send -u normal -i dialog-information \
    "Grok Build" "No supported terminal found. Run 'grok' from a terminal instead." 2>/dev/null || true

exit 1
