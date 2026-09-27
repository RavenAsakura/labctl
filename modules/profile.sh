#!/usr/bin/env bash

readonly LABCTL_PROFILE_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/labctl"
readonly LABCTL_PROFILE_STATE_FILE="$LABCTL_PROFILE_STATE_DIR/profile"

profile_help() {
    cat <<'HELP'
Usage:
  labctl profile status
  labctl profile current

Configuration:
  labctl [work|travel] [COMPONENT...] [OPTIONS]
  labctl COMPONENT [COMPONENT...] [OPTIONS]

Options:
  --dry-run   Show the planned changes without applying them
  --yes, -y   Apply changes without an interactive confirmation

Power selectors:
  work      balanced
  travel    power-saver

Components:
  qemu      QEMU / Libvirt
  docker    Docker / Containerd
  vmware    VMware Workstation
  vbox      VirtualBox
  ai        Ollama

If neither 'work' nor 'travel' is specified, performance mode is used.

Examples:
  labctl work
  labctl work vmware
  labctl work qemu docker
  labctl travel
  labctl travel qemu
  labctl qemu
  labctl qemu vmware
  labctl qemu vmware docker
  labctl docker ai

Notes:
  'work' and 'travel' cannot be used together.
  Components not listed in the command are stopped.
  Confirmation is required before active components are stopped.
HELP
}

profile_load_modules() {
    load_module docker || return 1
    load_module libvirt || return 1
    load_module vmware || return 1
    load_module virtualbox || return 1
    load_module ollama || return 1
    load_module power || return 1
}

profile_saved_name() {
    if [[ -r "$LABCTL_PROFILE_STATE_FILE" ]]; then
        cat "$LABCTL_PROFILE_STATE_FILE"
    else
        printf 'unmanaged\n'
    fi
}

profile_save_name() {
    mkdir -p "$LABCTL_PROFILE_STATE_DIR"
    printf '%s\n' "$*" > "$LABCTL_PROFILE_STATE_FILE"
}

profile_token_valid() {
    case "${1:-}" in
        work|travel|qemu|docker|vmware|vbox|ai)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

profile_component_requested() {
    local wanted="${1:?Missing component}"
    shift

    local item

    for item in "$@"; do
        [[ "$item" == "$wanted" ]] && return 0
    done

    return 1
}

profile_set_power() {
    local requested="${1:?Missing power profile}"

    if [[ "$(power_backend)" == "unavailable" ]]; then
        print_warn "No supported power-profile backend is available."
        return 0
    fi

    power_set "$requested"
}

profile_stop_vmware() {
    if service_is_active vmware.service ||
       service_is_active vmware-USBArbitrator.service; then
        vmware_stop
    else
        print_info "VMware is already stopped."
    fi
}

profile_start_vmware() {
    if service_is_active vmware.service; then
        print_info "VMware is already active."
    else
        vmware_start
    fi
}

profile_stop_virtualbox() {
    if ! virtualbox_installed; then
        print_info "VirtualBox is not installed. Skipping."
        return 0
    fi

    virtualbox_stop
}

profile_start_virtualbox() {
    if ! virtualbox_installed; then
        print_info "VirtualBox is not installed. Skipping."
        return 0
    fi

    virtualbox_start
}

profile_stop_ollama() {
    if service_is_active ollama.service; then
        ollama_stop
    else
        print_info "Ollama is already stopped."
    fi
}

profile_start_ollama() {
    if service_is_active ollama.service; then
        print_info "Ollama is already active."
    else
        ollama_start
    fi
}

profile_docker_state() {
    if docker_installed && service_is_active docker.service; then
        printf 'ACTIVE\n'
    else
        printf 'STOPPED\n'
    fi
}

profile_containerd_state() {
    if service_is_active containerd.service; then
        printf 'ACTIVE\n'
    else
        printf 'STOPPED\n'
    fi
}

