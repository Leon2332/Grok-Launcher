#!/bin/bash
# Grok Build Launcher for Flatpak
# Icon click → host terminal menu (Launch / Diagnostics / Source code).
# Directory arg (file-manager "Open with Grok") → launch Grok in that folder.

set -euo pipefail

INTEGRATIONS_DIR="/app/share/grok-launcher/integrations"
VERSION="0.9.3"
SOURCE_URL="https://github.com/Leon2332/Grok-Launcher"

usage() {
    cat <<'EOF'
Usage: grok-launcher [OPTIONS] [DIRECTORY]

With no DIRECTORY: open a host terminal with the Grok Launcher menu.
With DIRECTORY: launch Grok Build in that folder (file-manager context menu).

Options:
  -h, --help                 Show this help
  --menu                     Force the launcher menu (ignore DIRECTORY)
  --launch                   Launch Grok immediately (skip menu)
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
    printf "%s" "${s//\'/\'\\\'\'}"
}

# ---------------------------------------------------------------------------
# Host session script (runs inside the user's terminal emulator)
# ---------------------------------------------------------------------------
# MODE: menu | direct
# TARGET_DIR: working directory for Grok when launching
# LAUNCHER_VERSION, SOURCE_URL: display / open source
create_host_session_script() {
    local mode="$1"
    local work_dir="$2"
    local tmp_script
    local quoted_dir quoted_version quoted_source

    tmp_script=$(flatpak-spawn --host mktemp --tmpdir=/tmp grok-launch-XXXXXX.sh)
    quoted_dir=$(shell_single_quote "$work_dir")
    quoted_version=$(shell_single_quote "$VERSION")
    quoted_source=$(shell_single_quote "$SOURCE_URL")

    {
        printf '%s\n' '#!/bin/bash'
        printf "SESSION_MODE='%s'\n" "$(shell_single_quote "$mode")"
        printf "TARGET_DIR='%s'\n" "$quoted_dir"
        printf "LAUNCHER_VERSION='%s'\n" "$quoted_version"
        printf "SOURCE_URL='%s'\n" "$quoted_source"
        cat << 'HOSTEOF'
# Host-side Grok Launcher session. Do not use set -e: menus stay open on errors.

export PATH="${HOME}/.grok/bin:${HOME}/.local/bin:${HOME}/bin:${PATH:-/usr/bin:/bin}"

# --- colours (Grok-style: white / grey / orange) ----------------------------
C_RESET=$'\033[0m'
C_ORANGE=$'\033[38;2;245;166;35m'
C_WHITE=$'\033[97m'
C_GREY=$'\033[38;2;140;140;140m'
C_DIM=$'\033[90m'
C_CYAN=$'\033[0;36m'
C_YELLOW=$'\033[1;33m'
C_RED=$'\033[1;31m'
C_GREEN=$'\033[1;32m'
C_BLUE=$'\033[1;34m'

SPINNER_FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧)
SPINNER_INTERVAL=0.08
# Orange square as a foreground glyph (not full-cell background — avoids solid bars
# when rows stack). Prefer small square (U+25AA, width 1) over ■ (ambiguous width).
SQUARE="${C_ORANGE}▪${C_RESET}"
# Logo bounding box: "▪ ▪" = 1+1+1
LOGO_W=3
# Menu selection: "▪ " + label
MENU_MARK_W=2

# Diagnostics list: name + leader dots + status, total fixed width.
# Status is right-aligned to the end of the line (design mockup).
# Dots fill only the gap between name and status text (never inside status).
DIAG_WIDTH=48

# ---------------------------------------------------------------------------
cleanup_ui() {
    tput cnorm 2>/dev/null || true
    stty sane 2>/dev/null || true
}
trap cleanup_ui EXIT INT TERM

clear_screen() {
    printf '\033[2J\033[H'
}

hide_cursor() {
    tput civis 2>/dev/null || true
}

show_cursor() {
    tput cnorm 2>/dev/null || true
}

# Terminal size (fallback when tput is unavailable)
term_cols() {
    local c
    c=$(tput cols 2>/dev/null) || c="${COLUMNS:-80}"
    case "$c" in
        ''|*[!0-9]*) c=80 ;;
    esac
    [ "$c" -lt 20 ] && c=20
    printf '%s\n' "$c"
}

