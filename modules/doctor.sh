#!/usr/bin/env bash

doctor_help() {
    cat <<'HELP'
Usage:
  labctl doctor
  labctl doctor run
  labctl doctor help

Description:
  Runs a read-only workstation and lab diagnostic.

Result levels:
  PASS       Healthy condition
  INFO       Useful information that requires no immediate action
  WARNING    A condition worth reviewing
  ERROR      A problem requiring action

Checks:
  - Failed system and user services
  - UFW/Firewalld and AppArmor/SELinux
  - Battery health and charge thresholds
  - Docker, VMware, Ollama, and libvirt state
  - Running virtual machines
  - OneDrive service and process count
  - NVIDIA temperature, usage, power, and runtime PM
  - Filesystem usage
  - Weekly TRIM
  - Available APT or DNF package updates

This module does not modify the system.
HELP
}

doctor_passed=0
doctor_information=0
doctor_warnings=0
doctor_failed=0
doctor_recommendations=()

doctor_pass() {
    print_pass "$1"
    doctor_passed=$((doctor_passed + 1))
}

doctor_info() {
    print_info "$1"
    doctor_information=$((doctor_information + 1))
}

doctor_warning() {
    print_warn "$1"
    doctor_warnings=$((doctor_warnings + 1))
}

doctor_failure() {
    print_error "$1"
    doctor_failed=$((doctor_failed + 1))
}

doctor_recommend() {
    local recommendation="${1:-}"

    [[ -n "$recommendation" ]] || return 0
    doctor_recommendations+=("$recommendation")
}

doctor_check_failed_services() {
    local system_failed
    local user_failed

    system_failed="$(
        systemctl --failed \
            --no-legend \
            --plain \
            2>/dev/null |
        sed '/^[[:space:]]*$/d' |
        wc -l
    )"

    user_failed="$(
        systemctl --user --failed \
            --no-legend \
            --plain \
            2>/dev/null |
        sed '/^[[:space:]]*$/d' |
        wc -l
    )"

    if (( system_failed == 0 )); then
        doctor_pass "No failed system services."
    else
        doctor_failure "$system_failed failed system service(s)."
        doctor_recommend "Review failed system services with: systemctl --failed"
        systemctl --failed --no-pager
    fi

    if (( user_failed == 0 )); then
        doctor_pass "No failed user services."
    else
        doctor_failure "$user_failed failed user service(s)."
        doctor_recommend \
            "Review failed user services with: systemctl --user --failed"
        systemctl --user --failed --no-pager
    fi
}

doctor_check_security() {
    local ufw_enabled="no"

    if command_exists ufw &&
       [[ -r /etc/ufw/ufw.conf ]] &&
       grep -Eq '^[[:space:]]*ENABLED=yes([[:space:]]|$)' /etc/ufw/ufw.conf; then
        ufw_enabled="yes"
    fi

    if [[ "$ufw_enabled" == "yes" ]]; then
        doctor_pass "UFW is enabled."
    elif command_exists firewall-cmd && service_is_active firewalld.service; then
        doctor_pass "Firewalld is active."
    elif command_exists ufw; then
        doctor_failure "UFW is disabled."
        doctor_recommend "Review UFW rules and enable it with: sudo ufw enable"
    elif command_exists firewall-cmd; then
        doctor_failure "Firewalld is inactive."
        doctor_recommend "Start Firewalld and review its active zones."
    else
        doctor_warning "No supported firewall frontend was detected."
        doctor_recommend "Install and configure UFW or Firewalld."
    fi

    if [[ -r /sys/module/apparmor/parameters/enabled ]] &&
       grep -qi '^Y' /sys/module/apparmor/parameters/enabled; then
        doctor_pass "AppArmor is enabled."
    elif command_exists aa-status; then
        if aa-status --enabled >/dev/null 2>&1; then
            doctor_pass "AppArmor is enabled."
        else
            doctor_failure "AppArmor is disabled."
            doctor_recommend "Review the AppArmor service and kernel configuration."
        fi
    elif command_exists getenforce; then
        case "$(getenforce)" in
            Enforcing)
                doctor_pass "SELinux is enforcing."
                ;;
            Permissive)
                doctor_warning "SELinux is permissive."
                doctor_recommend \
                    "Review why SELinux is permissive before enabling enforcing mode."
                ;;
            Disabled)
                doctor_failure "SELinux is disabled."
                doctor_recommend \
                    "Review the SELinux configuration and restore protection."
                ;;
            *)
                doctor_warning "SELinux state could not be determined."
                ;;
        esac
    else
        doctor_warning "Neither AppArmor nor SELinux was detected."
    fi
}

