#!/usr/bin/env bash

readonly LABCTL_OK="[OK]"
readonly LABCTL_WARN="[WARNING]"
readonly LABCTL_ERROR="[ERROR]"
readonly LABCTL_INFO="[INFO]"

print_line() {
    printf '%*s\n' 62 '' | tr ' ' '='
}

print_header() {
    print_line
    printf " %s\n" "$1"
    print_line
}

print_ok() {
    printf "%s %s\n" "$LABCTL_OK" "$*"
}

print_warn() {
    printf "%s %s\n" "$LABCTL_WARN" "$*"
}

print_error() {
    printf "%s %s\n" "$LABCTL_ERROR" "$*" >&2
}

print_info() {
    printf "%s %s\n" "$LABCTL_INFO" "$*"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

service_is_active() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

service_state() {
    if service_is_active "$1"; then
        printf "ACTIVE"
    else
        printf "STOPPED"
    fi
}

require_command() {
    local command_name="$1"

    if ! command_exists "$command_name"; then
        print_error "Required command not found: $command_name"
        return 1
    fi
}

confirm_action() {
    local message="$1"
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
