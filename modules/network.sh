#!/usr/bin/env bash

network_help() {
    cat <<'HELP'
Usage:
  labctl network list
  labctl network active
  labctl network status NAME
  labctl network start NAME
  labctl network stop NAME
  labctl network autostart NAME
  labctl network no-autostart NAME
  labctl network help
HELP
}

network_require_virsh() {
    require_command virsh
}

network_require_name() {
    local network_name="${1:-}"

    if [[ -z "$network_name" ]]; then
        print_error "A network name is required."
        print_info "List networks with: labctl network list"
        return 1
    fi

    if ! sudo virsh net-info "$network_name" >/dev/null 2>&1; then
        print_error "Libvirt network not found: $network_name"
        return 1
    fi
}

network_get_state() {
    sudo virsh net-info "$1" 2>/dev/null |
        awk -F: '/Active:/ {
            gsub(/^[[:space:]]+/, "", $2)
            print tolower($2)
        }'
}

network_list() {
    network_require_virsh || return 1
    print_header "LIBVIRT NETWORKS"
    sudo virsh net-list --all
}

network_active() {
    network_require_virsh || return 1
    print_header "ACTIVE LIBVIRT NETWORKS"
    sudo virsh net-list
}

network_status() {
    local network_name="${1:-}"

    network_require_virsh || return 1
    network_require_name "$network_name" || return 1

    print_header "LIBVIRT NETWORK STATUS"
    sudo virsh net-info "$network_name"

    echo
    print_info "XML configuration summary:"

    sudo virsh net-dumpxml "$network_name" 2>/dev/null |
        grep -E '<name>|<bridge|<forward|<ip ' ||
        true
}

network_start() {
    local network_name="${1:-}"
    local state

    network_require_virsh || return 1
    network_require_name "$network_name" || return 1
    state="$(network_get_state "$network_name")"

    if [[ "$state" == "yes" ]]; then
        print_warn "The network is already active: $network_name"
        return 0
    fi

    print_info "Starting network: $network_name"

    if sudo virsh net-start "$network_name"; then
        print_ok "Network started: $network_name"
    else
        print_error "The network could not be started: $network_name"
        return 1
    fi
}

network_stop() {
    local network_name="${1:-}"
    local state
    local vm_count

    network_require_virsh || return 1
    network_require_name "$network_name" || return 1
    state="$(network_get_state "$network_name")"

    if [[ "$state" == "no" ]]; then
        print_warn "The network is already stopped: $network_name"
        return 0
    fi

    vm_count="$(sudo virsh list --name 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l)"

    if (( vm_count > 0 )); then
        print_warn "Running virtual machines were detected."
        print_info "Stopping this network may interrupt VM connectivity."
    fi

    if ! confirm_action "Stop network $network_name?"; then
        print_info "Operation cancelled."
        return 0
    fi

    if sudo virsh net-destroy "$network_name"; then
        print_ok "Network stopped: $network_name"
    else
        print_error "The network could not be stopped: $network_name"
        return 1
    fi
}

network_autostart() {
    local network_name="${1:-}"

    network_require_virsh || return 1
    network_require_name "$network_name" || return 1

    if sudo virsh net-autostart "$network_name"; then
        print_ok "Autostart enabled for: $network_name"
    else
        print_error "Autostart could not be enabled."
        return 1
    fi
}

network_no_autostart() {
    local network_name="${1:-}"

    network_require_virsh || return 1
    network_require_name "$network_name" || return 1

    if sudo virsh net-autostart "$network_name" --disable; then
        print_ok "Autostart disabled for: $network_name"
    else
        print_error "Autostart could not be disabled."
        return 1
    fi
}

network_dispatch() {
    local action="${1:-help}"
    shift || true

    case "$action" in
        list) network_list ;;
        active) network_active ;;
        status) network_status "${1:-}" ;;
        start) network_start "${1:-}" ;;
        stop) network_stop "${1:-}" ;;
        autostart) network_autostart "${1:-}" ;;
        no-autostart) network_no_autostart "${1:-}" ;;
        help|-h|--help) network_help ;;
        *)
            print_error "Unknown network action: $action"
            network_help
            return 1
            ;;
    esac
}