term_rows() {
    local r
    r=$(tput lines 2>/dev/null) || r="${LINES:-24}"
    case "$r" in
        ''|*[!0-9]*) r=24 ;;
    esac
    [ "$r" -lt 10 ] && r=10
    printf '%s\n' "$r"
}

# Print leading spaces so a block of visible width $1 is horizontally centered
center_pad() {
    local vis_w="$1"
    local cols pad
    cols=$(term_cols)
    pad=$(( (cols - vis_w) / 2 ))
    [ "$pad" -lt 0 ] && pad=0
    printf '%*s' "$pad" ''
}

# Vertical top padding so ~content_h lines sit in the middle of the screen
vcenter_pad() {
    local content_h="$1"
    local rows pad
    rows=$(term_rows)
    pad=$(( (rows - content_h) / 2 ))
    [ "$pad" -lt 1 ] && pad=1
    local i
    for ((i = 0; i < pad; i++)); do
        printf '\n'
    done
}

# Visible width of home menu items block (square + space + longest label)
menu_items_width() {
    local max=0 item w
    for item in "$@"; do
        w=$((MENU_MARK_W + ${#item}))
        [ "$w" -gt "$max" ] && max=$w
    done
    printf '%s\n' "$max"
}

# Read one key: prints up|down|enter|esc|quit|other
read_key() {
    local k rest
    # shellcheck disable=SC2162
    IFS= read -rsn1 k || return 1
    case "$k" in
        $'\x1b')
            # Arrow keys: ESC [ A/B  — also handle lone ESC
            # shellcheck disable=SC2162
            if IFS= read -rsn1 -t 0.05 rest; then
                if [ "$rest" = "[" ]; then
                    # shellcheck disable=SC2162
                    IFS= read -rsn1 -t 0.05 rest || true
                    case "$rest" in
                        A) printf 'up\n'; return 0 ;;
                        B) printf 'down\n'; return 0 ;;
                        *) printf 'other\n'; return 0 ;;
                    esac
                fi
            fi
            printf 'esc\n'
            ;;
        ''|$'\n'|$'\r')
            printf 'enter\n'
            ;;
        j|J)
            printf 'down\n'
            ;;
        k|K)
            printf 'up\n'
            ;;
        q|Q)
            printf 'quit\n'
            ;;
        *)
            printf 'other\n'
            ;;
    esac
}

# Print a single centered line: visible width $1, then format + args
print_centered() {
    local vis_w="$1"
    shift
    center_pad "$vis_w"
    printf "$@"
}

# Logo centered on its bounding box (LOGO_W). Top square sits in the left
# column of that box (matches the icon "b" shape).
draw_logo() {
    local pad
    pad=$(center_pad "$LOGO_W")
    printf '%s%s\n' "$pad" "$SQUARE"
    printf '%s%s %s\n' "$pad" "$SQUARE" "$SQUARE"
    printf '%s%s %s\n' "$pad" "$SQUARE" "$SQUARE"
    printf '%s%s %s\n' "$pad" "$SQUARE" "$SQUARE"
    printf '\n'
}

