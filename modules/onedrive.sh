#!/usr/bin/env bash

onedrive_help() {
    cat <<'HELP'
Usage:
  labctl onedrive status
  labctl onedrive start
  labctl onedrive stop
  labctl onedrive restart
  labctl onedrive sync
  labctl onedrive monitor
  labctl onedrive logs
  labctl onedrive config
  labctl onedrive help

Actions:
  status     Show service, process, version, and configuration status
  start      Start continuous synchronization
  stop       Stop continuous synchronization
  restart    Restart continuous synchronization
  sync       Run a one-time synchronization
  monitor    Start continuous synchronization
  logs       Show recent systemd user-service logs
  config     Show the effective OneDrive configuration
HELP
}

onedrive_require_command() {
    require_command onedrive
}

onedrive_user_service_exists() {
    systemctl --user list-unit-files onedrive.service \
        --no-legend 2>/dev/null |
        grep -q '^onedrive\.service'
}

onedrive_service_active() {
    systemctl --user is-active --quiet onedrive.service 2>/dev/null
}

onedrive_process_count() {
    pgrep -x onedrive 2>/dev/null | wc -l
}

onedrive_process_running() {
    pgrep -x onedrive >/dev/null 2>&1
}

onedrive_get_sync_dir() {
    onedrive --display-config 2>/dev/null |
        awk -F= '
            /Config option '\''sync_dir'\''/ {
                value=$2
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                print value
                found=1
            }
            END {
                if (!found) {
                    print "Not detected"
                }
            }
        '
}

onedrive_status() {
    local version
    local process_count
    local service_state_value="NOT INSTALLED"
    local enabled_state="NOT INSTALLED"
    local sync_dir

    onedrive_require_command || return 1

    version="$(onedrive --version 2>/dev/null | head -1 || true)"
    process_count="$(onedrive_process_count)"
    sync_dir="$(onedrive_get_sync_dir)"

    if onedrive_user_service_exists; then
        service_state_value="$(
            systemctl --user is-active onedrive.service 2>/dev/null ||
            true
        )"

        enabled_state="$(
            systemctl --user is-enabled onedrive.service 2>/dev/null ||
            true
        )"

        service_state_value="${service_state_value^^}"
        enabled_state="${enabled_state^^}"
    fi

    print_header "ONEDRIVE STATUS"

    printf "%-24s %s\n" \
        "Client Version:" \
        "${version:-Unknown}"

    printf "%-24s %s\n" \
        "User Service:" \
        "$service_state_value"

    printf "%-24s %s\n" \
        "Service Enabled:" \
        "$enabled_state"

    if onedrive_process_running; then
        printf "%-24s %s\n" "Process State:" "RUNNING"
    else
        printf "%-24s %s\n" "Process State:" "STOPPED"
    fi

    printf "%-24s %s\n" \
        "Process Count:" \
        "$process_count"

    printf "%-24s %s\n" \
        "Sync Directory:" \
        "$sync_dir"

    echo
    print_info "Running processes:"

    if onedrive_process_running; then
        pgrep -a -x onedrive
    else
        echo "None"
    fi
}

onedrive_start() {
    onedrive_require_command || return 1

    if onedrive_process_running; then
        print_warn "OneDrive is already running."
        pgrep -a -x onedrive
        return 0
    fi

    if onedrive_user_service_exists; then
        print_info "Starting the OneDrive user service..."

        if systemctl --user start onedrive.service; then
            sleep 2

            if onedrive_service_active; then
                print_ok "OneDrive user service is active."
            else
                print_error "The OneDrive service did not remain active."
                return 1
            fi
        else
            print_error "The OneDrive user service could not be started."
            return 1
        fi
    else
        local log_dir
        local log_file

        log_dir="${XDG_STATE_HOME:-$HOME/.local/state}"
        log_file="$log_dir/onedrive-monitor.log"

        mkdir -p "$log_dir"

        print_warn "The OneDrive user service is not installed."
        print_info "Starting OneDrive monitor mode directly..."

        nohup onedrive --monitor > "$log_file" 2>&1 &

        disown || true
        sleep 2

        if onedrive_process_running; then
            print_ok "OneDrive monitor mode is running."
        else
            print_error "OneDrive monitor mode could not be started."
            return 1
        fi
    fi
}

