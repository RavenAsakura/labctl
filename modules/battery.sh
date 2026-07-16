#!/usr/bin/env bash

battery_help() {
    cat <<'HELP'
Usage:
  labctl battery status
  labctl battery health
  labctl battery thresholds
  labctl battery help
HELP
}

battery_get_device() {
    upower -e 2>/dev/null |
        grep '/battery_' |
        head -1
}

battery_require_device() {
    local battery_device

    battery_device="$(battery_get_device)"

    if [[ -z "$battery_device" ]]; then
        print_error "No battery device was detected."
        return 1
    fi
}

battery_status() {
    local battery_device

    require_command upower || return 1
    battery_require_device || return 1

    battery_device="$(battery_get_device)"

    print_header "BATTERY STATUS"

    upower -i "$battery_device" 2>/dev/null |
    awk -F: '
        /vendor:/ {
            gsub(/^[ \t]+/, "", $2)
            printf "%-24s %s\n", "Vendor:", $2
        }
        /model:/ {
            gsub(/^[ \t]+/, "", $2)
            printf "%-24s %s\n", "Model:", $2
        }
        /^[[:space:]]*state:/ {
            gsub(/^[ \t]+/, "", $2)
            printf "%-24s %s\n", "State:", $2
        }
        /^[[:space:]]*percentage:/ {
            gsub(/^[ \t]+/, "", $2)
            printf "%-24s %s\n", "Charge:", $2
        }
        /^[[:space:]]*capacity:/ {
            gsub(/^[ \t]+/, "", $2)
            printf "%-24s %s\n", "Health:", $2
        }
        /energy-full:/ && !/design/ {
            gsub(/^[ \t]+/, "", $2)
            printf "%-24s %s\n", "Full Capacity:", $2
        }
        /energy-full-design:/ {
            gsub(/^[ \t]+/, "", $2)
            printf "%-24s %s\n", "Design Capacity:", $2
        }
        /energy-rate:/ {
            gsub(/^[ \t]+/, "", $2)
            printf "%-24s %s\n", "Power Rate:", $2
        }
        /^[[:space:]]*voltage:/ {
            gsub(/^[ \t]+/, "", $2)
            printf "%-24s %s\n", "Voltage:", $2
        }
        /charge-cycles:/ {
            gsub(/^[ \t]+/, "", $2)
            printf "%-24s %s\n", "Charge Cycles:", $2
        }
        /time to empty:/ {
            gsub(/^[ \t]+/, "", $2)
            printf "%-24s %s\n", "Time to Empty:", $2
        }
        /time to full:/ {
            gsub(/^[ \t]+/, "", $2)
            printf "%-24s %s\n", "Time to Full:", $2
        }
        /charge-start-threshold:/ {
            gsub(/^[ \t]+/, "", $2)
            printf "%-24s %s\n", "Charge Start:", $2
        }
        /charge-end-threshold:/ {
            gsub(/^[ \t]+/, "", $2)
            printf "%-24s %s\n", "Charge Limit:", $2
        }
    '

    echo

    if command_exists tuned-adm; then
        printf "%-24s %s\n" \
            "TuneD Profile:" \
            "$(tuned-adm active 2>/dev/null | sed 's/Current active profile: //')"
    fi

    if systemctl is-active --quiet intel_lpmd.service 2>/dev/null; then
        printf "%-24s %s\n" "Intel LPMD:" "ACTIVE"
    else
        printf "%-24s %s\n" "Intel LPMD:" "STOPPED"
    fi
}

battery_health() {
    local battery_device
    local full
    local design
    local health

    require_command upower || return 1
    battery_require_device || return 1

    battery_device="$(battery_get_device)"

    full="$(
        upower -i "$battery_device" 2>/dev/null |
        awk '/energy-full:/ && !/design/ {print $2; exit}'
    )"

    design="$(
        upower -i "$battery_device" 2>/dev/null |
        awk '/energy-full-design:/ {print $2; exit}'
    )"

    health="$(
        upower -i "$battery_device" 2>/dev/null |
        awk '/^[[:space:]]*capacity:/ {print $2; exit}'
    )"

    print_header "BATTERY HEALTH"

    printf "%-24s %s Wh\n" "Full Capacity:" "${full:-N/A}"
    printf "%-24s %s Wh\n" "Design Capacity:" "${design:-N/A}"
    printf "%-24s %s\n" "Reported Health:" "${health:-N/A}"

    if [[ -n "$full" && -n "$design" ]]; then
        awk -v full="$full" -v design="$design" '
            BEGIN {
                if (design > 0) {
                    printf "%-24s %.2f %%\n", "Calculated Health:", (full / design) * 100
                }
            }
        '
    fi
}

battery_thresholds() {
    local battery_device

    require_command upower || return 1
    battery_require_device || return 1

    battery_device="$(battery_get_device)"

    print_header "BATTERY CHARGE THRESHOLDS"

    upower -i "$battery_device" 2>/dev/null |
    awk -F: '
        /charge-start-threshold:/ {
            gsub(/^[ \t]+/, "", $2)
            printf "%-24s %s\n", "Charge Start:", $2
        }
        /charge-end-threshold:/ {
            gsub(/^[ \t]+/, "", $2)
            printf "%-24s %s\n", "Charge Limit:", $2
        }
        /charge-threshold-supported:/ {
            gsub(/^[ \t]+/, "", $2)
            printf "%-24s %s\n", "Threshold Support:", $2
        }
    '
}

battery_dispatch() {
    local action="${1:-status}"

    case "$action" in
        status)
            battery_status
            ;;
        health)
            battery_health
            ;;
        thresholds)
            battery_thresholds
            ;;
        help|-h|--help)
            battery_help
            ;;
        *)
            print_error "Unknown battery action: $action"
            battery_help
            return 1
            ;;
    esac
}
