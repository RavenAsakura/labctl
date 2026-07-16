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
HELP
}

firewall_require_commands() {
    require_command firewall-cmd || return 1
    require_command systemctl || return 1
}

firewall_status() {
    firewall_require_commands || return 1

    print_header "FIREWALL STATUS"

    printf "%-24s %s\n" \
        "Firewalld Service:" \
        "$(service_state firewalld.service)"

    if command_exists getenforce; then
        printf "%-24s %s\n" \
            "SELinux:" \
            "$(getenforce)"
    fi

    if systemctl is-active --quiet firewalld.service; then
        printf "%-24s %s\n" \
            "Default Zone:" \
            "$(firewall-cmd --get-default-zone 2>/dev/null)"

        printf "%-24s %s\n" \
            "Panic Mode:" \
            "$(firewall-cmd --query-panic 2>/dev/null || true)"
    fi
}

firewall_zones() {
    firewall_require_commands || return 1

    print_header "FIREWALL ZONES"

    sudo firewall-cmd --get-zones
}

firewall_active() {
    firewall_require_commands || return 1

    print_header "ACTIVE FIREWALL ZONES"

    sudo firewall-cmd --get-active-zones
}

firewall_interfaces() {
    firewall_require_commands || return 1

    print_header "FIREWALL INTERFACES"

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
    firewall_require_commands || return 1

    print_header "ALLOWED FIREWALL SERVICES"

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
    firewall_require_commands || return 1

    print_header "ALLOWED FIREWALL PORTS"

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
