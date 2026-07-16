#!/usr/bin/env bash

gpu_help() {
    cat <<'HELP'
Usage:
  labctl gpu status
  labctl gpu nvidia
  labctl gpu intel
  labctl gpu processes
  labctl gpu help
HELP
}

gpu_nvidia_available() {
    command_exists nvidia-smi
}

gpu_nvidia_pci_path() {
    local slot

    slot="$(
        lspci -D 2>/dev/null |
        awk '/NVIDIA Corporation/ && ($0 ~ /VGA compatible controller|3D controller|Display controller/) {
            print $1
            exit
        }'
    )"

    [[ -n "$slot" ]] && printf '/sys/bus/pci/devices/%s' "$slot"
}

gpu_status() {
    print_header "GPU STATUS"

    echo "Intel GPU:"
    lspci -k 2>/dev/null |
        grep -A3 -E 'VGA compatible controller.*Intel|Display controller.*Intel' ||
        print_warn "Intel GPU was not detected."

    echo

    if gpu_nvidia_available; then
        local gpu_data
        local name temp power util memory_used memory_total perf
        local pci_path runtime_status

        gpu_data="$(
            nvidia-smi \
                --query-gpu=name,temperature.gpu,power.draw,utilization.gpu,memory.used,memory.total,pstate \
                --format=csv,noheader,nounits 2>/dev/null |
            head -1
        )"

        if [[ -n "$gpu_data" ]]; then
            IFS=',' read -r name temp power util memory_used memory_total perf <<< "$gpu_data"

            name="$(xargs <<< "$name")"
            temp="$(xargs <<< "$temp")"
            power="$(xargs <<< "$power")"
            util="$(xargs <<< "$util")"
            memory_used="$(xargs <<< "$memory_used")"
            memory_total="$(xargs <<< "$memory_total")"
            perf="$(xargs <<< "$perf")"

            printf "%-24s %s\n" "NVIDIA GPU:" "$name"
            printf "%-24s %s °C\n" "Temperature:" "$temp"
            printf "%-24s %s W\n" "Power Draw:" "$power"
            printf "%-24s %s %%\n" "GPU Usage:" "$util"
            printf "%-24s %s / %s MiB\n" "VRAM:" "$memory_used" "$memory_total"
            printf "%-24s %s\n" "Performance State:" "$perf"
        else
            print_warn "NVIDIA GPU information could not be read."
        fi

        pci_path="$(gpu_nvidia_pci_path || true)"
        runtime_status="Unavailable"

        if [[ -n "$pci_path" && -r "$pci_path/power/runtime_status" ]]; then
            runtime_status="$(cat "$pci_path/power/runtime_status")"
        fi

        printf "%-24s %s\n" "Runtime PM:" "$runtime_status"
    else
        print_info "nvidia-smi is unavailable."
    fi
}

gpu_nvidia() {
    if ! gpu_nvidia_available; then
        print_error "nvidia-smi was not found."
        return 1
    fi

    print_header "NVIDIA GPU"
    nvidia-smi
}

gpu_intel() {
    print_header "INTEL GPU"

    lspci -k 2>/dev/null |
        grep -A4 -E 'VGA compatible controller.*Intel|Display controller.*Intel' ||
        print_warn "Intel GPU was not detected."
}

gpu_processes() {
    print_header "NVIDIA PROCESSES"

    if ! gpu_nvidia_available; then
        print_error "nvidia-smi was not found."
        return 1
    fi

    nvidia-smi \
        --query-compute-apps=pid,process_name,used_memory \
        --format=csv,noheader 2>/dev/null ||
        true

    echo
    print_info "Open NVIDIA device handles:"

    sudo lsof /dev/nvidia* 2>/dev/null ||
        print_info "No processes were detected on /dev/nvidia*."
}

gpu_dispatch() {
    local action="${1:-status}"

    case "$action" in
        status) gpu_status ;;
        nvidia) gpu_nvidia ;;
        intel) gpu_intel ;;
        processes) gpu_processes ;;
        help|-h|--help) gpu_help ;;
        *)
            print_error "Unknown GPU action: $action"
            gpu_help
            return 1
            ;;
    esac
}
