#!/usr/bin/env bash
set -eo pipefail

# Firefox Local Addon Manager - AutoConfig Edition
# Automatically loads temporary Firefox addons using AutoConfig
# Survives Firefox updates via auto-reinstall

# shellcheck disable=SC2155
declare SCRIPT_DIR
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly AUTOCONFIG_DIR="${SCRIPT_DIR}/autoconfig"
readonly ADDON_LIST="${SCRIPT_DIR}/.addon-list.txt"
readonly TEMPLATE_FILE="${AUTOCONFIG_DIR}/autoconfig.js.template"

# Colours
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Error handling
error_handler() {
    echo -e "${RED}Error: Command failed at line $1${NC}" >&2
    exit 1
}
trap 'error_handler $LINENO' ERR

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_debug() { echo -e "${BLUE}[DEBUG]${NC} $*"; }

# Find Firefox executable
find_firefox() {
    if [[ -n "${FIREFOX_BIN:-}" ]] && [[ -x "$FIREFOX_BIN" ]]; then
        echo "$FIREFOX_BIN"
        return 0
    fi

    local firefox_paths=(
        "/Applications/Firefox Developer Edition.app/Contents/MacOS/firefox"
        "/Applications/Firefox Nightly.app/Contents/MacOS/firefox"
        "/Applications/Firefox.app/Contents/MacOS/firefox"
        "$(which firefox-developer-edition 2>/dev/null || true)"
        "$(which firefox-nightly 2>/dev/null || true)"
        "$(which firefox 2>/dev/null || true)"
    )

    for path in "${firefox_paths[@]}"; do
        if [[ -n "$path" ]] && [[ -x "$path" ]]; then
            echo "$path"
            return 0
        fi
    done

    log_error "Firefox not found"
    exit 1
}

# Get Firefox application directory
get_firefox_app_dir() {
    local firefox_bin
    firefox_bin=$(find_firefox)

    # From: /Applications/Firefox Nightly.app/Contents/MacOS/firefox
    # To: /Applications/Firefox Nightly.app
    echo "${firefox_bin%/Contents/MacOS/firefox}"
}

# Get Firefox variant name
get_firefox_variant() {
    local firefox_bin
    firefox_bin=$(find_firefox)

    if [[ "$firefox_bin" == *"Nightly"* ]]; then
        echo "nightly"
    elif [[ "$firefox_bin" == *"Developer Edition"* ]]; then
        echo "developer"
    else
        echo "release"
    fi
}

# Initialize addon list file
init_addon_list() {
    if [[ ! -f "$ADDON_LIST" ]]; then
        touch "$ADDON_LIST"
        log_info "Created addon list file"
    fi
}

