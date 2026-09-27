#!/usr/bin/env bash

firewall_help() {
    cat <<'HELP'
Usage:
  labctl firewall status
  labctl firewall zones
  labctl firewall active
  labctl firewall interfaces
  labctl firewall services
  labctl firewall ports
  labctl firewall help

Supported backends:
  UFW          Ubuntu and Debian-based systems
  Firewalld    Fedora and other Firewalld-based systems
HELP
}

firewall_backend() {
    if command_exists ufw && firewall_ufw_enabled; then
        printf 'ufw\n'
    elif command_exists firewall-cmd && service_is_active firewalld.service; then
        printf 'firewalld\n'
    elif command_exists ufw; then
        printf 'ufw\n'
    elif command_exists firewall-cmd; then
        printf 'firewalld\n'
    else
        printf 'unavailable\n'
    fi
}

firewall_require_backend() {
    if [[ "$(firewall_backend)" == "unavailable" ]]; then
        print_error "Neither UFW nor Firewalld is installed."
        return 1
    fi
}

firewall_ufw_enabled() {
    [[ -r /etc/ufw/ufw.conf ]] &&
        grep -Eq '^[[:space:]]*ENABLED=yes([[:space:]]|$)' /etc/ufw/ufw.conf
}

firewall_ufw_status() {
    if (( EUID == 0 )); then
        ufw status "$@"
    else
        sudo ufw status "$@"
    fi
}

firewall_status() {
    local backend
    backend="$(firewall_backend)"

    firewall_require_backend || return 1

    print_header "FIREWALL STATUS"
    print_status_value "Backend:" "$backend" "info"

    case "$backend" in
        ufw)
            if firewall_ufw_enabled; then
                print_status_value "UFW:" "ENABLED" "active"
            else
                print_status_value "UFW:" "DISABLED" "warning"
            fi
            ;;
        firewalld)
            printf "%-24s %s\n" \
                "Firewalld Service:" \
                "$(service_state firewalld.service)"

            if systemctl is-active --quiet firewalld.service; then
                print_status_value \
                    "Default Zone:" \
                    "$(firewall-cmd --get-default-zone 2>/dev/null)" \
                    "normal"
                print_status_value \
                    "Panic Mode:" \
                    "$(firewall-cmd --query-panic 2>/dev/null || true)" \
                    "normal"
            fi
            ;;
    esac
}

firewall_zones() {
    firewall_require_backend || return 1

    print_header "FIREWALL ZONES"

    if [[ "$(firewall_backend)" == "ufw" ]]; then
        print_info "UFW does not use zones. Showing its verbose status instead."
        firewall_ufw_status verbose
    else
        sudo firewall-cmd --get-zones
    fi
}

firewall_active() {
    firewall_require_backend || return 1

    print_header "ACTIVE FIREWALL CONFIGURATION"

    if [[ "$(firewall_backend)" == "ufw" ]]; then
        firewall_ufw_status numbered
    else
        sudo firewall-cmd --get-active-zones
    fi
}

firewall_interfaces() {
    firewall_require_backend || return 1

    print_header "FIREWALL INTERFACES"

    if [[ "$(firewall_backend)" == "ufw" ]]; then
        print_info "UFW does not assign interfaces to zones."
        firewall_ufw_status verbose
        return
    fi

    local interface
    local zone

    while IFS= read -r interface; do
        [[ -n "$interface" ]] || continue

        zone="$(
            firewall-cmd \
                --get-zone-of-interface="$interface" \
                2>/dev/null ||
            true
        )"

        printf "%-24s %s\n" \
            "$interface:" \
            "${zone:-No zone assigned}"
    done < <(
        nmcli -t -f DEVICE device status 2>/dev/null |
        sed '/^[[:space:]]*$/d'
    )
}

firewall_services() {
    firewall_require_backend || return 1

    print_header "ALLOWED FIREWALL SERVICES"

    if [[ "$(firewall_backend)" == "ufw" ]]; then
        print_info "Showing UFW application profiles."
        if (( EUID == 0 )); then
            ufw app list
        else
            sudo ufw app list
        fi
        return
    fi

    local zone

    while IFS= read -r zone; do
        [[ -n "$zone" ]] || continue

        echo
        printf "Zone: %s\n" "$zone"

        sudo firewall-cmd \
            --zone="$zone" \
            --list-services
    done < <(
        sudo firewall-cmd --get-active-zones |
        awk '/^[^[:space:]]/ {print $1}'
    )
}

firewall_ports() {
    firewall_require_backend || return 1

    print_header "ALLOWED FIREWALL PORTS"

    if [[ "$(firewall_backend)" == "ufw" ]]; then
        firewall_ufw_status numbered
        return
    fi

    local zone
    local ports

    while IFS= read -r zone; do
        [[ -n "$zone" ]] || continue

        ports="$(
            sudo firewall-cmd \
                --zone="$zone" \
                --list-ports
        )"

        printf "%-24s %s\n" \
            "$zone:" \
            "${ports:-None}"
    done < <(
        sudo firewall-cmd --get-active-zones |
        awk '/^[^[:space:]]/ {print $1}'
    )
}

firewall_dispatch() {
    local action="${1:-status}"

    case "$action" in
        status)
            firewall_status
            ;;
        zones)
            firewall_zones
            ;;
        active)
            firewall_active
            ;;
        interfaces)
            firewall_interfaces
            ;;
        services)
            firewall_services
            ;;
        ports)
            firewall_ports
            ;;
        help|-h|--help)
            firewall_help
            ;;
        *)
            print_error "Unknown firewall action: $action"
            firewall_help
            return 1
            ;;
    esac
}