doctor_check_battery() {
    local battery_device
    local capacity
    local start_threshold
    local end_threshold
    local cycles

    if ! command_exists upower; then
        doctor_info "UPower is unavailable."
        return 0
    fi

    battery_device="$(
        upower -e 2>/dev/null |
        grep '/battery_' |
        head -1
    )"

    if [[ -z "$battery_device" ]]; then
        doctor_info "No battery was detected."
        return 0
    fi

    capacity="$(
        upower -i "$battery_device" 2>/dev/null |
        awk '/^[[:space:]]*capacity:/ {
            gsub(/%/, "", $2)
            print int($2)
            exit
        }'
    )"

    cycles="$(
        upower -i "$battery_device" 2>/dev/null |
        awk '/charge-cycles:/ {
            print $2
            exit
        }'
    )"

    start_threshold="$(
        upower -i "$battery_device" 2>/dev/null |
        awk '/charge-start-threshold:/ {
            gsub(/%/, "", $2)
            print int($2)
            exit
        }'
    )"

    end_threshold="$(
        upower -i "$battery_device" 2>/dev/null |
        awk '/charge-end-threshold:/ {
            gsub(/%/, "", $2)
            print int($2)
            exit
        }'
    )"

    if [[ -n "$capacity" ]]; then
        if (( capacity >= 80 )); then
            doctor_pass "Battery health is ${capacity}%."
        elif (( capacity >= 60 )); then
            doctor_warning "Battery health is ${capacity}%."
            doctor_recommend "Monitor battery degradation."
        else
            doctor_failure "Battery health is only ${capacity}%."
            doctor_recommend "Consider battery replacement."
        fi
    else
        doctor_info "Battery health could not be determined."
    fi

    if [[ -n "$cycles" ]]; then
        doctor_info "Battery charge cycles: $cycles."
    fi

    if [[ "$start_threshold" == "75" &&
          "$end_threshold" == "80" ]]; then
        doctor_pass "Battery thresholds are configured at 75% / 80%."
    elif [[ -n "$start_threshold" &&
            -n "$end_threshold" ]]; then
        doctor_info \
            "Battery thresholds are ${start_threshold}% / ${end_threshold}%."
    else
        doctor_info "Battery thresholds could not be determined."
    fi
}

doctor_check_lab_services() {
    local running_vms

    if service_is_active docker.service; then
        doctor_info "Docker is active."
    else
        doctor_pass "Docker is stopped when not required."
    fi

    if service_is_active containerd.service; then
        doctor_info "Containerd is active."
    else
        doctor_pass "Containerd is stopped when not required."
    fi

    if service_is_active vmware.service; then
        doctor_info "VMware is active."
    else
        doctor_pass "VMware is stopped when not required."
    fi

    if service_is_active ollama.service; then
        doctor_info "Ollama is active."
    else
        doctor_pass "Ollama is stopped when not required."
    fi

    if ! command_exists virsh; then
        doctor_info "virsh is unavailable."
        return 0
    fi

    if ! running_vms="$(
        virsh -c qemu:///system list --name 2>/dev/null |
            sed '/^[[:space:]]*$/d'
    )"; then
        doctor_warning "Libvirt virtual machines could not be queried as the current user."
        doctor_recommend "Add the user to the libvirt group and start a new session."
        return 0
    fi

    if [[ -n "$running_vms" ]]; then
        doctor_info "Running libvirt virtual machines:"
        printf '%s\n' "$running_vms" |
            sed 's/^/          /'
    else
        doctor_pass "No libvirt virtual machines are running."
    fi
}

doctor_check_onedrive() {
    local process_count

    process_count="$(
        pgrep -x onedrive 2>/dev/null |
        wc -l
    )"

    if systemctl --user is-active --quiet onedrive.service; then
        doctor_pass "OneDrive user service is active."
    else
        doctor_info "OneDrive user service is currently inactive."
    fi

    case "$process_count" in
        0)
            doctor_info "No OneDrive process is running."
            ;;
        1)
            doctor_pass "Exactly one OneDrive process is running."
            ;;
        *)
            doctor_failure \
                "$process_count OneDrive processes are running."
            doctor_recommend \
                "Stop duplicate OneDrive processes and keep one monitor instance."
            pgrep -a -x onedrive |
                sed 's/^/          /'
            ;;
    esac
}