# Generate autoconfig.js from template
generate_autoconfig() {
    init_addon_list

    log_info "Generating autoconfig.js from template..."

    local output_file="${AUTOCONFIG_DIR}/autoconfig.js"
    local count=0
    local in_placeholder=0

    # Read template line by line and insert addon paths at placeholder
    > "$output_file"  # Truncate output file

    while IFS= read -r line; do
        if [[ "$line" =~ "// ADDON_PATHS_PLACEHOLDER" ]]; then
            # Insert addon paths
            while IFS= read -r addon_path; do
                [[ -z "$addon_path" ]] && continue
                [[ "$addon_path" =~ ^# ]] && continue

                # Verify addon exists
                if [[ ! -e "$addon_path" ]]; then
                    log_warn "Addon path does not exist (skipping): $addon_path"
                    continue
                fi

                # Escape path for JavaScript string
                local escaped_path
                escaped_path=$(echo "$addon_path" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')

                echo "        \"${escaped_path}\"," >> "$output_file"
                count=$((count + 1))
            done < "$ADDON_LIST"

            # Remove trailing comma from last line
            if [[ $count -gt 0 ]]; then
                # Use temp file to remove trailing comma from last addon path
                sed -i '' '$ s/,$//' "$output_file"
            fi
        else
            echo "$line" >> "$output_file"
        fi
    done < "$TEMPLATE_FILE"

    log_info "Generated autoconfig.js with $count addon(s)"
}

# Install AutoConfig files into Firefox
install_autoconfig() {
    local firefox_app
    firefox_app=$(get_firefox_app_dir)

    local defaults_dir="${firefox_app}/Contents/Resources/defaults"
    local pref_dir="${defaults_dir}/pref"

    log_info "Installing AutoConfig files into Firefox..."
    log_info "Firefox: $firefox_app"

    # Create directories if they don't exist
    if [[ ! -d "$defaults_dir" ]]; then
        mkdir -p "$defaults_dir"
        log_info "Created: $defaults_dir"
    fi

    if [[ ! -d "$pref_dir" ]]; then
        mkdir -p "$pref_dir"
        log_info "Created: $pref_dir"
    fi

    # Copy config files
    cp "${AUTOCONFIG_DIR}/config-prefs.js" "$pref_dir/"
    log_info "Installed: config-prefs.js"

    cp "${AUTOCONFIG_DIR}/autoconfig.js" "${firefox_app}/Contents/Resources/"
    log_info "Installed: autoconfig.js"

    log_info "AutoConfig installation complete!"
}

# Check if AutoConfig is installed
is_autoconfig_installed() {
    local firefox_app
    firefox_app=$(get_firefox_app_dir)

    local pref_file="${firefox_app}/Contents/Resources/defaults/pref/config-prefs.js"
    local autoconfig_file="${firefox_app}/Contents/Resources/autoconfig.js"

    [[ -f "$pref_file" ]] && [[ -f "$autoconfig_file" ]]
}

# Add addon to list
add_addon() {
    local addon_path="$1"

    init_addon_list

    # Convert to absolute path
    if [[ ! "$addon_path" =~ ^/ ]]; then
        addon_path="$(cd "$(dirname "$addon_path")" && pwd)/$(basename "$addon_path")"
    fi

    if [[ ! -e "$addon_path" ]]; then
        log_error "Addon path does not exist: $addon_path"
        return 1
    fi

    # Check if already in list
    if grep -Fxq "$addon_path" "$ADDON_LIST" 2>/dev/null; then
        log_warn "Addon already in list: $addon_path"
        return 0
    fi

    # Add to list
    echo "$addon_path" >> "$ADDON_LIST"
    log_info "Added addon: $addon_path"

    # Regenerate and reinstall
    generate_autoconfig
    install_autoconfig

    log_info "Addon added successfully!"
    log_warn "Restart Firefox to load the addon"
}

# Remove addon from list (interactive if no path provided)
remove_addon() {
    local addon_path="$1"

    init_addon_list

    # If no path provided, show interactive menu
    if [[ -z "$addon_path" ]]; then
        remove_addon_interactive
        return $?
    fi

    # Convert to absolute path if it's a path
    if [[ -e "$addon_path" ]] && [[ ! "$addon_path" =~ ^/ ]]; then
        addon_path="$(cd "$(dirname "$addon_path")" && pwd)/$(basename "$addon_path")"
    fi

    # Remove from list
    if grep -Fxq "$addon_path" "$ADDON_LIST" 2>/dev/null; then
        # Use temp file for safe removal
        grep -Fxv "$addon_path" "$ADDON_LIST" > "${ADDON_LIST}.tmp" || true
        mv "${ADDON_LIST}.tmp" "$ADDON_LIST"
        log_info "Removed addon: $addon_path"

        # Regenerate and reinstall
        generate_autoconfig
        install_autoconfig

        log_info "Addon removed successfully!"
        log_warn "Restart Firefox to apply changes"
    else
        log_warn "Addon not found in list: $addon_path"
        return 1
    fi
}

# Interactive addon removal menu
remove_addon_interactive() {
    init_addon_list

    # Read addons into array
    local -a addons=()
    while IFS= read -r addon_path; do
        [[ -z "$addon_path" ]] && continue
        [[ "$addon_path" =~ ^# ]] && continue
        addons+=("$addon_path")
    done < "$ADDON_LIST"

    if [[ ${#addons[@]} -eq 0 ]]; then
        log_warn "No addons configured to remove"
        return 1
    fi

    # Display menu
    echo ""
    log_info "Select addon(s) to remove:"
    echo ""

    local i=1
    for addon in "${addons[@]}"; do
        if [[ -e "$addon" ]]; then
            echo "  $i) ✓ $addon"
        else
            echo "  $i) ✗ $addon (missing)"
        fi
        i=$((i + 1))
    done

    echo ""
    echo "  0) Cancel"
    echo ""
    echo -n "Enter number(s) separated by spaces (e.g., 1 3 5): "

    local input
    read -r input

    # Handle cancel
    if [[ -z "$input" ]] || [[ "$input" == "0" ]]; then
        log_info "Cancelled"
        return 0
    fi

    # Parse selections
    local -a to_remove=()
    local changed=0

    for num in $input; do
        # Validate number
        if ! [[ "$num" =~ ^[0-9]+$ ]]; then
            log_warn "Invalid selection: $num"
            continue
        fi

        local idx=$((num - 1))

        if [[ $idx -ge 0 ]] && [[ $idx -lt ${#addons[@]} ]]; then
            to_remove+=("${addons[$idx]}")
        else
            log_warn "Invalid selection: $num (out of range)"
        fi
    done

    if [[ ${#to_remove[@]} -eq 0 ]]; then
        log_warn "No valid selections made"
        return 1
    fi

    # Confirm removal
    echo ""
    log_info "Will remove ${#to_remove[@]} addon(s):"
    for addon in "${to_remove[@]}"; do
        echo "  - $addon"
    done
    echo ""
    echo -n "Confirm removal? [y/N]: "

    local confirm
    read -r confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Cancelled"
        return 0
    fi

    # Remove selected addons
    echo ""
    for addon in "${to_remove[@]}"; do
        if grep -Fxq "$addon" "$ADDON_LIST" 2>/dev/null; then
            grep -Fxv "$addon" "$ADDON_LIST" > "${ADDON_LIST}.tmp" || true
            mv "${ADDON_LIST}.tmp" "$ADDON_LIST"
            log_info "Removed: $addon"
            changed=1
        fi
    done

    if [[ $changed -eq 1 ]]; then
        # Regenerate and reinstall
        generate_autoconfig
        install_autoconfig

        echo ""
        log_info "Successfully removed ${#to_remove[@]} addon(s)"
        log_warn "Restart Firefox to apply changes"
    fi

    return 0
}

# List addons
list_addons() {
    init_addon_list

    log_info "Configured addons:"
    echo ""

    local count=0
    while IFS= read -r addon_path; do
        [[ -z "$addon_path" ]] && continue
        [[ "$addon_path" =~ ^# ]] && continue

        if [[ -e "$addon_path" ]]; then
            echo "  ✓ $addon_path"
        else
            echo "  ✗ $addon_path (missing)"
        fi
        count=$((count + 1))
    done < "$ADDON_LIST"

    if [[ $count -eq 0 ]]; then
        log_warn "No addons configured"
        echo ""
        log_info "Add addons with: $0 add <path>"
    else
        echo ""
        echo "Total: $count addon(s)"
    fi

    echo ""
    if is_autoconfig_installed; then
        echo -e "${GREEN}✓${NC} AutoConfig is installed in Firefox"
    else
        echo -e "${YELLOW}✗${NC} AutoConfig not installed - run: $0 setup"
    fi
}

# Setup AutoConfig
setup() {
    log_info "Setting up Firefox AutoConfig for addon auto-loading..."

    generate_autoconfig
    install_autoconfig

    echo ""
    log_info "Setup complete!"
    log_info "Add addons with: $0 add <path>"
    log_info "Start Firefox with: $0 start"
    echo ""
    log_warn "Note: After Firefox updates, AutoConfig files may be removed."
    log_warn "Just run '$0 start' and it will auto-reinstall them."
}

# Start Firefox with auto-check
start_firefox() {
    local firefox_bin
    firefox_bin=$(find_firefox)

    # Auto-check and reinstall if needed
    if ! is_autoconfig_installed; then
        log_warn "AutoConfig not installed (Firefox may have updated)"
        log_info "Auto-reinstalling..."
        install_autoconfig
        echo ""
    fi

    local variant
    variant=$(get_firefox_variant)

    log_info "Starting Firefox ($variant)..."
    log_info "Binary: $firefox_bin"
    log_info "Addons will auto-load from configured list"
    echo ""

    "$firefox_bin" "$@" &
}

# Show status
show_status() {
    local firefox_app
    firefox_app=$(get_firefox_app_dir)

    local variant
    variant=$(get_firefox_variant)

    echo ""
    log_info "Firefox variant: $variant"
    log_info "Firefox location: $firefox_app"
    echo ""

    if is_autoconfig_installed; then
        echo -e "${GREEN}✓ AutoConfig is installed${NC}"
    else
        echo -e "${YELLOW}✗ AutoConfig is NOT installed${NC}"
        log_info "Run '$0 setup' to install"
    fi

    echo ""
    log_info "Configured addons:"

    init_addon_list
    local count=0
    while IFS= read -r addon_path; do
        [[ -z "$addon_path" ]] && continue
        [[ "$addon_path" =~ ^# ]] && continue

        if [[ -e "$addon_path" ]]; then
            echo "  ✓ $addon_path"
        else
            echo "  ✗ $addon_path (missing)"
        fi
        count=$((count + 1))
    done < "$ADDON_LIST"

    if [[ $count -eq 0 ]]; then
        echo "  (none)"
    fi
    echo ""
}

# Show usage
show_usage() {
    cat <<EOF
Firefox Local Addon Manager - AutoConfig Edition

Automatically loads temporary addons using Firefox AutoConfig.
No signature checking needed, survives Firefox updates via auto-reinstall.

Usage: $0 <command> [arguments]

Commands:
  setup              Set up AutoConfig in Firefox
  add <path>         Add addon to auto-load list
  remove [path]      Remove addon from list (interactive menu if no path)
  list               List configured addons
  status             Show installation status
  start              Launch Firefox (auto-reinstalls config if needed)
  help               Show this help message

Examples:
  # Initial setup
  $0 setup

  # Add addons
  $0 add ~/dev/my-addon
  $0 add ~/downloads/addon.xpi

  # List configured addons
  $0 list

  # Start Firefox (auto-loads addons)
  $0 start

  # Remove addon (interactive menu)
  $0 remove

  # Remove addon by path
  $0 remove ~/dev/my-addon

  # Check status
  $0 status

How it works:
  - Uses Firefox AutoConfig to call AddonManager.installTemporaryAddon()
  - Loads addons as temporary (same as about:debugging)
  - No signature checking required
  - Auto-reinstalls config files after Firefox updates

Notes:
  - Addons load automatically when Firefox starts
  - Restart Firefox after adding/removing addons
  - Use '$0 start' to launch Firefox with auto-checking
  - After Firefox updates, config files may need reinstalling
    (happens automatically when you use '$0 start')
EOF
}

# Main
main() {
    local command="${1:-help}"

    case "$command" in
        setup)
            setup
            ;;
        add)
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 add <path>"
                exit 1
            fi
            add_addon "$2"
            ;;
        remove)
            remove_addon "${2:-}"
            ;;
        list)
            list_addons
            ;;
        status)
            show_status
            ;;
        start)
            shift
            start_firefox "$@"
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
