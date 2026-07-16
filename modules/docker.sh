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

docker_start() {
    print_info "Starting Docker..."

    if ! sudo systemctl start docker.service; then
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
    print_info "Stopping running containers..."

    if service_is_active docker.service; then
        local running_containers
        running_containers="$(sudo docker ps -q 2>/dev/null || true)"

        if [[ -n "$running_containers" ]]; then
            sudo docker stop $running_containers
        fi
    fi

    print_info "Stopping Docker, its socket, and containerd..."

    sudo systemctl stop \
        docker.service \
        docker.socket \
        containerd.service

    if service_is_active docker.service; then
        print_error "Docker is still active."
        return 1
    fi

    print_ok "Docker and containerd are stopped."
}

docker_restart() {
    print_info "Restarting Docker..."

    sudo systemctl restart docker.service

    if service_is_active docker.service; then
        print_ok "Docker restarted successfully."
    else
        print_error "Docker could not be restarted."
        return 1
    fi
}

docker_status() {
    print_header "DOCKER"

    printf "%-22s %s\n" "Docker:" "$(service_state docker.service)"
    printf "%-22s %s\n" "Docker Socket:" "$(service_state docker.socket)"
    printf "%-22s %s\n" "Containerd:" "$(service_state containerd.service)"

    if service_is_active docker.service; then
        echo
        print_info "Containers:"
        sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
    fi
}

docker_ps() {
    if ! service_is_active docker.service; then
        print_warn "Docker is stopped."
        print_info "Start it with: labctl docker start"
        return 1
    fi

    sudo docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
}

docker_logs() {
    local container_name="${1:-}"

    if [[ -z "$container_name" ]]; then
        print_error "A container name is required."
        echo "Example: labctl docker logs open-webui"
        return 1
    fi

    if ! service_is_active docker.service; then
        print_error "Docker is stopped."
        return 1
    fi

    sudo docker logs --tail 100 --follow "$container_name"
}

docker_restart_container() {
    local container_name="${1:-}"

    if [[ -z "$container_name" ]]; then
        print_error "A container name is required."
        echo "Example: labctl docker restart-container open-webui"
        return 1
    fi

    if ! service_is_active docker.service; then
        print_error "Docker is stopped."
        return 1
    fi

    sudo docker restart "$container_name"
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