profile_qemu_state() {
    if libvirt_is_active; then
        printf 'ACTIVE\n'
    else
        printf 'STOPPED\n'
    fi
}

profile_vmware_state() {
    if service_is_active vmware.service; then
        printf 'ACTIVE\n'
    else
        printf 'STOPPED\n'
    fi
}

profile_vbox_state() {
    if virtualbox_installed && virtualbox_driver_loaded; then
        printf 'ACTIVE\n'
    else
        printf 'STOPPED\n'
    fi
}

profile_ai_state() {
    if service_is_active ollama.service; then
        printf 'ACTIVE\n'
    else
        printf 'STOPPED\n'
    fi
}

profile_component_active() {
    case "${1:?Missing component}" in
        docker)
            service_is_active docker.service ||
                service_is_active docker.socket ||
                service_is_active containerd.service
            ;;
        qemu)
            libvirt_is_active
            ;;
        vmware)
            service_is_active vmware.service ||
                service_is_active vmware-USBArbitrator.service
            ;;
        vbox)
            virtualbox_installed && virtualbox_driver_loaded
            ;;
        ai)
            service_is_active ollama.service
            ;;
        *)
            return 1
            ;;
    esac
}

profile_apply_component() {
    local component="${1:?Missing component}"
    local desired="${2:?Missing desired state}"

    if [[ "$desired" == "active" ]]; then
        case "$component" in
            docker)
                if profile_component_active docker; then
                    print_info "Docker is already active."
                else
                    docker_start
                fi
                ;;
            qemu)
                if profile_component_active qemu; then
                    print_info "QEMU/Libvirt is already active."
                else
                    libvirt_start
                fi
                ;;
            vmware) profile_start_vmware ;;
            vbox) profile_start_virtualbox ;;
            ai) profile_start_ollama ;;
        esac
    else
        case "$component" in
            docker) docker_stop ;;
            qemu) libvirt_stop ;;
            vmware) profile_stop_vmware ;;
            vbox) profile_stop_virtualbox ;;
            ai) profile_stop_ollama ;;
        esac
    fi
}