onedrive_stop() {
    local stopped_something=false

    onedrive_require_command || return 1

    if onedrive_user_service_exists && onedrive_service_active; then
        print_info "Stopping the OneDrive user service..."

        if systemctl --user stop onedrive.service; then
            stopped_something=true
        else
            print_error "The OneDrive user service could not be stopped."
            return 1
        fi
    fi

    if onedrive_process_running; then
        print_info "Stopping remaining OneDrive processes..."

        pkill -TERM -x onedrive 2>/dev/null || true

        for _ in {1..10}; do
            onedrive_process_running || break
            sleep 1
        done

        if onedrive_process_running; then
            print_warn "OneDrive did not stop gracefully. Forcing termination."
            pkill -KILL -x onedrive 2>/dev/null || true
        fi

        stopped_something=true
    fi

    if [[ "$stopped_something" == false ]]; then
        print_warn "OneDrive is already stopped."
        return 0
    fi

    if onedrive_process_running; then
        print_error "OneDrive is still running."
        return 1
    fi

    print_ok "OneDrive is stopped."
}

onedrive_restart() {
    print_info "Restarting OneDrive..."

    onedrive_stop || return 1
    onedrive_start
}

onedrive_sync() {
    local restart_after_sync=false

    onedrive_require_command || return 1

    if onedrive_process_running; then
        print_warn "OneDrive monitor mode is currently running."
        print_info "It must be stopped before a manual one-time sync."

        if ! confirm_action "Stop OneDrive, synchronize, and start it again?"; then
            print_info "Operation cancelled."
            return 0
        fi

        onedrive_stop || return 1
        restart_after_sync=true
    fi

    print_info "Starting one-time OneDrive synchronization..."

    if onedrive --synchronize; then
        print_ok "OneDrive synchronization completed."
    else
        print_error "OneDrive synchronization failed."

        if [[ "$restart_after_sync" == true ]]; then
            print_info "Restoring monitor mode..."
            onedrive_start || true
        fi

        return 1
    fi

    if [[ "$restart_after_sync" == true ]]; then
        print_info "Restoring continuous synchronization..."
        onedrive_start
    fi
}

onedrive_monitor() {
    onedrive_start
}

onedrive_logs() {
    if onedrive_user_service_exists; then
        print_header "ONEDRIVE LOGS"

        journalctl --user \
            -u onedrive.service \
            -n 100 \
            --no-pager
    else
        local log_file="${XDG_STATE_HOME:-$HOME/.local/state}/onedrive-monitor.log"

        print_header "ONEDRIVE LOGS"

        if [[ -r "$log_file" ]]; then
            tail -100 "$log_file"
        else
            print_warn "No OneDrive monitor log was found."
        fi
    fi
}

onedrive_config() {
    onedrive_require_command || return 1

    print_header "ONEDRIVE CONFIGURATION"

    onedrive --display-config
}

onedrive_dispatch() {
    local action="${1:-status}"

    case "$action" in
        status)
            onedrive_status
            ;;
        start)
            onedrive_start
            ;;
        stop)
            onedrive_stop
            ;;
        restart)
            onedrive_restart
            ;;
        sync)
            onedrive_sync
            ;;
        monitor)
            onedrive_monitor
            ;;
        logs)
            onedrive_logs
            ;;
        config)
            onedrive_config
            ;;
        help|-h|--help)
            onedrive_help
            ;;
        *)
            print_error "Unknown OneDrive action: $action"
            onedrive_help
            return 1
            ;;
    esac
}
