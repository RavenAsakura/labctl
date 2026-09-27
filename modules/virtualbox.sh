#!/usr/bin/env bash

virtualbox_help() {
    cat <<'HELP'
Usage:
  labctl virtualbox start
  labctl virtualbox stop
  labctl virtualbox restart
  labctl virtualbox status
  labctl virtualbox vms
  labctl virtualbox help
HELP
}

virtualbox_installed() {
    command_exists VBoxManage
}

virtualbox_driver_loaded() {
    lsmod | awk '{print $1}' | grep -Fxq vboxdrv
}

virtualbox_running_vms() {
    VBoxManage list runningvms 2>/dev/null |
        grep -E '^".*" \{[0-9A-Fa-f-]+\}$' || true
}

virtualbox_running_vm_count() {
    virtualbox_running_vms |
        awk 'NF {count++} END {print count+0}'
}

virtualbox_has_running_vms() {
    (( $(virtualbox_running_vm_count) > 0 ))
}

virtualbox_start() {
    if ! virtualbox_installed; then
        print_warn "VirtualBox is not installed."
        return 0
    fi

    print_info "Starting VirtualBox services..."

    if ! run_privileged systemctl start vboxdrv.service; then
        print_warn "VirtualBox kernel driver could not be started."
        print_info "Attempting to rebuild VirtualBox kernel modules..."

        if [[ -x /sbin/vboxconfig ]] && run_privileged /sbin/vboxconfig; then
            print_ok "VirtualBox kernel modules rebuilt."
        else
            print_error "VirtualBox kernel modules could not be prepared."
            print_info "Run manually: sudo /sbin/vboxconfig"
            return 1
        fi
    fi

    if ! virtualbox_driver_loaded; then
        print_error "VirtualBox kernel driver is still not loaded."
        print_info "Run manually: sudo /sbin/vboxconfig"
        return 1
    fi

    if run_privileged systemctl start \
        vboxautostart-service.service \
        vboxballoonctrl-service.service \
        vboxweb-service.service; then
        print_ok "VirtualBox services started."
    else
        print_error "VirtualBox auxiliary services could not be started."
        return 1
    fi
}

virtualbox_stop() {
    if ! virtualbox_installed; then
        print_warn "VirtualBox is not installed."
        return 0
    fi

    if virtualbox_has_running_vms; then
        print_warn "VirtualBox has running VMs."
        print_info "VirtualBox services were not stopped."
        echo
        virtualbox_running_vms
        return 1
    fi

    if ! virtualbox_driver_loaded; then
        print_info "VirtualBox kernel driver is not loaded."
        print_info "VirtualBox is already effectively stopped."
        return 0
    fi

    print_info "Stopping VirtualBox services..."

    if run_privileged systemctl stop \
        vboxweb-service.service \
        vboxballoonctrl-service.service \
        vboxautostart-service.service \
        vboxdrv.service; then

        print_ok "VirtualBox services stopped."
    else
        print_error "VirtualBox services could not be stopped."
        return 1
    fi
}

virtualbox_restart() {
    virtualbox_stop || return 1
    virtualbox_start || return 1
}

virtualbox_status() {
    print_header "VIRTUALBOX"

    if ! virtualbox_installed; then
        print_status_value "Installation:" "NOT INSTALLED" "warning"
        return 0
    fi

    if virtualbox_driver_loaded; then
        print_status_value "Kernel driver:" "LOADED" "active"
    else
        print_status_value "Kernel driver:" "NOT LOADED" "warning"
    fi

    print_status_value \
        "Driver service:" \
        "$(service_state vboxdrv.service)" \
        "normal"

    print_status_value \
        "Autostart service:" \
        "$(service_state vboxautostart-service.service)" \
        "normal"

    print_status_value \
        "Balloon service:" \
        "$(service_state vboxballoonctrl-service.service)" \
        "normal"

    print_status_value \
        "Web service:" \
        "$(service_state vboxweb-service.service)" \
        "normal"

    print_status_value \
        "Running VMs:" \
        "$(virtualbox_running_vm_count)" \
        "normal"

    echo

    if virtualbox_has_running_vms; then
        print_warn "Running VirtualBox VMs:"
        virtualbox_running_vms
    else
        print_ok "No VirtualBox VMs are running."
    fi
}

virtualbox_vms() {
    if ! virtualbox_installed; then
        print_warn "VirtualBox is not installed."
        return 0
    fi

    print_header "VIRTUALBOX VMS"

    echo "Running:"
    virtualbox_running_vms

    echo
    echo "All VMs:"
    VBoxManage list vms 2>/dev/null |
        grep -E '^".*" \{[0-9A-Fa-f-]+\}$' || true
}

virtualbox_dispatch() {
    local action="${1:-status}"

    case "$action" in
        start) virtualbox_start ;;
        stop) virtualbox_stop ;;
        restart) virtualbox_restart ;;
        status) virtualbox_status ;;
        vms) virtualbox_vms ;;
        help|-h|--help) virtualbox_help ;;
        *)
            print_error "Unknown VirtualBox action: $action"
            virtualbox_help
            return 1
            ;;
    esac
}
