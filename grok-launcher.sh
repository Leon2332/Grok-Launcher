#!/bin/bash
# Grok Build Launcher for Flatpak
# Detects a host terminal emulator and starts the host-installed Grok CLI.

set -euo pipefail

create_host_launch_script() {
    local tmp_script
    tmp_script=$(flatpak-spawn --host mktemp --tmpdir=/tmp grok-launch-XXXXXX.sh)

    flatpak-spawn --host tee "$tmp_script" > /dev/null << 'HOSTEOF'
#!/bin/bash
# Do not use set -e: stay open if failed.

# Host session PATH might lack interactive-shell additions (.bashrc).
# Grok's official installer puts the binary in ~/.grok/bin.
export PATH="${HOME}/.grok/bin:${HOME}/.local/bin:${HOME}/bin:${PATH:-/usr/bin:/bin}"

#   for i in {N..1}; do for c in / - \ |; do printf "\r%c ... %d" "$c" "$i"; sleep 0.25; done; done
spin_countdown() {
    local seconds="${1:-3}"
    local message="${2:-Starting}"
    local i c
    for ((i = seconds; i >= 1; i--)); do
        for c in / - \\ \|; do
            printf "\r\033[0;36m%c\033[0m %s in %d second(s)... " "$c" "$message" "$i"
            sleep 0.25
        done
    done
    printf "\r\033[K"
}

# Do twirly thing while a background PID is still running (for long installs).
spin_while_pid() {
    local pid="$1"
    local message="${2:-Working}"
    local c frames=('/' '-' '\' '|') i=0
    while kill -0 "$pid" 2>/dev/null; do
        c="${frames[$((i % 4))]}"
        printf "\r\033[0;36m%c\033[0m %s... " "$c" "$message"
        sleep 0.25
        i=$((i + 1))
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

cd "$HOME" 2>/dev/null || true

printf "\033[1;34mStarting Grok Build...\033[0m\n"
printf "\033[0;90m%s\033[0m\n\n" "$GROK_BIN"
"$GROK_BIN"
status=$?

if [ "$status" -ne 0 ]; then
    printf "\n\033[1;33mGrok exited with status %s.\033[0m\n" "$status"
fi

# Keep an interactive login shell open after Grok exits.
exec "${SHELL:-/bin/bash}" -l
HOSTEOF

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

echo "Preparing Grok Build launcher..."
SCRIPT_PATH=$(create_host_launch_script | tail -n1)

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
