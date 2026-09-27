#!/usr/bin/env bash

power_help() {
    cat <<'HELP'
Usage:
  labctl power status
  labctl power list
  labctl power balanced
  labctl power performance
  labctl power power-saver
  labctl power help
HELP
}

power_backend() {
    if command_exists powerprofilesctl; then
        printf 'powerprofilesctl\n'
    elif command_exists tuned-adm; then
        printf 'tuned\n'
    else
        printf 'unavailable\n'
    fi
}

power_normalize_profile() {
    case "${1:-}" in
        powersave|power-saver) printf 'power-saver\n' ;;
        balanced) printf 'balanced\n' ;;
        performance) printf 'performance\n' ;;
        *) printf '%s\n' "${1:-}" ;;
    esac
}

power_tuned_profile() {
    case "$(power_normalize_profile "${1:-}")" in
        power-saver) printf 'powersave\n' ;;
        *) power_normalize_profile "${1:-}" ;;
    esac
}

power_current() {
    local current=""

    case "$(power_backend)" in
        powerprofilesctl)
            current="$(powerprofilesctl get 2>/dev/null || true)"
            ;;
        tuned)
            current="$(
                tuned-adm active 2>/dev/null |
                    sed -n 's/^Current active profile: //p' |
                    head -n 1
            )"
            ;;
    esac

    if [[ -n "$current" ]]; then
        power_normalize_profile "$current"
    else
        printf 'unavailable\n'
    fi
}

power_set() {
    local requested
    local backend
    local backend_profile

    requested="$(power_normalize_profile "${1:?Missing power profile}")"
    backend="$(power_backend)"

    case "$requested" in
        balanced|performance|power-saver) ;;
        *)
            print_error "Unsupported power profile: $requested"
            return 1
            ;;
    esac

    if [[ "$backend" == "unavailable" ]]; then
        print_warn "No supported power-profile backend is available."
        return 1
    fi

    if [[ "$(power_current)" == "$requested" ]]; then
        print_info "Power profile is already '$requested'."
        return 0
    fi

    case "$backend" in
        powerprofilesctl)
            print_info "Setting power profile to '$requested' with powerprofilesctl..."
            if powerprofilesctl set "$requested"; then
                print_ok "Power profile set to '$requested'."
            else
                print_error "Power profile could not be changed to '$requested'."
                return 1
            fi
            ;;
        tuned)
            backend_profile="$(power_tuned_profile "$requested")"
            print_info "Setting power profile to '$requested' with TuneD..."
            if sudo tuned-adm profile "$backend_profile"; then
                print_ok "Power profile set to '$requested'."
            else
                print_error "Power profile could not be changed to '$requested'."
                return 1
            fi
            ;;
    esac
}

power_status() {
    print_header "POWER PROFILE"
    print_status_value "Backend:" "$(power_backend)" "info"
    print_status_value "Current profile:" "$(power_current)" "normal"
}

power_list() {
    print_header "POWER PROFILES"

    case "$(power_backend)" in
        powerprofilesctl) powerprofilesctl list ;;
        tuned) tuned-adm list ;;
        *)
            print_error "No supported power-profile backend is available."
            return 1
            ;;
    esac
}

power_dispatch() {
    local action="${1:-status}"

    case "$action" in
        status) power_status ;;
        list) power_list ;;
        balanced|performance|power-saver|powersave) power_set "$action" ;;
        help|-h|--help) power_help ;;
        *)
            print_error "Unknown power action: $action"
            power_help
            return 1
            ;;
    esac
}
