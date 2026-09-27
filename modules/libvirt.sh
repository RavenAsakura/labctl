#!/usr/bin/env bash

libvirt_help() {
    cat <<'HELP'
Usage:
  labctl libvirt status
  labctl libvirt start
  labctl libvirt stop
  labctl libvirt restart
  labctl libvirt backend
  labctl libvirt help
HELP
}

libvirt_unit_exists() {
    systemctl list-unit-files "$1" --no-legend 2>/dev/null |
        awk '{print $1}' |
        grep -Fxq "$1"
}

libvirt_backend() {
    if libvirt_unit_exists libvirtd.service; then
        printf 'classic\n'
    elif libvirt_unit_exists virtqemud.service ||
         libvirt_unit_exists virtqemud.socket; then
        printf 'modular\n'
    else
        printf 'unavailable\n'
    fi
}

libvirt_primary_service() {
    case "$(libvirt_backend)" in
        classic) printf 'libvirtd.service\n' ;;
        modular) printf 'virtqemud.service\n' ;;
        *) printf '\n' ;;
    esac
}

libvirt_is_active() {
    case "$(libvirt_backend)" in
        classic)
            service_is_active libvirtd.service
            ;;
        modular)
            service_is_active virtqemud.service ||
                service_is_active virtnetworkd.service
            ;;
        *)
            return 1
            ;;
    esac
}

libvirt_running_vm_count() {
    if ! command_exists virsh; then
        printf '0\n'
        return 0
    fi

    virsh -c qemu:///system list --state-running --name 2>/dev/null |
        awk 'NF {count++} END {print count+0}'
}

libvirt_start() {
    local backend
    backend="$(libvirt_backend)"

    if libvirt_is_active; then
        print_info "Libvirt is already active."
        return 0
    fi

    case "$backend" in
        classic)
            print_info "Starting classic libvirt service..."
            if run_privileged systemctl start libvirtd.service; then
                print_ok "Libvirt started."
            else
                print_error "Libvirt could not be started."
                return 1
            fi
            ;;
        modular)
            print_info "Starting modular libvirt sockets..."
            if run_privileged systemctl start virtlogd.socket virtnetworkd.socket virtqemud.socket; then
                print_ok "Libvirt socket activation is ready."
            else
                print_error "Modular libvirt could not be started."
                return 1
            fi
            ;;
        *)
            print_error "No supported libvirt backend was detected."
            return 1
            ;;
    esac
}

libvirt_stop() {
    local backend
    local running_vms

    backend="$(libvirt_backend)"
    running_vms="$(libvirt_running_vm_count)"

    if (( running_vms > 0 )); then
        print_error "Libvirt has $running_vms running virtual machine(s)."
        print_info "Shut them down before stopping libvirt."
        return 1
    fi

    if ! libvirt_is_active; then
        print_info "Libvirt services are already stopped."
        return 0
    fi

    case "$backend" in
        classic)
            print_info "Stopping classic libvirt services and sockets..."
            if run_privileged systemctl stop                 libvirtd.service                 libvirtd.socket                 libvirtd-ro.socket                 libvirtd-admin.socket                 virtlogd.service                 virtlogd.socket                 virtlogd-admin.socket; then
                print_ok "Libvirt services and sockets are fully stopped."
            else
                print_error "Libvirt could not be stopped cleanly."
                return 1
            fi
            ;;
        modular)
            print_info "Stopping modular libvirt services and sockets..."
            if run_privileged systemctl stop                 virtqemud.service                 virtqemud.socket                 virtnetworkd.service                 virtnetworkd.socket                 virtlogd.service                 virtlogd.socket; then
                print_ok "Libvirt services and sockets are fully stopped."
            else
                print_error "Libvirt could not be stopped cleanly."
                return 1
            fi
            ;;
        *)
            print_error "No supported libvirt backend was detected."
            return 1
            ;;
    esac
}

libvirt_restart() {
    libvirt_stop || return 1
    libvirt_start
}

libvirt_status() {
    local backend
    local primary
    local state
    local status_kind

    backend="$(libvirt_backend)"
    primary="$(libvirt_primary_service)"

    if libvirt_is_active; then
        state="ACTIVE"
        status_kind="active"
    else
        state="STOPPED"
        status_kind="warning"
    fi

    print_header "LIBVIRT STATUS"
    print_status_value "Backend:" "$backend" "info"
    print_status_value "Primary service:" "${primary:-Unavailable}" "normal"
    print_status_value "Service state:" "$state" "$status_kind"
    print_status_value "Running VMs:" "$(libvirt_running_vm_count)" "normal"

    echo

    case "$backend" in
        classic)
            printf "%-28s %s\n" "libvirtd.service:" "$(service_state libvirtd.service)"
            printf "%-28s %s\n" "libvirtd.socket:" "$(service_state libvirtd.socket)"
            printf "%-28s %s\n" "virtlogd.service:" "$(service_state virtlogd.service)"
            printf "%-28s %s\n" "virtlogd.socket:" "$(service_state virtlogd.socket)"
            ;;
        modular)
            printf "%-28s %s\n" "virtqemud.service:" "$(service_state virtqemud.service)"
            printf "%-28s %s\n" "virtqemud.socket:" "$(service_state virtqemud.socket)"
            printf "%-28s %s\n" "virtnetworkd.service:" "$(service_state virtnetworkd.service)"
            printf "%-28s %s\n" "virtnetworkd.socket:" "$(service_state virtnetworkd.socket)"
            printf "%-28s %s\n" "virtlogd.service:" "$(service_state virtlogd.service)"
            printf "%-28s %s\n" "virtlogd.socket:" "$(service_state virtlogd.socket)"
            ;;
        *)
            print_warn "No supported libvirt systemd units were found."
            ;;
    esac
}

libvirt_dispatch() {
    local action="${1:-status}"

    case "$action" in
        status) libvirt_status ;;
        start) libvirt_start ;;
        stop) libvirt_stop ;;
        restart) libvirt_restart ;;
        backend) libvirt_backend ;;
        help|-h|--help) libvirt_help ;;
        *)
            print_error "Unknown libvirt action: $action"
            libvirt_help
            return 1
            ;;
    esac
}
