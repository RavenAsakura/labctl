#!/usr/bin/env bash

vm_help() {
    cat <<'HELP'
Usage:
  labctl vm list
  labctl vm running
  labctl vm status NAME
  labctl vm start NAME
  labctl vm shutdown NAME
  labctl vm stop NAME
  labctl vm reboot NAME
  labctl vm suspend NAME
  labctl vm resume NAME
  labctl vm console NAME
  labctl vm help

Actions:
  shutdown    Graceful guest shutdown
  stop        Forced power off
  reboot      Graceful guest reboot
HELP
}

vm_require_virsh() {
    require_command virsh
}

vm_require_name() {
    local vm_name="${1:-}"

    if [[ -z "$vm_name" ]]; then
        print_error "A virtual machine name is required."
        print_info "List VMs with: labctl vm list"
        return 1
    fi

    if ! sudo virsh dominfo "$vm_name" >/dev/null 2>&1; then
        print_error "Virtual machine not found: $vm_name"
        return 1
    fi
}

vm_get_state() {
    sudo virsh domstate "$1" 2>/dev/null | tr '[:upper:]' '[:lower:]'
}

vm_list() {
    vm_require_virsh || return 1
    print_header "VIRTUAL MACHINES"
    sudo virsh list --all
}

vm_running() {
    vm_require_virsh || return 1
    print_header "RUNNING VIRTUAL MACHINES"
    sudo virsh list
}

vm_status() {
    local vm_name="${1:-}"
    vm_require_virsh || return 1
    vm_require_name "$vm_name" || return 1

    print_header "VIRTUAL MACHINE STATUS"
    sudo virsh dominfo "$vm_name"
}

vm_start() {
    local vm_name="${1:-}"
    local state

    vm_require_virsh || return 1
    vm_require_name "$vm_name" || return 1
    state="$(vm_get_state "$vm_name")"

    if [[ "$state" == "running" ]]; then
        print_warn "The VM is already running: $vm_name"
        return 0
    fi

    print_info "Starting VM: $vm_name"

    if sudo virsh start "$vm_name"; then
        print_ok "VM started successfully: $vm_name"
    else
        print_error "The VM could not be started: $vm_name"
        return 1
    fi
}

vm_shutdown() {
    local vm_name="${1:-}"
    local state

    vm_require_virsh || return 1
    vm_require_name "$vm_name" || return 1
    state="$(vm_get_state "$vm_name")"

    if [[ "$state" == "shut off" ]]; then
        print_warn "The VM is already powered off: $vm_name"
        return 0
    fi

    print_info "Requesting graceful shutdown: $vm_name"

    if sudo virsh shutdown "$vm_name"; then
        print_ok "Shutdown request sent to: $vm_name"
    else
        print_error "The shutdown request failed."
        return 1
    fi
}

vm_stop() {
    local vm_name="${1:-}"
    local state

    vm_require_virsh || return 1
    vm_require_name "$vm_name" || return 1
    state="$(vm_get_state "$vm_name")"

    if [[ "$state" == "shut off" ]]; then
        print_warn "The VM is already powered off: $vm_name"
        return 0
    fi

    print_warn "This will forcibly power off the VM: $vm_name"

    if ! confirm_action "Continue?"; then
        print_info "Operation cancelled."
        return 0
    fi

    if sudo virsh destroy "$vm_name"; then
        print_ok "VM forcibly stopped: $vm_name"
    else
        print_error "The VM could not be stopped."
        return 1
    fi
}

vm_reboot() {
    local vm_name="${1:-}"
    local state

    vm_require_virsh || return 1
    vm_require_name "$vm_name" || return 1
    state="$(vm_get_state "$vm_name")"

    if [[ "$state" != "running" ]]; then
        print_error "The VM is not running: $vm_name"
        return 1
    fi

    print_info "Requesting graceful reboot: $vm_name"

    if sudo virsh reboot "$vm_name"; then
        print_ok "Reboot request sent to: $vm_name"
    else
        print_error "The VM could not be rebooted."
        return 1
    fi
}

vm_suspend() {
    local vm_name="${1:-}"
    local state

    vm_require_virsh || return 1
    vm_require_name "$vm_name" || return 1
    state="$(vm_get_state "$vm_name")"

    if [[ "$state" != "running" ]]; then
        print_error "The VM is not running: $vm_name"
        return 1
    fi

    if sudo virsh suspend "$vm_name"; then
        print_ok "VM suspended: $vm_name"
    else
        print_error "The VM could not be suspended."
        return 1
    fi
}

vm_resume() {
    local vm_name="${1:-}"
    local state

    vm_require_virsh || return 1
    vm_require_name "$vm_name" || return 1
    state="$(vm_get_state "$vm_name")"

    if [[ "$state" != "paused" ]]; then
        print_error "The VM is not suspended: $vm_name"
        return 1
    fi

    if sudo virsh resume "$vm_name"; then
        print_ok "VM resumed: $vm_name"
    else
        print_error "The VM could not be resumed."
        return 1
    fi
}

vm_console() {
    local vm_name="${1:-}"
    local state

    vm_require_virsh || return 1
    vm_require_name "$vm_name" || return 1
    state="$(vm_get_state "$vm_name")"

    if [[ "$state" != "running" ]]; then
        print_error "The VM is not running: $vm_name"
        return 1
    fi

    print_info "Opening console for: $vm_name"
    print_info "Press Ctrl + ] to leave the console."
    sudo virsh console "$vm_name"
}

vm_dispatch() {
    local action="${1:-help}"
    shift || true

    case "$action" in
        list) vm_list ;;
        running) vm_running ;;
        status) vm_status "${1:-}" ;;
        start) vm_start "${1:-}" ;;
        shutdown) vm_shutdown "${1:-}" ;;
        stop) vm_stop "${1:-}" ;;
        reboot) vm_reboot "${1:-}" ;;
        suspend) vm_suspend "${1:-}" ;;
        resume) vm_resume "${1:-}" ;;
        console) vm_console "${1:-}" ;;
        help|-h|--help) vm_help ;;
        *)
            print_error "Unknown VM action: $action"
            vm_help
            return 1
            ;;
    esac
}