profile_restore_state() {
    local previous_power="${1:-unavailable}"
    shift

    local component
    local state

    print_warn "Restoring the previous component state..."

    while (( $# >= 2 )); do
        component="$1"
        state="$2"
        shift 2

        profile_apply_component "$component" "$state" ||
            print_error "Could not restore component: $component"
    done

    if [[ "$previous_power" != "unavailable" ]]; then
        profile_set_power "$previous_power" ||
            print_error "Could not restore power profile: $previous_power"
    fi
}

profile_apply_selection() {
    local -a arguments=("$@")
    local -a tokens=()
    local -a components=()
    local -a stopping=()
    local -a previous_states=()
    local -a known_components=(docker qemu vmware vbox ai)

    local power_mode="performance"
    local previous_power="unavailable"
    local has_work=0
    local has_travel=0
    local dry_run=0
    local assume_yes=0
    local token
    local component
    local desired

    if (( ${#arguments[@]} == 0 )); then
        print_error "No configuration was specified."
        return 1
    fi

    for token in "${arguments[@]}"; do
        case "$token" in
            --dry-run)
                dry_run=1
                continue
                ;;
            --yes|-y)
                assume_yes=1
                continue
                ;;
        esac

        if ! profile_token_valid "$token"; then
            print_error "Unknown configuration token: $token"
            return 1
        fi

        tokens+=("$token")

        case "$token" in
            work)
                has_work=1
                ;;
            travel)
                has_travel=1
                ;;
            qemu|docker|vmware|vbox|ai)
                if ! profile_component_requested "$token" "${components[@]}"; then
                    components+=("$token")
                fi
                ;;
        esac
    done

    if (( has_work && has_travel )); then
        print_error "'work' and 'travel' cannot be used together."
        return 1
    fi

    if (( ${#tokens[@]} == 0 )); then
        print_error "No configuration was specified."
        return 1
    fi

    if (( has_work )); then
        power_mode="balanced"
    elif (( has_travel )); then
        power_mode="power-saver"
    fi

    profile_load_modules || return 1

    previous_power="$(power_current)"

    for component in "${known_components[@]}"; do
        if profile_component_active "$component"; then
            previous_states+=("$component" active)

            if ! profile_component_requested "$component" "${components[@]}"; then
                stopping+=("$component")
            fi
        else
            previous_states+=("$component" stopped)
        fi
    done

    print_header "APPLYING LAB CONFIGURATION"

    print_status_value "Power profile:" "$power_mode" "info"
    print_status_value \
        "Enabled components:" \
        "${components[*]:-none}" \
        "normal"

    if (( ${#stopping[@]} > 0 )); then
        print_warn "Active components to stop: ${stopping[*]}"
    fi

    if (( dry_run )); then
        print_info "Dry run: no services or settings were changed."
        return 0
    fi

    if (( ${#stopping[@]} > 0 && ! assume_yes )); then
        if [[ ! -t 0 ]]; then
            print_error "Confirmation requires a terminal. Use --yes to apply."
            return 1
        fi

        if ! confirm_action "Apply this configuration?"; then
            print_info "Operation cancelled."
            return 0
        fi
    fi

    for component in "${known_components[@]}"; do
        desired="stopped"

        if profile_component_requested "$component" "${components[@]}"; then
            desired="active"
        fi

        if ! profile_apply_component "$component" "$desired"; then
            print_error "Configuration failed while applying: $component"
            profile_restore_state "$previous_power" "${previous_states[@]}"
            return 1
        fi
    done

    #
    # Power
    #
    if ! profile_set_power "$power_mode"; then
        print_error "Configuration failed while applying the power profile."
        profile_restore_state "$previous_power" "${previous_states[@]}"
        return 1
    fi

    profile_save_name "${tokens[@]}"

    echo
    print_info "Power mode: $power_mode"

    if (( ${#components[@]} == 0 )); then
        print_info "Enabled components: none"
    else
        print_info "Enabled components:"
        for token in "${components[@]}"; do
            printf '  %s\n' "$token"
        done
    fi

    print_ok "Lab configuration applied."
}

profile_status() {
    profile_load_modules || return 1

    print_header "WORKSTATION CONFIGURATION"

    print_status_value \
        "Selected configuration:" \
        "$(profile_saved_name)" \
        "info"

    print_status_value \
        "Power backend:" \
        "$(power_backend)" \
        "normal"

    print_status_value \
        "Power profile:" \
        "$(power_current)" \
        "normal"

    print_status_value \
        "Docker:" \
        "$(profile_docker_state)" \
        "normal"

    print_status_value \
        "Containerd:" \
        "$(profile_containerd_state)" \
        "normal"

    print_status_value \
        "Libvirt backend:" \
        "$(libvirt_backend)" \
        "normal"

    print_status_value \
        "QEMU/Libvirt:" \
        "$(profile_qemu_state)" \
        "normal"

    print_status_value \
        "VMware:" \
        "$(profile_vmware_state)" \
        "normal"

    print_status_value \
        "VirtualBox:" \
        "$(profile_vbox_state)" \
        "normal"

    print_status_value \
        "Ollama:" \
        "$(profile_ai_state)" \
        "normal"
}

profile_dispatch() {
    local action="${1:-status}"
    shift || true

    case "$action" in
        status)
            profile_status
            ;;

        current)
            profile_saved_name
            ;;

        help|-h|--help)
            profile_help
            ;;

        work|travel|qemu|docker|vmware|vbox|ai|--dry-run|--yes|-y)
            profile_apply_selection "$action" "$@"
            ;;

        *)
            print_error "Unknown profile action: $action"
            profile_help
            return 1
            ;;
    esac
}
