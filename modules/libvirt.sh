#!/usr/bin/env bash

libvirt_help() {
    cat <<'HELP'
Usage:
  labctl libvirt start
  labctl libvirt stop
  labctl libvirt restart
  labctl libvirt status
  labctl libvirt help
HELP
}

libvirt_running_vms() {
    sudo virsh list --name 2>/dev/null | sed '/^[[:space:]]*$/d'
}

libvirt_start() {
    print_info "Starting libvirt services..."

    sudo systemctl start \
        virtqemud.service \
        virtnetworkd.service \
        virtlogd.service

    if service_is_active virtqemud.service; then
        print_ok "virtqemud is active."
    else
        print_error "virtqemud could not be started."
        return 1
    fi

    service_is_active virtnetworkd.service \
        && print_ok "virtnetworkd is active." \
        || print_warn "virtnetworkd is stopped."

    service_is_active virtlogd.service \
        && print_ok "virtlogd is active." \
        || print_warn "virtlogd is stopped."
}

libvirt_stop() {
    local running_vms
    running_vms="$(libvirt_running_vms)"

    if [[ -n "$running_vms" ]]; then
        print_error "Running virtual machines were detected:"
        printf '%s\n' "$running_vms"
        print_info "Shut them down before stopping libvirt."
        return 1
    fi

    print_info "Stopping libvirt services..."

    sudo systemctl stop \
        virtqemud.service \
        virtnetworkd.service \
        virtlogd.service

    if service_is_active virtqemud.service; then
        print_error "virtqemud is still active."
        return 1
    fi

    print_ok "Main libvirt services are stopped."
    print_info "Socket activation remains available."
}

libvirt_restart() {
    local running_vms
    running_vms="$(libvirt_running_vms)"

    if [[ -n "$running_vms" ]]; then
        print_warn "Running VMs were detected. Libvirt will not be restarted."
        printf '%s\n' "$running_vms"
        return 1
    fi

    print_info "Restarting libvirt..."

    sudo systemctl restart \
        virtqemud.service \
        virtnetworkd.service \
        virtlogd.service

    if service_is_active virtqemud.service; then
        print_ok "Libvirt restarted successfully."
    else
        print_error "Libvirt could not be restarted."
        return 1
    fi
}

libvirt_status() {
    print_header "LIBVIRT"

    printf "%-25s %s\n" "virtqemud:" "$(service_state virtqemud.service)"
    printf "%-25s %s\n" "virtnetworkd:" "$(service_state virtnetworkd.service)"
    printf "%-25s %s\n" "virtlogd:" "$(service_state virtlogd.service)"
    printf "%-25s %s\n" "libvirtd:" "$(service_state libvirtd.service)"

    echo
    print_info "Main sockets:"

    printf "%-25s %s\n" "virtqemud.socket:" "$(service_state virtqemud.socket)"
    printf "%-25s %s\n" "virtnetworkd.socket:" "$(service_state virtnetworkd.socket)"
    printf "%-25s %s\n" "virtlogd.socket:" "$(service_state virtlogd.socket)"

    echo
    print_info "Running VMs:"
    sudo virsh list 2>/dev/null || true
}

libvirt_dispatch() {
    local action="${1:-help}"

    case "$action" in
        start) libvirt_start ;;
        stop) libvirt_stop ;;
        restart) libvirt_restart ;;
        status) libvirt_status ;;
        help|-h|--help) libvirt_help ;;
        *)
            print_error "Unknown libvirt action: $action"
            libvirt_help
            return 1
            ;;
    esac
}
