#!/usr/bin/env bash

docker_help() {
    cat <<'HELP'
Usage:
  labctl docker start
  labctl docker stop
  labctl docker restart
  labctl docker status
  labctl docker ps
  labctl docker logs CONTAINER
  labctl docker restart-container CONTAINER
  labctl docker help
HELP
}

docker_unit_exists() {
    local unit="${1:?Missing systemd unit name}"
    local load_state

    load_state="$(
        systemctl show \
            --property=LoadState \
            --value \
            "$unit" 2>/dev/null || true
    )"

    [[ -n "$load_state" && "$load_state" != "not-found" ]]
}

docker_installed() {
    command_exists docker &&
        (
            docker_unit_exists docker.service ||
            docker_unit_exists docker.socket ||
            docker_unit_exists containerd.service
        )
}

docker_require_installed() {
    if docker_installed; then
        return 0
    fi

    print_warn "Docker is not installed."
    return 1
}

docker_start() {
    if ! docker_installed; then
        print_info "Docker is not installed. Skipping."
        return 0
    fi

    if service_is_active docker.service; then
        print_info "Docker is already active."
        return 0
    fi

    print_info "Starting Docker..."

    if ! run_privileged systemctl start docker.service; then
        print_error "Docker could not be started."
        return 1
    fi

    if service_is_active docker.service; then
        print_ok "Docker is active."
        print_info "Containerd: $(service_state containerd.service)"
    else
        print_error "Docker did not remain active."
        return 1
    fi
}

docker_stop() {
    local running_containers
    local -a units=()

    if ! docker_installed; then
        print_info "Docker is not installed. Skipping."
        return 0
    fi

    if service_is_active docker.service; then
        print_info "Stopping running containers..."
        running_containers="$(run_privileged docker ps -q 2>/dev/null || true)"

        if [[ -n "$running_containers" ]]; then
            # shellcheck disable=SC2086
            run_privileged docker stop $running_containers || return 1
        fi
    fi

    docker_unit_exists docker.service && units+=(docker.service)
    docker_unit_exists docker.socket && units+=(docker.socket)
    docker_unit_exists containerd.service && units+=(containerd.service)

    if (( ${#units[@]} == 0 )); then
        print_info "Docker is already stopped."
        return 0
    fi

    print_info "Stopping Docker, its socket, and containerd..."

    if ! run_privileged systemctl stop "${units[@]}"; then
        print_error "Docker or containerd could not be stopped."
        return 1
    fi

    if service_is_active docker.service ||
       service_is_active docker.socket ||
       service_is_active containerd.service; then
        print_error "Docker or containerd is still active."
        return 1
    fi

    print_ok "Docker and containerd are stopped."
}

docker_restart() {
    if ! docker_require_installed; then
        return 1
    fi

    print_info "Restarting Docker..."

    if ! run_privileged systemctl restart docker.service; then
        print_error "Docker could not be restarted."
        return 1
    fi

    if service_is_active docker.service; then
        print_ok "Docker restarted successfully."
    else
        print_error "Docker did not remain active."
        return 1
    fi
}

docker_status() {
    print_header "DOCKER"

    if ! docker_installed; then
        print_status_value "Installation:" "NOT INSTALLED" "warning"
        return 0
    fi

    print_status_value "Docker:" "$(service_state docker.service)" "normal"
    print_status_value "Docker Socket:" "$(service_state docker.socket)" "normal"
    print_status_value "Containerd:" "$(service_state containerd.service)" "normal"

    if service_is_active docker.service; then
        echo
        print_info "Containers:"
        run_privileged docker ps --format \
            'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
    fi
}

docker_ps() {
    if ! docker_require_installed; then
        return 1
    fi

    if ! service_is_active docker.service; then
        print_warn "Docker is stopped."
        print_info "Start it with: labctl docker start"
        return 1
    fi

    run_privileged docker ps --format \
        'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
}

docker_logs() {
    local container_name="${1:-}"

    if ! docker_require_installed; then
        return 1
    fi

    if [[ -z "$container_name" ]]; then
        print_error "A container name is required."
        echo "Example: labctl docker logs open-webui"
        return 1
    fi

    if ! service_is_active docker.service; then
        print_error "Docker is stopped."
        return 1
    fi

    run_privileged docker logs --tail 100 --follow "$container_name"
}

docker_restart_container() {
    local container_name="${1:-}"

    if ! docker_require_installed; then
        return 1
    fi

    if [[ -z "$container_name" ]]; then
        print_error "A container name is required."
        echo "Example: labctl docker restart-container open-webui"
        return 1
    fi

    if ! service_is_active docker.service; then
        print_error "Docker is stopped."
        return 1
    fi

    run_privileged docker restart "$container_name"
    print_ok "Container restarted: $container_name"
}

docker_dispatch() {
    local action="${1:-help}"
    shift || true

    case "$action" in
        start) docker_start ;;
        stop) docker_stop ;;
        restart) docker_restart ;;
        status) docker_status ;;
        ps) docker_ps ;;
        logs) docker_logs "${1:-}" ;;
        restart-container) docker_restart_container "${1:-}" ;;
        help|-h|--help) docker_help ;;
        *)
            print_error "Unknown Docker action: $action"
            docker_help
            return 1
            ;;
    esac
}
