#!/usr/bin/env bash
# install.sh - Firefox-98 theme installer
#
# Monochrome-terminal safe:
#   - no ANSI color escapes, no reverse video
#   - ASCII-only output; ncurses falls back to +-| if ACS is unavailable
#   - backend: dialog (monochrome by default), else plain read(1) prompts
#   - whiptail deliberately unused: newt colors cannot be neutralised portably
#
# Usage: ./install.sh [--variant light|dark] [--yes]

set -euo pipefail

SRC_DIR="chrome"
TUI=""
VARIANT=""
ASSUME_YES=0

usage() { printf 'Usage: %s [--variant light|dark] [--yes]\n' "${0##*/}"; }

while [ "$#" -gt 0 ]; do
    case "$1" in
        --variant)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            VARIANT=$2; shift 2 ;;
        --variant=*) VARIANT=${1#*=}; shift ;;
        --yes|-y)    ASSUME_YES=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        *)           usage >&2; exit 2 ;;
    esac
done

case "$VARIANT" in
    ""|light|dark) ;;
    *) printf 'Invalid variant: %s\n' "$VARIANT" >&2; exit 2 ;;
esac

command -v dialog >/dev/null 2>&1 && TUI=dialog

clear_screen() {
    if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "$TERM" != dumb ]; then
        clear 2>/dev/null || true
    fi
}

plain_info() {
    printf '\n%s\n' "$1"
    if [ -t 0 ]; then
        printf '\nPress Enter to continue... '
        read -r _ || true
    fi
}

info() {
    if [ "$TUI" = dialog ]; then
        dialog --no-shadow --title "Firefox-98 Installer" \
               --msgbox "$1" "${2:-10}" "${3:-64}" || exit 0
    else
        plain_info "$1"
    fi
}

err() {
    if [ "$TUI" = dialog ]; then
        dialog --no-shadow --title "Error" --msgbox "$1" 9 64 || true
    else
        printf '\nError: %s\n' "$1" >&2
    fi
    exit 1
}

confirm() {
    local ans
    [ "$ASSUME_YES" -eq 1 ] && return 0
    if [ "$TUI" = dialog ]; then
        dialog --no-shadow --title "Confirm" --yesno "$1" "${2:-9}" "${3:-60}"
        return $?
    fi
    printf '\n%s [y/N] ' "$1"
    read -r ans || return 1
    case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

choose_variant() {
    local choice
    if [ "$TUI" = dialog ]; then
        choice=$(dialog --no-shadow --title "Theme Variant" \
            --menu "Select theme variant:" 12 50 2 \
            light "Light (default)" \
            dark  "Dark" \
            3>&1 1>&2 2>&3) || exit 0
        printf '%s\n' "$choice"
        return 0
    fi
    printf '\nSelect theme variant:\n'
    printf '  1) light (default)\n'
    printf '  2) dark\n'
    printf 'Choice [1]: '
    read -r choice || { printf 'light\n'; return 0; }
    case "$choice" in
        2|d|D|dark|Dark) printf 'dark\n' ;;
        *)               printf 'light\n' ;;
    esac
}

find_firefox_profile() {
    local dir
    for dir in \
        "$HOME/.mozilla/firefox"/*.default* \
        "$HOME/snap/firefox/common/.mozilla/firefox"/*.default* \
        "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"/*.default*
    do
        [ -d "$dir" ] && [ -f "$dir/prefs.js" ] && { printf '%s\n' "$dir"; return 0; }
    done
    return 1
}

clear_screen

if [ ! -d "$SRC_DIR" ]; then
    printf 'Error: %s not found. Run this script from the repository root.\n' \
        "$SRC_DIR" >&2
    exit 1
fi

if [ -z "$VARIANT" ]; then
    VARIANT=$(choose_variant) || exit 0
fi

case "$VARIANT" in
    light)
        CHROME_SRC="$SRC_DIR/userChrome.css"
        CONTENT_SRC="$SRC_DIR/userContent.css" ;;
    dark)
        CHROME_SRC="$SRC_DIR/userChrome-dark.css"
        CONTENT_SRC="$SRC_DIR/userContent-dark.css" ;;
esac

[ -f "$CHROME_SRC" ]  || err "Variant file not found: $CHROME_SRC"
[ -f "$CONTENT_SRC" ] || err "Variant file not found: $CONTENT_SRC"

info "Firefox-98 theme installer.

Variant: $VARIANT

This script will:
1. Locate your Firefox profile directory.
2. Copy the selected variant into the profile's chrome/ directory.
3. Copy the SVG assets and colors.txt alongside it.
4. Set toolkit.legacyUserProfileCustomizations.stylesheets=true.

Firefox must be restarted after installation."

PROFILE_DIR=$(find_firefox_profile) || \
    err "Could not find a Firefox profile.
Launch Firefox at least once, then rerun this script."

info "Profile directory:
$PROFILE_DIR"

confirm "Proceed with installation?" || exit 0

CHROME_DIR="$PROFILE_DIR/chrome"
mkdir -p "$CHROME_DIR"

cp "$CHROME_SRC"  "$CHROME_DIR/userChrome.css"
cp "$CONTENT_SRC" "$CHROME_DIR/userContent.css"

for asset in "$SRC_DIR"/*.svg "$SRC_DIR"/colors.txt; do
    if [ -f "$asset" ]; then
        cp "$asset" "$CHROME_DIR/"
    fi
done

PREFS_OUT="$PROFILE_DIR/user.js"
PREF_LINE='user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'
if ! grep -qF "$PREF_LINE" "$PREFS_OUT" 2>/dev/null; then
    printf '%s\n' "$PREF_LINE" >> "$PREFS_OUT"
fi

info "Installation complete.

Restart Firefox, then clear the startup cache:
about:support > Clear startup cache" 10 64

clear_screen