draw_title() {
    # Visible: "Grok Launcher " + version — centered independently of the logo
    local vis=$((13 + 1 + ${#LAUNCHER_VERSION}))
    print_centered "$vis" '%sGrok Launcher%s %s%s%s\n' \
        "$C_WHITE" "$C_RESET" "$C_GREY" "$LAUNCHER_VERSION" "$C_RESET"
    printf '\n\n'
}

# Menu items: one left-aligned block, centered as a group
draw_menu_items() {
    local selected="$1"
    shift
    local block_w pad i=0 item
    block_w=$(menu_items_width "$@")
    pad=$(center_pad "$block_w")
    for item in "$@"; do
        if [ "$i" -eq "$selected" ]; then
            printf '%s%s %s%s%s\n' "$pad" "$SQUARE" "$C_WHITE" "$item" "$C_RESET"
        else
            # MENU_MARK_W spaces so unselected text lines up under the label
            printf '%s%*s%s%s%s\n' "$pad" "$MENU_MARK_W" '' "$C_WHITE" "$item" "$C_RESET"
        fi
        i=$((i + 1))
    done
    printf '\n'
}

# Vertical centering for the home screen
prepare_home_layout() {
    # logo 4 + blank 1 + title 1 + blanks 2 + items n + blank 1
    local content_h=$((4 + 1 + 1 + 2 + $# + 1))
    vcenter_pad "$content_h"
}

# ---------------------------------------------------------------------------
# Detect DE / WM and list applicable diagnostic checks
# Each line: id|label
# ---------------------------------------------------------------------------
detect_desktop_family() {
    local xdg session de
    xdg=$(printf '%s' "${XDG_CURRENT_DESKTOP:-}" | tr '[:upper:]' '[:lower:]')
    session=$(printf '%s' "${DESKTOP_SESSION:-}" | tr '[:upper:]' '[:lower:]')
    de=$(printf '%s' "${XDG_SESSION_DESKTOP:-}" | tr '[:upper:]' '[:lower:]')

    # Prefer XDG_CURRENT_DESKTOP (can be "ubuntu:GNOME")
    case "$xdg" in
        *gnome*|*ubuntu*)
            printf 'gnome\n'; return 0
            ;;
        *kde*|*plasma*)
            printf 'kde\n'; return 0
            ;;
        *cinnamon*|*x-cinnamon*)
            printf 'cinnamon\n'; return 0
            ;;
        *cosmic*)
            printf 'cosmic\n'; return 0
            ;;
        *xfce*)
            printf 'xfce\n'; return 0
            ;;
        *mate*)
            printf 'mate\n'; return 0
            ;;
        *lxqt*|*lxde*)
            printf 'lxqt\n'; return 0
            ;;
        *hyprland*|*sway*|*i3*|*bspwm*|*awesome*)
            printf 'wl_wm\n'; return 0
            ;;
    esac

    case "$session$de" in
        *gnome*) printf 'gnome\n'; return 0 ;;
        *plasma*|*kde*) printf 'kde\n'; return 0 ;;
        *cinnamon*) printf 'cinnamon\n'; return 0 ;;
        *cosmic*) printf 'cosmic\n'; return 0 ;;
    esac

    # Fallbacks from running processes / binaries
    if command -v gnome-shell >/dev/null 2>&1 && pgrep -x gnome-shell >/dev/null 2>&1; then
        printf 'gnome\n'; return 0
    fi
    if command -v plasmashell >/dev/null 2>&1 && pgrep -x plasmashell >/dev/null 2>&1; then
        printf 'kde\n'; return 0
    fi
    if command -v nemo >/dev/null 2>&1 && pgrep -x nemo >/dev/null 2>&1; then
        printf 'cinnamon\n'; return 0
    fi

    printf 'generic\n'
}

# Prints check lines: id|label  (only those applicable to this DE)
diagnostic_checks_for_de() {
    local family="$1"
    # Always check Grok Build CLI
    printf 'grok|Grok Build\n'

    case "$family" in
        gnome)
            printf 'context-menu|context-menu\n'
            printf 'python3-nautilus|python3-nautilus\n'
            ;;
        kde)
            printf 'context-menu|context-menu\n'
            ;;
        cinnamon)
            printf 'context-menu|context-menu\n'
            ;;
        cosmic|xfce|mate|lxqt|wl_wm|generic)
            # No first-class file-manager integration for these yet
            ;;
    esac
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

check_grok_installed() {
    resolve_grok >/dev/null 2>&1
}

check_context_menu_installed() {
    local family="$1"
    case "$family" in
        gnome)
            [ -f "${HOME}/.local/share/nautilus-python/extensions/open_with_grok.py" ]
            ;;
        kde)
            [ -f "${HOME}/.local/share/kio/servicemenus/org.grokbuild.Launcher-open-folder.desktop" ] \
                || [ -f "${HOME}/.local/share/kservices5/ServiceMenus/org.grokbuild.Launcher-open-folder.desktop" ]
            ;;
        cinnamon)
            [ -f "${HOME}/.local/share/nemo/actions/open-with-grok.nemo_action" ]
            ;;
        *)
            return 1
            ;;
    esac
}

check_python3_nautilus() {
    if python3 -c 'import gi; gi.require_version("Nautilus", "4.0"); from gi.repository import Nautilus' 2>/dev/null; then
        return 0
    fi
    if python3 -c 'import gi; gi.require_version("Nautilus", "3.0"); from gi.repository import Nautilus' 2>/dev/null; then
        return 0
    fi
    if command -v dpkg >/dev/null 2>&1 && dpkg -s python3-nautilus 2>/dev/null | grep -q '^Status: install ok'; then
        return 0
    fi
    if command -v rpm >/dev/null 2>&1; then
        if rpm -q python3-nautilus >/dev/null 2>&1 || rpm -q nautilus-python >/dev/null 2>&1; then
            return 0
        fi
    fi
    if command -v pacman >/dev/null 2>&1 && pacman -Q nautilus-python >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

run_check() {
    local id="$1"
    local family="$2"
    case "$id" in
        grok) check_grok_installed ;;
        context-menu) check_context_menu_installed "$family" ;;
        python3-nautilus) check_python3_nautilus ;;
        *) return 1 ;;
    esac
}