doctor_check_nvidia() {
    local gpu_data
    local gpu_temp
    local gpu_power
    local gpu_util
    local runtime_status="unknown"
    local gpu_slot
    local gpu_path

    if ! command_exists nvidia-smi; then
        doctor_info "NVIDIA GPU or nvidia-smi was not detected."
        return 0
    fi

    gpu_data="$(
        nvidia-smi \
            --query-gpu=temperature.gpu,power.draw,utilization.gpu \
            --format=csv,noheader,nounits \
            2>/dev/null |
        head -1
    )"

    if [[ -z "$gpu_data" ]]; then
        doctor_info "NVIDIA GPU status could not be read."
        return 0
    fi

    IFS=',' read -r gpu_temp gpu_power gpu_util <<< "$gpu_data"

    gpu_temp="$(xargs <<< "$gpu_temp")"
    gpu_power="$(xargs <<< "$gpu_power")"
    gpu_util="$(xargs <<< "$gpu_util")"

    gpu_slot="$(
        lspci -D 2>/dev/null |
        awk '
            /NVIDIA Corporation/ &&
            ($0 ~ /VGA compatible controller|3D controller|Display controller/) {
                print $1
                exit
            }
        '
    )"

    if [[ -n "$gpu_slot" ]]; then
        gpu_path="/sys/bus/pci/devices/$gpu_slot"

        if [[ -r "$gpu_path/power/runtime_status" ]]; then
            runtime_status="$(cat "$gpu_path/power/runtime_status")"
        fi
    fi

    if awk -v temp="$gpu_temp" 'BEGIN { exit !(temp >= 85) }'; then
        doctor_failure "NVIDIA temperature is ${gpu_temp} °C."
        doctor_recommend \
            "Check cooling, workload, vents, and NVIDIA processes."
    elif awk -v temp="$gpu_temp" 'BEGIN { exit !(temp >= 75) }'; then
        doctor_warning "NVIDIA temperature is ${gpu_temp} °C."
        doctor_recommend "Review NVIDIA workload and cooling."
    else
        doctor_pass "NVIDIA temperature is ${gpu_temp} °C."
    fi

    doctor_info \
        "NVIDIA usage is ${gpu_util}% with a ${gpu_power} W power draw."

    if [[ "$runtime_status" == "suspended" ]]; then
        doctor_pass "NVIDIA runtime power management is suspended."
    else
        doctor_info "NVIDIA runtime PM state is $runtime_status."
    fi

    if awk -v power="$gpu_power" -v util="$gpu_util" '
        BEGIN {
            exit !(util <= 5 && power >= 30)
        }
    '; then
        doctor_warning \
            "NVIDIA is nearly idle but drawing ${gpu_power} W."
        doctor_recommend \
            "Inspect NVIDIA device users with: labctl gpu processes"
    fi
}

