#!/usr/bin/env bash

# LabCTL output and user-interface helpers.
# Colors are enabled only when stdout is an interactive terminal.
# Set NO_COLOR=1 to disable colors manually.

LABCTL_COLOR_ENABLED=false

if [[ -t 1 ]] &&
   [[ -z "${NO_COLOR:-}" ]] &&
   [[ "${TERM:-dumb}" != "dumb" ]]; then
    LABCTL_COLOR_ENABLED=true
fi

if [[ "$LABCTL_COLOR_ENABLED" == true ]]; then
    LABCTL_RESET=$'\033[0m'
    LABCTL_BOLD=$'\033[1m'

    LABCTL_RED=$'\033[31m'
    LABCTL_GREEN=$'\033[32m'
    LABCTL_YELLOW=$'\033[33m'
    LABCTL_BLUE=$'\033[34m'
    LABCTL_CYAN=$'\033[36m'
    LABCTL_WHITE=$'\033[37m'
else
    LABCTL_RESET=""
    LABCTL_BOLD=""

    LABCTL_RED=""
    LABCTL_GREEN=""
    LABCTL_YELLOW=""
    LABCTL_BLUE=""
    LABCTL_CYAN=""
    LABCTL_WHITE=""
fi

print_line() {
    printf '%*s\n' 62 '' | tr ' ' '='
}

print_header() {
    local title="${1:-}"

    printf '%s%s' "$LABCTL_CYAN" "$LABCTL_BOLD"
    print_line
    printf " %s\n" "$title"
    print_line
    printf '%s' "$LABCTL_RESET"
}

print_subheader() {
    local title="${1:-}"

    printf '\n%s%s%s%s\n' \
        "$LABCTL_BOLD" \
        "$LABCTL_CYAN" \
        "$title" \
        "$LABCTL_RESET"
}

print_ok() {
    printf '%s[OK]%s      %s\n' \
        "$LABCTL_GREEN" \
        "$LABCTL_RESET" \
        "$*"
}

print_pass() {
    printf '%s[PASS]%s    %s\n' \
        "$LABCTL_GREEN" \
        "$LABCTL_RESET" \
        "$*"
}

print_info() {
    printf '%s[INFO]%s    %s\n' \
        "$LABCTL_BLUE" \
        "$LABCTL_RESET" \
        "$*"
}

print_warn() {
    printf '%s[WARNING]%s %s\n' \
        "$LABCTL_YELLOW" \
        "$LABCTL_RESET" \
        "$*"
}

print_error() {
    printf '%s[ERROR]%s   %s\n' \
        "$LABCTL_RED" \
        "$LABCTL_RESET" \
        "$*" >&2
}

print_status_value() {
    local label="${1:-}"
    local value="${2:-}"
    local state="${3:-normal}"
    local color="$LABCTL_WHITE"

    case "$state" in
        ok|pass|healthy|active)
            color="$LABCTL_GREEN"
            ;;
        info)
            color="$LABCTL_BLUE"
            ;;
        warning|warn)
            color="$LABCTL_YELLOW"
            ;;
        error|critical|failed)
            color="$LABCTL_RED"
            ;;
        normal|*)
            color="$LABCTL_WHITE"
            ;;
    esac

    printf "%-24s %s%s%s\n" \
        "$label" \
        "$color" \
        "$value" \
        "$LABCTL_RESET"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

service_is_active() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

service_is_enabled() {
    systemctl is-enabled --quiet "$1" 2>/dev/null
}

service_state() {
    if service_is_active "$1"; then
        printf '%sACTIVE%s' \
            "$LABCTL_GREEN" \
            "$LABCTL_RESET"
    else
        printf '%sSTOPPED%s' \
            "$LABCTL_YELLOW" \
            "$LABCTL_RESET"
    fi
}

require_command() {
    local command_name="${1:-}"

    if [[ -z "$command_name" ]]; then
        print_error "No command name was provided."
        return 1
    fi

    if ! command_exists "$command_name"; then
        print_error "Required command not found: $command_name"
        return 1
    fi
}

confirm_action() {
    local message="${1:-Continue?}"
    local answer=""

    read -r -p "$message [y/N]: " answer

    case "${answer:-}" in
        y|Y|yes|YES|Yes)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

color_by_percentage() {
    local value="${1:-0}"
    local warning="${2:-70}"
    local critical="${3:-90}"

    if (( value >= critical )); then
        printf '%s%s%%%s' \
            "$LABCTL_RED" \
            "$value" \
            "$LABCTL_RESET"
    elif (( value >= warning )); then
        printf '%s%s%%%s' \
            "$LABCTL_YELLOW" \
            "$value" \
            "$LABCTL_RESET"
    else
        printf '%s%s%%%s' \
            "$LABCTL_GREEN" \
            "$value" \
            "$LABCTL_RESET"
    fi
}

color_by_temperature() {
    local value="${1:-0}"
    local warning="${2:-60}"
    local critical="${3:-80}"

    if (( value >= critical )); then
        printf '%s%s °C%s' \
            "$LABCTL_RED" \
            "$value" \
            "$LABCTL_RESET"
    elif (( value >= warning )); then
        printf '%s%s °C%s' \
            "$LABCTL_YELLOW" \
            "$value" \
            "$LABCTL_RESET"
    else
        printf '%s%s °C%s' \
            "$LABCTL_GREEN" \
            "$value" \
            "$LABCTL_RESET"
    fi
}