# Ensure DIAG_WIDTH fits longest name + min dots + longest status for this DE
ensure_diag_width() {
    local family="$1"
    local max_label=0 id label need
    while IFS='|' read -r id label; do
        [ -n "$id" ] || continue
        [ "${#label}" -gt "$max_label" ] && max_label=${#label}
    done < <(diagnostic_checks_for_de "$family")
    # longest status is "NOT INSTALLED" (13); keep at least ~12 leader dots on longest name
    need=$((max_label + 12 + 13))
    if [ "$need" -gt "$DIAG_WIDTH" ]; then
        DIAG_WIDTH=$need
    fi
}

# Print: pad + name + dots + status
# dots = DIAG_WIDTH - len(name) - len(status)  so status is right-aligned
# Status text itself is never dotted.
print_diag_line() {
    local label="$1"
    local status="$2"
    local color="$3"
    local dots=$((DIAG_WIDTH - ${#label} - ${#status}))
    [ "$dots" -lt 1 ] && dots=1
    printf '%s%s' "$DIAG_PAD" "$label"
    local i
    for ((i = 0; i < dots; i++)); do
        printf '%s' '.'
    done
    printf '%s%s%s' "$color" "$status" "$C_RESET"
}

# Spinner while checking: name + dots + spinner at the status end
spin_while_pid() {
    local pid="$1"
    local frame n=${#SPINNER_FRAMES[@]} fi=0
    while kill -0 "$pid" 2>/dev/null; do
        frame="${SPINNER_FRAMES[$((fi % n))]}"
        printf '\r'
        print_diag_line "$SPIN_LABEL" "$frame" "$C_ORANGE"
        printf '\033[K'
        sleep "$SPINNER_INTERVAL"
        fi=$((fi + 1))
    done
    wait "$pid" 2>/dev/null
    return $?
}

# Run one diagnostic row: spinner then INSTALLED / NOT INSTALLED
# Echoes "ok" or "missing" on stdout's last... actually sets DIAG_ROW_OK=0/1
diag_row() {
    local id="$1"
    local label="$2"
    local family="$3"
    local ok=1

    SPIN_LABEL="$label"
    # Run check in background so spinner can animate (checks are often instant)
    (
        sleep 0.35
        run_check "$id" "$family"
    ) &
    local pid=$!
    if spin_while_pid "$pid"; then
        ok=0
    else
        ok=1
    fi

    printf '\r'
    if [ "$ok" -eq 0 ]; then
        print_diag_line "$label" "INSTALLED" "$C_WHITE"
        DIAG_ROW_OK=1
    else
        print_diag_line "$label" "NOT INSTALLED" "$C_ORANGE"
        DIAG_ROW_OK=0
    fi
    printf '\033[K\n'
}

# Print a stored result line (no re-check) — used when redrawing the actions menu
print_diag_result_line() {
    local label="$1"
    local ok="$2"
    if [ "$ok" = "1" ]; then
        print_diag_line "$label" "INSTALLED" "$C_WHITE"
    else
        print_diag_line "$label" "NOT INSTALLED" "$C_ORANGE"
    fi
    printf '\n'
}

draw_diag_rule() {
    # Horizontal rule the full width of the dependency list
    local i
    printf '%s' "$DIAG_PAD"
    for ((i = 0; i < DIAG_WIDTH; i++)); do
        printf '%s' '─'
    done
    printf '\n'
}

# Build the initial prompt for "Ask Grok to fix this"
build_fix_deps_prompt() {
    local family="$1"
    shift
    # remaining args: missing labels
    local missing_list="" label
    for label in "$@"; do
        missing_list="${missing_list}
- ${label}"
    done

    cat <<EOF
Grok Launcher (Flatpak app id: org.grokbuild.Launcher) Diagnostics reports missing dependencies on this Linux system.

Desktop environment family: ${family}

Missing dependencies:${missing_list}

Please install and configure only what is missing so the launcher works fully. Guidance:

- Grok Build: official install is \`curl -fsSL https://x.ai/cli/install.sh | bash\` (binary usually at ~/.grok/bin/grok).
- context-menu (file manager "Open with Grok"): run \`flatpak run org.grokbuild.Launcher --install-context-menu\`. On GNOME you may need to restart Files (\`nautilus -q\`); on Cinnamon \`nemo -q\`.
- python3-nautilus (GNOME top-level context menu): install host package \`python3-nautilus\` (Debian/Ubuntu) or \`nautilus-python\` (Fedora/Arch), then \`nautilus -q\`.

Detect the distro/package manager, use appropriate commands, and briefly confirm what you did. Do not change unrelated system settings.
EOF
}

# Draw diagnostics chrome + stored results + action items (selected index)
# Globals: DIAG_RES_LABELS[], DIAG_RES_OK[], DIAG_N, DIAG_PAD, DIAG_WIDTH
draw_diagnostics_frame() {
    local selected="$1"
    shift
    local actions=("$@")
    local i item

    clear_screen
    hide_cursor
    # title + blanks + Dependencies + rule + blank + checks + blanks + actions
    local content_h=$((1 + 2 + 1 + 1 + 1 + DIAG_N + 3 + ${#actions[@]}))
    vcenter_pad "$content_h"

    print_centered 11 '%sDiagnostics%s\n' "$C_ORANGE" "$C_RESET"
    printf '\n\n'

    printf '%s%sDependencies%s\n' "$DIAG_PAD" "$C_WHITE" "$C_RESET"
    draw_diag_rule
    printf '\n'

    for ((i = 0; i < DIAG_N; i++)); do
        print_diag_result_line "${DIAG_RES_LABELS[$i]}" "${DIAG_RES_OK[$i]}"
    done

    printf '\n\n\n'
    i=0
    for item in "${actions[@]}"; do
        if [ "$i" -eq "$selected" ]; then
            printf '%s%s %s%s%s\n' "$DIAG_PAD" "$SQUARE" "$C_WHITE" "$item" "$C_RESET"
        else
            printf '%s%*s%s%s%s\n' "$DIAG_PAD" "$MENU_MARK_W" '' "$C_WHITE" "$item" "$C_RESET"
        fi
        i=$((i + 1))
    done
    printf '\n'
}

show_diagnostics() {
    local family n_checks=0 id label
    local -a missing_labels=()
    family=$(detect_desktop_family)

    DIAG_N=0
    DIAG_RES_LABELS=()
    DIAG_RES_OK=()
    missing_labels=()

    while IFS='|' read -r id label; do
        [ -n "$id" ] || continue
        n_checks=$((n_checks + 1))
    done < <(diagnostic_checks_for_de "$family")

    ensure_diag_width "$family"
    DIAG_PAD=$(center_pad "$DIAG_WIDTH")

    # First pass: animated checks (title + list only; actions drawn after)
    clear_screen
    hide_cursor
    vcenter_pad $((1 + 2 + 1 + 1 + 1 + n_checks + 3 + 2))

    print_centered 11 '%sDiagnostics%s\n' "$C_ORANGE" "$C_RESET"
    printf '\n\n'
    printf '%s%sDependencies%s\n' "$DIAG_PAD" "$C_WHITE" "$C_RESET"
    draw_diag_rule
    printf '\n'

    while IFS='|' read -r id label; do
        [ -n "$id" ] || continue
        diag_row "$id" "$label" "$family"
        DIAG_RES_LABELS[DIAG_N]="$label"
        DIAG_RES_OK[DIAG_N]="$DIAG_ROW_OK"
        if [ "$DIAG_ROW_OK" = "0" ]; then
            missing_labels+=("$label")
        fi
        DIAG_N=$((DIAG_N + 1))
    done < <(diagnostic_checks_for_de "$family")

    # Actions: offer fix only when something is missing
    local -a actions=()
    if [ "${#missing_labels[@]}" -gt 0 ]; then
        actions+=("Ask Grok to fix this")
    fi
    actions+=("Back")

    local sel=0 n=${#actions[@]} key
    # Redraw full frame with actions so layout matches
    while true; do
        draw_diagnostics_frame "$sel" "${actions[@]}"

        stty -echo -icanon min 1 time 0 2>/dev/null || stty -echo 2>/dev/null || true
        key=$(read_key) || key=quit
        stty sane 2>/dev/null || true

        case "$key" in
            up)
                sel=$(( (sel - 1 + n) % n ))
                ;;
            down)
                sel=$(( (sel + 1) % n ))
                ;;
            quit|esc)
                break
                ;;
            enter)
                case "${actions[$sel]}" in
                    "Ask Grok to fix this")
                        GROK_PROMPT=$(build_fix_deps_prompt "$family" "${missing_labels[@]}")
                        export GROK_PROMPT
                        launch_grok
                        return
                        ;;
                    "Back"|*)
                        break
                        ;;
                esac
                ;;
        esac
    done
}

open_source_code() {
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$SOURCE_URL" >/dev/null 2>&1 &
    elif command -v gio >/dev/null 2>&1; then
        gio open "$SOURCE_URL" >/dev/null 2>&1 &
    else
        clear_screen
        printf '\n  %sOpen in your browser:%s\n  %s\n\n' "$C_WHITE" "$C_RESET" "$SOURCE_URL"
        printf '  Press Enter to continue...'
        # shellcheck disable=SC2162
        read -r _
    fi
}

# ---------------------------------------------------------------------------
# Launch Grok Build (install if missing) in TARGET_DIR
# ---------------------------------------------------------------------------
spin_while_pid_msg() {
    local pid="$1"
    local message="${2:-Working}"
    local frame n=${#SPINNER_FRAMES[@]} fi=0
    while kill -0 "$pid" 2>/dev/null; do
        frame="${SPINNER_FRAMES[$((fi % n))]}"
        printf '\r%s%s%s %s... ' "$C_CYAN" "$frame" "$C_RESET" "$message"
        sleep "$SPINNER_INTERVAL"
        fi=$((fi + 1))
    done
    printf '\r\033[K'
    wait "$pid" 2>/dev/null
    return $?
}

launch_grok() {
    cleanup_ui
    show_cursor
    clear_screen

    if [ -d "$TARGET_DIR" ]; then
        cd "$TARGET_DIR" || {
            printf '%sCould not cd to %s; using home.%s\n' "$C_YELLOW" "$TARGET_DIR" "$C_RESET"
            cd "$HOME" 2>/dev/null || true
        }
    else
        printf '%sDirectory not found: %s; using home.%s\n' "$C_YELLOW" "$TARGET_DIR" "$C_RESET"
        cd "$HOME" 2>/dev/null || true
    fi

    local GROK_BIN=""
    if ! GROK_BIN=$(resolve_grok); then
        printf '%sGrok Build CLI not found on your system.%s\n' "$C_CYAN" "$C_RESET"
        printf '%sInstalling now (internet connection required)...%s\n\n' "$C_YELLOW" "$C_RESET"

        (
            curl -fsSL https://x.ai/cli/install.sh | bash
        ) &
        local install_pid=$!

        if ! spin_while_pid_msg "$install_pid" "Installing Grok Build"; then
            printf '%sInstall failed.%s See https://x.ai/ or run manually:\n' "$C_RED" "$C_RESET"
            printf '  curl -fsSL https://x.ai/cli/install.sh | bash\n'
            exec "${SHELL:-/bin/bash}" -l
        fi

        export PATH="${HOME}/.grok/bin:${HOME}/.local/bin:${HOME}/bin:${PATH}"
        if ! GROK_BIN=$(resolve_grok); then
            printf '%sInstall finished but '\''grok'\'' was still not found.%s\n' "$C_RED" "$C_RESET"
            printf 'Expected something like: %s/.grok/bin/grok\n' "$HOME"
            exec "${SHELL:-/bin/bash}" -l
        fi

        printf '%sGrok Build installed successfully.%s\n' "$C_GREEN" "$C_RESET"
        printf '%sUsing: %s%s\n\n' "$C_DIM" "$GROK_BIN" "$C_RESET"
    fi

    printf '%sStarting Grok Build...%s\n' "$C_BLUE" "$C_RESET"
    printf '%s%s%s\n' "$C_DIM" "$GROK_BIN" "$C_RESET"
    printf '%sWorking directory: %s%s\n' "$C_DIM" "$(pwd)" "$C_RESET"
    if [ -n "${GROK_PROMPT:-}" ]; then
        printf '%sWith initial prompt (%s chars)%s\n\n' "$C_DIM" "${#GROK_PROMPT}" "$C_RESET"
        "$GROK_BIN" "$GROK_PROMPT"
    else
        printf '\n'
        "$GROK_BIN"
    fi
    local status=$?

    if [ "$status" -ne 0 ]; then
        printf '\n%sGrok exited with status %s.%s\n' "$C_YELLOW" "$status" "$C_RESET"
    fi

    exec "${SHELL:-/bin/bash}" -l
}

# ---------------------------------------------------------------------------
# Main interactive menu
# ---------------------------------------------------------------------------
run_menu() {
    local items=("Launch Grok" "Diagnostics" "Source code")
    local n=${#items[@]}
    local sel=0
    local key

    while true; do
        clear_screen
        hide_cursor
        prepare_home_layout "${items[@]}"
        draw_logo
        draw_title
        draw_menu_items "$sel" "${items[@]}"

        stty -echo -icanon min 1 time 0 2>/dev/null || stty -echo 2>/dev/null || true
        key=$(read_key) || key=quit
        stty sane 2>/dev/null || true

        case "$key" in
            up)
                sel=$(( (sel - 1 + n) % n ))
                ;;
            down)
                sel=$(( (sel + 1) % n ))
                ;;
            quit|esc)
                cleanup_ui
                clear_screen
                exit 0
                ;;
            enter)
                case "$sel" in
                    0)
                        launch_grok
                        return
                        ;;
                    1)
                        show_diagnostics
                        ;;
                    2)
                        open_source_code
                        ;;
                esac
                ;;
        esac
    done
}

# --- entry -----------------------------------------------------------------
case "${SESSION_MODE:-menu}" in
    direct)
        launch_grok
        ;;
    menu|*)
        run_menu
        ;;
esac
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

open_host_session() {
    local mode="$1"
    local work_dir="$2"
    local script_path

    script_path=$(create_host_session_script "$mode" "$work_dir" | tail -n1)

    for term in "${TERMINALS[@]}"; do
        if flatpak-spawn --host sh -c "command -v $term >/dev/null 2>&1"; then
            echo "Opening Grok Launcher in $term..."
            if launch_in_terminal "$term" "$script_path"; then
                exit 0
            fi
            echo "Warning: failed to start $term, trying next..." >&2
        fi
    done

    echo "Error: Could not find a supported terminal emulator." >&2
    echo "Please install one (e.g. gnome-terminal, konsole, alacritty, kitty)." >&2

    flatpak-spawn --host notify-send -u normal -i dialog-information \
        "Grok Launcher" "No supported terminal found. Install a terminal emulator and try again." 2>/dev/null || true

    exit 1
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
    cat <<EOF
kde-plasma6|${hh}/.local/share/kio/servicemenus/org.grokbuild.Launcher-open-folder.desktop|755|kde/org.grokbuild.Launcher-open-folder.desktop
kde-plasma5|${hh}/.local/share/kservices5/ServiceMenus/org.grokbuild.Launcher-open-folder.desktop|755|kde/org.grokbuild.Launcher-open-folder.desktop
nemo|${hh}/.local/share/nemo/actions/open-with-grok.nemo_action|644|nemo/open-with-grok.nemo_action
nautilus|${hh}/.local/share/nautilus-python/extensions/open_with_grok.py|644|nautilus/open_with_grok.py
EOF
}

legacy_nautilus_script_path() {
    printf '%s\n' "$(host_home)/.local/share/nautilus/scripts/Open with Grok"
}

host_has_nautilus_python() {
    if host_run sh -c 'python3 -c "import gi; gi.require_version(\"Nautilus\", \"4.0\"); from gi.repository import Nautilus" 2>/dev/null'; then
        return 0
    fi
    if host_run sh -c 'python3 -c "import gi; gi.require_version(\"Nautilus\", \"3.0\"); from gi.repository import Nautilus" 2>/dev/null'; then
        return 0
    fi
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
MODE="auto"   # auto | menu | launch | install-cm | uninstall-cm | status-cm

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --menu)
            MODE="menu"
            shift
            ;;
        --launch)
            MODE="launch"
            shift
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

# auto: directory from file manager → direct launch; otherwise menu
case "$MODE" in
    menu)
        open_host_session "menu" "$WORK_DIR"
        ;;
    launch)
        open_host_session "direct" "$WORK_DIR"
        ;;
    auto)
        if [ $# -gt 0 ] && [ -n "${1:-}" ]; then
            open_host_session "direct" "$WORK_DIR"
        else
            open_host_session "menu" "$WORK_DIR"
        fi
        ;;
esac