doctor_check_storage() {
    local filesystem
    local usage
    local percentage
    local target
    local filesystem_type
    local -a targets=(/)

    if [[ -d "${HOME:-}" ]]; then
        targets+=("$HOME")
    fi

    if command_exists findmnt; then
        while read -r target filesystem_type; do
            case "$filesystem_type" in
                squashfs|iso9660) continue ;;
            esac

            case "$target" in
                /mnt/*|/media/*|/run/media/*)
                    targets+=("$target")
                    ;;
            esac
        done < <(findmnt --real --raw --noheadings --output TARGET,FSTYPE 2>/dev/null)
    fi

    while read -r filesystem usage; do
        [[ -n "$filesystem" ]] || continue

        percentage="${usage%\%}"

        if (( percentage >= 90 )); then
            doctor_failure \
                "$filesystem usage is ${percentage}%."
            doctor_recommend \
                "Free space on $filesystem before it reaches full capacity."
        elif (( percentage >= 80 )); then
            doctor_warning \
                "$filesystem usage is ${percentage}%."
            doctor_recommend "Review disk usage on $filesystem."
        else
            doctor_pass \
                "$filesystem usage is ${percentage}%."
        fi
    done < <(
        df -P "${targets[@]}" 2>/dev/null |
        awk 'NR > 1 && !seen[$6]++ {
            print $6, $5
        }'
    )

    if systemctl is-enabled --quiet fstrim.timer 2>/dev/null &&
       systemctl is-active --quiet fstrim.timer 2>/dev/null; then
        doctor_pass "Weekly TRIM is enabled and active."
    else
        doctor_warning "Weekly TRIM is not fully enabled and active."
        doctor_recommend "Enable fstrim.timer for periodic SSD maintenance."
    fi
}

doctor_check_updates() {
    local update_count
    local package_manager=""

    if command_exists apt; then
        package_manager="apt"
    elif command_exists dnf; then
        package_manager="dnf"
    fi

    case "$package_manager" in
        apt)
            print_info "Checking cached APT package updates..."
            update_count="$(
                apt list --upgradable 2>/dev/null |
                    awk 'NR > 1 {count++} END {print count + 0}'
            )"
            ;;
        dnf)
            print_info "Checking Fedora package updates..."
            update_count="$(
                dnf check-upgrade \
                    --quiet \
                    --refresh \
                    2>/dev/null |
                awk '
                    /^[[:alnum:]_.+-]+[[:space:]]+[[:alnum:]_.+-]+[[:space:]]+/ {
                        count++
                    }
                    END {
                        print count + 0
                    }
                '
            )"
            ;;
        *)
            doctor_info "No supported package manager was detected."
            return 0
            ;;
    esac

    if (( update_count == 0 )); then
        doctor_pass "No package updates were detected."
    else
        doctor_info "$update_count package update(s) available."

        if [[ "$package_manager" == "apt" ]]; then
            doctor_recommend "Refresh and review updates with: sudo apt update && apt list --upgradable"
        else
            doctor_recommend "Review available updates with: dnf check-upgrade"
        fi
    fi
}

doctor_show_recommendations() {
    local recommendation
    local index=1

    if (( ${#doctor_recommendations[@]} == 0 )); then
        return 0
    fi

    echo
    print_header "RECOMMENDATIONS"

    for recommendation in "${doctor_recommendations[@]}"; do
        printf "%2d. %s\n" "$index" "$recommendation"
        index=$((index + 1))
    done
}

doctor_summary() {
    local health_level
    local health_state

    if (( doctor_failed > 0 )); then
        health_level="CRITICAL"
        health_state="error"
    elif (( doctor_warnings >= 3 )); then
        health_level="ATTENTION NEEDED"
        health_state="warning"
    elif (( doctor_warnings > 0 )); then
        health_level="HEALTHY"
        health_state="warning"
    else
        health_level="EXCELLENT"
        health_state="ok"
    fi

    echo
    print_header "DOCTOR SUMMARY"

    print_status_value "Passed:" "$doctor_passed" "ok"
    print_status_value "Information:" "$doctor_information" "info"
    print_status_value "Warnings:" "$doctor_warnings" \
        "$([[ "$doctor_warnings" -gt 0 ]] && echo warning || echo ok)"
    print_status_value "Errors:" "$doctor_failed" \
        "$([[ "$doctor_failed" -gt 0 ]] && echo error || echo ok)"
    print_status_value "System Health:" "$health_level" "$health_state"

    doctor_show_recommendations

    echo

    if (( doctor_failed > 0 )); then
        print_error "Problems requiring action were detected."
        return 1
    elif (( doctor_warnings > 0 )); then
        print_warn "The system is operational, but review the warnings."
        return 0
    else
        print_ok "The system is healthy."
        return 0
    fi
}

doctor_run() {
    doctor_passed=0
    doctor_information=0
    doctor_warnings=0
    doctor_failed=0
    doctor_recommendations=()

    print_header "LABCTL DOCTOR"

    print_subheader "Services"
    doctor_check_failed_services

    print_subheader "Security"
    doctor_check_security

    print_subheader "Battery"
    doctor_check_battery

    print_subheader "Lab Services"
    doctor_check_lab_services

    print_subheader "OneDrive"
    doctor_check_onedrive

    print_subheader "NVIDIA GPU"
    doctor_check_nvidia

    print_subheader "Storage"
    doctor_check_storage

    print_subheader "Updates"
    doctor_check_updates

    doctor_summary
}

doctor_dispatch() {
    local action="${1:-run}"

    case "$action" in
        run|status)
            doctor_run
            ;;
        help|-h|--help)
            doctor_help
            ;;
        *)
            print_error "Unknown doctor action: $action"
            doctor_help
            return 1
            ;;
    esac
}
