#!/usr/bin/env bash

vmware_help() {
    cat <<'HELP'
Usage:
  labctl vmware start
  labctl vmware stop
  labctl vmware restart
  labctl vmware status
  labctl vmware help
HELP
}

vmware_start() {
    print_info "Starting VMware..."

    run_privileged systemctl start \
        vmware.service \
        vmware-USBArbitrator.service

    if service_is_active vmware.service; then
        print_ok "VMware is active."
    else
        print_error "VMware could not be started."
        return 1
    fi

    if service_is_active vmware-USBArbitrator.service; then
        print_ok "VMware USB Arbitrator is active."
    else
        print_warn "VMware started, but USB Arbitrator is stopped."
    fi
}

vmware_stop() {
    print_info "Stopping VMware..."

    run_privileged systemctl stop \
        vmware.service \
        vmware-USBArbitrator.service

    if service_is_active vmware.service; then
        print_error "VMware is still active."
        return 1
    fi

    print_ok "VMware is stopped."
}

vmware_restart() {
    print_info "Restarting VMware..."

    run_privileged systemctl restart \
        vmware.service \
        vmware-USBArbitrator.service

    if service_is_active vmware.service; then
        print_ok "VMware restarted successfully."
    else
        print_error "VMware could not be restarted."
        return 1
    fi
}

vmware_status() {
    print_header "VMWARE"

    printf "%-25s %s\n" "VMware:" "$(service_state vmware.service)"
    printf "%-25s %s\n" "USB Arbitrator:" "$(service_state vmware-USBArbitrator.service)"

    if pgrep -f vmware >/dev/null 2>&1; then
        echo
        print_info "Detected VMware processes:"
        pgrep -a -f vmware
    fi
}

vmware_dispatch() {
    local action="${1:-help}"

    case "$action" in
        start) vmware_start ;;
        stop) vmware_stop ;;
        restart) vmware_restart ;;
        status) vmware_status ;;
        help|-h|--help) vmware_help ;;
        *)
            print_error "Unknown VMware action: $action"
            vmware_help
            return 1
            ;;
    esac
}
