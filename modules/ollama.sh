#!/usr/bin/env bash

ollama_help() {
    cat <<'HELP'
Usage:
  labctl ollama start
  labctl ollama stop
  labctl ollama restart
  labctl ollama status
  labctl ollama models
  labctl ollama help
HELP
}

ollama_start() {
    print_info "Starting Ollama..."

    if ! run_privileged systemctl start ollama.service; then
        print_error "Ollama could not be started."
        return 1
    fi

    if service_is_active ollama.service; then
        print_ok "Ollama is active."
    else
        print_error "Ollama did not remain active."
        return 1
    fi
}

ollama_stop() {
    print_info "Stopping Ollama..."

    run_privileged systemctl stop ollama.service

    if service_is_active ollama.service; then
        print_error "Ollama is still active."
        return 1
    fi

    print_ok "Ollama is stopped."
}

ollama_restart() {
    print_info "Restarting Ollama..."

    run_privileged systemctl restart ollama.service

    if service_is_active ollama.service; then
        print_ok "Ollama restarted successfully."
    else
        print_error "Ollama could not be restarted."
        return 1
    fi
}

ollama_status() {
    print_header "OLLAMA"

    printf "%-20s %s\n" "Service:" "$(service_state ollama.service)"

    if service_is_active ollama.service; then
        echo
        print_info "Local port:"
        ss -lntp 2>/dev/null | grep ':11434' || true
    fi
}

ollama_models() {
    if ! service_is_active ollama.service; then
        print_warn "Ollama is stopped."
        print_info "Start it with: labctl ollama start"
        return 1
    fi

    require_command ollama || return 1
    ollama list
}

ollama_dispatch() {
    local action="${1:-help}"

    case "$action" in
        start) ollama_start ;;
        stop) ollama_stop ;;
        restart) ollama_restart ;;
        status) ollama_status ;;
        models) ollama_models ;;
        help|-h|--help) ollama_help ;;
        *)
            print_error "Unknown Ollama action: $action"
            ollama_help
            return 1
            ;;
    esac
}
