#!/usr/bin/env bash

# LabCTL resource monitor.
# Provides one-shot and live views for CPU, memory, GPU, storage, network,
# power, and LabCTL-managed services.

monitor_help() {
    cat <<'HELP'
Usage:
  labctl monitor dashboard
  labctl monitor dashboard --json
  labctl monitor summary
  labctl monitor live [seconds]
  labctl monitor cpu
  labctl monitor memory
  labctl monitor gpu
  labctl monitor disk
  labctl monitor network
  labctl monitor power
  labctl monitor help

Actions:
  dashboard        Show a compact workstation dashboard (default)
                   Add --json for the stable, versioned machine interface
  summary          Show a complete detailed resource snapshot
  live             Refresh the compact dashboard continuously
  cpu              Show CPU usage, load, frequency, and temperature
  memory           Show RAM, cache, available memory, swap, and ZRAM
  gpu              Show NVIDIA GPU usage, temperature, VRAM, and power
  disk             Show filesystem usage, I/O rates, and NVMe temperatures
  network          Show active interfaces and receive/transmit rates
  power            Show tuned profile and battery information

Examples:
  labctl monitor
  labctl monitor dashboard
  labctl monitor summary
  labctl monitor live
  labctl monitor live 3
  labctl monitor gpu
HELP
}

monitor_number_or_zero() {
    local value="${1:-0}"
    [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]] && printf '%s' "$value" || printf '0'
}

monitor_human_bytes() {
    local bytes="${1:-0}"

    if command_exists numfmt; then
        numfmt --to=iec-i --suffix=B --format='%.1f' "$bytes" 2>/dev/null || printf '%s B' "$bytes"
    else
        awk -v bytes="$bytes" 'BEGIN {
            split("B KiB MiB GiB TiB", units, " ")
            i=1
            while (bytes >= 1024 && i < 5) { bytes /= 1024; i++ }
            printf "%.1f %s", bytes, units[i]
        }'
    fi
}

monitor_cpu_snapshot() {
    awk '/^cpu / {
        idle=$5+$6
        total=0
        for (i=2; i<=NF; i++) total+=$i
        print total, idle
        exit
    }' /proc/stat
}

monitor_cpu_usage() {
    local first_total first_idle second_total second_idle delta_total delta_idle usage

    read -r first_total first_idle < <(monitor_cpu_snapshot)
    sleep 0.35
    read -r second_total second_idle < <(monitor_cpu_snapshot)

    delta_total=$((second_total - first_total))
    delta_idle=$((second_idle - first_idle))

    if (( delta_total <= 0 )); then
        printf '0'
        return 0
    fi

    usage=$(( (100 * (delta_total - delta_idle)) / delta_total ))
    (( usage < 0 )) && usage=0
    (( usage > 100 )) && usage=100
    printf '%s' "$usage"
}

monitor_cpu_frequency_mhz() {
    local total=0 count=0 value cpu_path

    shopt -s nullglob
    for cpu_path in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq; do
        [[ -r "$cpu_path" ]] || continue
        read -r value < "$cpu_path"
        [[ "$value" =~ ^[0-9]+$ ]] || continue
        total=$((total + value))
        count=$((count + 1))
    done
    shopt -u nullglob

    if (( count > 0 )); then
        printf '%s' "$((total / count / 1000))"
    elif command_exists lscpu; then
        lscpu 2>/dev/null | awk -F: '/CPU MHz/ {gsub(/^[[:space:]]+/, "", $2); printf "%.0f", $2; exit}'
    else
        printf 'Unavailable'
    fi
}

monitor_cpu_temperature() {
    local path type temp best=""

    shopt -s nullglob
    for path in /sys/class/thermal/thermal_zone*/temp; do
        [[ -r "$path" ]] || continue
        type=""
        [[ -r "${path%/temp}/type" ]] && read -r type < "${path%/temp}/type"
        case "${type,,}" in
            *x86_pkg_temp*|*cpu*|*package*|*soc*)
                read -r temp < "$path"
                [[ "$temp" =~ ^[0-9]+$ ]] || continue
                temp=$((temp / 1000))
                if [[ -z "$best" || "$temp" -gt "$best" ]]; then
                    best="$temp"
                fi
                ;;
        esac
    done
    shopt -u nullglob

    if [[ -n "$best" ]]; then
        printf '%s' "$best"
        return 0
    fi

    if command_exists sensors; then
        sensors 2>/dev/null | awk '
            /Package id 0:|Tctl:|Tdie:/ {
                if (match($0, /[+]?[0-9]+([.][0-9]+)?°C/)) {
                    value=substr($0, RSTART, RLENGTH)
                    gsub(/[+°C]/, "", value)
                    printf "%.0f", value
                    exit
                }
            }'
        return 0
    fi

    printf 'Unavailable'
}

monitor_memory_values() {
    awk '
        /^MemTotal:/     {total=$2}
        /^MemAvailable:/ {available=$2}
        /^Cached:/       {cached=$2}
        /^SReclaimable:/ {reclaim=$2}
        /^SwapTotal:/    {swap_total=$2}
        /^SwapFree:/     {swap_free=$2}
        END {
            cache=cached+reclaim
            used=total-available
            swap_used=swap_total-swap_free
            printf "%d %d %d %d %d\n", total*1024, used*1024, available*1024, cache*1024, swap_used*1024
            printf "%d\n", swap_total*1024
        }
    ' /proc/meminfo
}

monitor_nvidia_pci_path() {
    local slot

    command_exists lspci || return 1
    slot="$(
        lspci -D 2>/dev/null |
        awk '/NVIDIA Corporation/ && ($0 ~ /VGA compatible controller|3D controller|Display controller/) {
            print $1
            exit
        }'
    )"

    [[ -n "$slot" ]] && printf '/sys/bus/pci/devices/%s' "$slot"
}

monitor_nvidia_runtime_pm() {
    local pci_path

    pci_path="$(monitor_nvidia_pci_path || true)"
    if [[ -n "$pci_path" && -r "$pci_path/power/runtime_status" ]]; then
        cat "$pci_path/power/runtime_status"
    else
        printf 'Unavailable'
    fi
}

monitor_nvidia_data() {
    command_exists nvidia-smi || return 1

    nvidia-smi \
        --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw,pstate \
        --format=csv,noheader,nounits 2>/dev/null | head -1
}

monitor_disk_counters() {
    awk '
        $3 ~ /^(nvme[0-9]+n[0-9]+|sd[a-z]+|vd[a-z]+)$/ {
            read_sectors += $6
            write_sectors += $10
        }
        END { print read_sectors+0, write_sectors+0 }
    ' /proc/diskstats
}

monitor_disk_rates() {
    local r1 w1 r2 w2 read_bytes write_bytes

    read -r r1 w1 < <(monitor_disk_counters)
    sleep 1
    read -r r2 w2 < <(monitor_disk_counters)

    read_bytes=$(( (r2 - r1) * 512 ))
    write_bytes=$(( (w2 - w1) * 512 ))
    (( read_bytes < 0 )) && read_bytes=0
    (( write_bytes < 0 )) && write_bytes=0

    printf '%s %s\n' "$read_bytes" "$write_bytes"
}

monitor_nvme_temperatures() {
    local controller controller_path device output model temp sensor_label sensor_temp hwmon_root hwmon_file
    local -A seen=()

    shopt -s nullglob

    # Prefer nvme-cli. Never prompt for sudo from a monitoring command: use
    # cached/non-interactive sudo only, then try ordinary unprivileged access.
    if command_exists nvme; then
        for device in /dev/nvme[0-9] /dev/nvme[0-9]n[0-9]; do
            [[ -e "$device" ]] || continue
            controller="$(basename "$device")"
            controller="${controller%%n[0-9]*}"
            [[ -n "${seen[$controller]:-}" ]] && continue

            output="$(sudo -n nvme smart-log "$device" 2>/dev/null || nvme smart-log "$device" 2>/dev/null || true)"
            [[ -n "$output" ]] || continue

            model="$(cat "/sys/class/nvme/$controller/model" 2>/dev/null | xargs || true)"
            [[ -n "$model" ]] || model="$controller"

            temp="$(awk -F: '
                tolower($1) ~ /^[[:space:]]*temperature[[:space:]]*$/ {
                    if (match($2, /[0-9]+/)) { print substr($2, RSTART, RLENGTH); exit }
                }
            ' <<< "$output")"
            if [[ "$temp" =~ ^[0-9]+$ ]]; then
                printf '%s\t%s\n' "$controller ($model) Composite" "$temp"
            fi

            while IFS=$'\t' read -r sensor_label sensor_temp; do
                [[ "$sensor_temp" =~ ^[0-9]+$ ]] || continue
                printf '%s\t%s\n' "$controller $sensor_label" "$sensor_temp"
            done < <(awk -F: '
                tolower($1) ~ /^[[:space:]]*temperature sensor [0-9]+[[:space:]]*$/ {
                    label=$1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", label)
                    if (match($2, /[0-9]+/))
                        printf "%s\t%s\n", label, substr($2, RSTART, RLENGTH)
                }
            ' <<< "$output")

            [[ "$temp" =~ ^[0-9]+$ ]] && seen["$controller"]=1
        done
    fi

    # Secondary source: smartmontools.
    if command_exists smartctl; then
        for device in /dev/nvme[0-9] /dev/nvme[0-9]n[0-9]; do
            [[ -e "$device" ]] || continue
            controller="$(basename "$device")"
            controller="${controller%%n[0-9]*}"
            [[ -n "${seen[$controller]:-}" ]] && continue
            output="$(sudo -n smartctl -a "$device" 2>/dev/null || smartctl -a "$device" 2>/dev/null || true)"
            temp="$(awk '
                /^Temperature:/ {
                    for (i=1; i<=NF; i++)
                        if ($i ~ /^[0-9]+$/) { print $i; exit }
                }
            ' <<< "$output")"
            if [[ "$temp" =~ ^[0-9]+$ ]]; then
                model="$(cat "/sys/class/nvme/$controller/model" 2>/dev/null | xargs || true)"
                [[ -n "$model" ]] || model="$controller"
                printf '%s\t%s\n' "$controller ($model) Composite" "$temp"
                seen["$controller"]=1
            fi
        done
    fi

    # Final source: kernel hwmon. Search only the bounded hwmon directory and
    # never recurse through the complete PCI/sysfs tree.
    for controller_path in /sys/class/nvme/nvme[0-9]*; do
        [[ -e "$controller_path" ]] || continue
        controller="$(basename "$controller_path")"
        [[ -n "${seen[$controller]:-}" ]] && continue
        model="$(cat "$controller_path/model" 2>/dev/null | xargs || true)"
        [[ -n "$model" ]] || model="$controller"

        for hwmon_root in "$controller_path/device/hwmon" "$controller_path/hwmon"; do
            [[ -d "$hwmon_root" ]] || continue
            for hwmon_file in "$hwmon_root"/hwmon*/temp1_input; do
                [[ -r "$hwmon_file" ]] || continue
                temp="$(cat "$hwmon_file" 2>/dev/null || true)"
                [[ "$temp" =~ ^[0-9]+$ ]] || continue
                (( temp > 1000 )) && temp=$((temp / 1000))
                printf '%s\t%s\n' "$controller ($model) Composite" "$temp"
                seen["$controller"]=1
                break 2
            done
        done
    done

    shopt -u nullglob
}

monitor_default_interfaces() {
    local iface

    if command_exists ip; then
        ip -o route show default 2>/dev/null | awk '{print $5}' | sort -u
    else
        shopt -s nullglob
        for iface in /sys/class/net/*; do
            iface="$(basename "$iface")"
            [[ "$iface" == "lo" ]] || printf '%s\n' "$iface"
        done
        shopt -u nullglob
    fi
}

monitor_network_ssid() {
    local iface="${1:?Missing interface}"
    local ssid=""

    if command_exists iwgetid; then
        ssid="$(iwgetid "$iface" --raw 2>/dev/null || true)"
    elif command_exists iw; then
        ssid="$(iw dev "$iface" link 2>/dev/null | sed -n 's/^[[:space:]]*SSID: //p' | head -1)"
    fi

    printf '%s' "${ssid:-Unavailable}"
}

monitor_network_signal() {
    local iface="${1:?Missing interface}"
    local signal=""

    if command_exists iw; then
        signal="$(iw dev "$iface" link 2>/dev/null | awk '/signal:/ {print $2 " dBm"; exit}')"
    fi

    printf '%s' "${signal:-Unavailable}"
}

monitor_network_link_speed() {
    local iface="${1:?Missing interface}"
    local speed=""

    # Some wireless drivers expose /sys/class/net/<iface>/speed but return EINVAL
    # when it is read. Suppress that kernel/driver error and fall back to iw.
    speed="$(cat "/sys/class/net/$iface/speed" 2>/dev/null || true)"
    if [[ "$speed" =~ ^[0-9]+$ ]] && (( speed > 0 )); then
        printf '%s Mbps' "$speed"
        return 0
    fi

    if command_exists iw; then
        speed="$(iw dev "$iface" link 2>/dev/null | awk '/tx bitrate:/ {print $3 " " $4; exit}')"
    fi

    printf '%s' "${speed:-Unavailable}"
}

monitor_default_gateway() {
    command_exists ip || { printf 'Unavailable'; return 0; }
    ip route show default 2>/dev/null | awk '{print $3; exit}' | sed '/^$/c\Unavailable'
}

monitor_dns_servers() {
    local iface="${1:-}"
    local dns=""

    if command_exists resolvectl; then
        if [[ -n "$iface" ]]; then
            dns="$(resolvectl dns "$iface" 2>/dev/null |
                awk -F: 'NR == 1 {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}' |
                xargs 2>/dev/null || true)"
        fi

        if [[ -z "$dns" ]]; then
            dns="$(resolvectl dns 2>/dev/null |
                awk -F: '
                    /^Global:/ || /^Link [0-9]+/ {
                        value=$2
                        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                        if (value != "") {
                            count=split(value, servers, /[[:space:]]+/)
                            for (i=1; i<=count; i++)
                                if (servers[i] ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/ || servers[i] ~ /:/)
                                    print servers[i]
                        }
                    }
                ' | awk '!seen[$0]++' | paste -sd ',' - | sed 's/,/, /g')"
        fi
    fi

    if [[ -z "$dns" && -r /etc/resolv.conf ]]; then
        dns="$(awk '/^nameserver[[:space:]]+/ {print $2}' /etc/resolv.conf |
            awk '!seen[$0]++' | paste -sd ',' - | sed 's/,/, /g')"
    fi

    printf '%s' "${dns:-Unavailable}"
}

monitor_net_counter() {
    local iface="${1:?Missing interface}"
    local direction="${2:?Missing direction}"
    local path="/sys/class/net/$iface/statistics/${direction}_bytes"

    [[ -r "$path" ]] && cat "$path" || printf '0'
}

monitor_network_rates() {
    local iface rx1 tx1 rx2 tx2 rx_rate tx_rate

    while IFS= read -r iface; do
        [[ -n "$iface" && -d "/sys/class/net/$iface" ]] || continue
        rx1="$(monitor_net_counter "$iface" rx)"
        tx1="$(monitor_net_counter "$iface" tx)"
        sleep 1
        rx2="$(monitor_net_counter "$iface" rx)"
        tx2="$(monitor_net_counter "$iface" tx)"
        rx_rate=$((rx2 - rx1))
        tx_rate=$((tx2 - tx1))
        (( rx_rate < 0 )) && rx_rate=0
        (( tx_rate < 0 )) && tx_rate=0
        printf '%s %s %s\n' "$iface" "$rx_rate" "$tx_rate"
    done < <(monitor_default_interfaces)
}

monitor_service_value() {
    local unit="${1:?Missing service unit}"
    if service_is_active "$unit"; then
        printf 'ACTIVE'
    else
        printf 'STOPPED'
    fi
}

monitor_service_indicator() {
    local state="${1:-STOPPED}"
    if [[ "$state" == "ACTIVE" ]]; then
        printf '● ACTIVE'
    else
        printf '○ STOPPED'
    fi
}

monitor_cpu() {
    local usage temperature frequency load processes

    usage="$(monitor_cpu_usage)"
    temperature="$(monitor_cpu_temperature)"
    frequency="$(monitor_cpu_frequency_mhz)"
    load="$(cut -d' ' -f1-3 /proc/loadavg)"
    processes="$(ps -e --no-headers 2>/dev/null | wc -l | xargs)"

    print_header "CPU"
    print_status_value "Usage:" "$(color_by_percentage "$usage" 70 90)" "normal"
    if [[ "$temperature" =~ ^[0-9]+$ ]]; then
        print_status_value "Temperature:" "$(color_by_temperature "$temperature" 75 90)" "normal"
    else
        print_status_value "Temperature:" "$temperature" "warning"
    fi
    print_status_value "Average Frequency:" "${frequency} MHz" "normal"
    print_status_value "Load Average:" "$load" "normal"
    print_status_value "Processes:" "$processes" "normal"
}

monitor_memory() {
    local -a values
    local total used available cache swap_used swap_total usage_percent

    mapfile -t values < <(monitor_memory_values)
    read -r total used available cache swap_used <<< "${values[0]}"
    swap_total="${values[1]}"

    usage_percent=0
    (( total > 0 )) && usage_percent=$((100 * used / total))

    print_header "MEMORY"
    print_status_value "RAM Used:" "$(monitor_human_bytes "$used") / $(monitor_human_bytes "$total") ($(color_by_percentage "$usage_percent" 75 90))" "normal"
    print_status_value "RAM Available:" "$(monitor_human_bytes "$available")" "normal"
    print_status_value "Cache:" "$(monitor_human_bytes "$cache")" "normal"
    print_status_value "Swap Used:" "$(monitor_human_bytes "$swap_used") / $(monitor_human_bytes "$swap_total")" "normal"

    if command_exists zramctl && zramctl --noheadings 2>/dev/null | grep -q .; then
        print_subheader "ZRAM"
        zramctl --output NAME,ALGORITHM,DISKSIZE,DATA,COMPR,TOTAL,STREAMS 2>/dev/null || true
    fi
}

monitor_gpu() {
    local data name temp util memory_used memory_total power pstate runtime_pm

    print_header "GPU"

    data="$(monitor_nvidia_data || true)"
    if [[ -z "$data" ]]; then
        print_warn "NVIDIA telemetry is unavailable. The GPU may be powered down or nvidia-smi may be missing."
        if command_exists lspci; then
            lspci -k 2>/dev/null | grep -A3 -E 'VGA compatible controller|3D controller|Display controller' || true
        fi
        return 0
    fi

    IFS=',' read -r name temp util memory_used memory_total power pstate <<< "$data"
    name="$(xargs <<< "$name")"
    temp="$(xargs <<< "$temp")"
    util="$(xargs <<< "$util")"
    memory_used="$(xargs <<< "$memory_used")"
    memory_total="$(xargs <<< "$memory_total")"
    power="$(xargs <<< "$power")"
    pstate="$(xargs <<< "$pstate")"
    runtime_pm="$(monitor_nvidia_runtime_pm)"

    print_status_value "GPU:" "$name" "normal"
    if [[ "$temp" =~ ^[0-9]+$ ]]; then
        print_status_value "Temperature:" "$(color_by_temperature "$temp" 70 85)" "normal"
    else
        print_status_value "Temperature:" "Unavailable" "warning"
    fi
    if [[ "$util" =~ ^[0-9]+$ ]]; then
        print_status_value "GPU Usage:" "$(color_by_percentage "$util" 75 95)" "normal"
    else
        print_status_value "GPU Usage:" "Unavailable" "warning"
    fi
    print_status_value "VRAM:" "${memory_used} / ${memory_total} MiB" "normal"
    print_status_value "Power Draw:" "${power} W" "normal"
    print_status_value "Performance State:" "$pstate" "normal"
    print_status_value "Runtime PM:" "$runtime_pm" "normal"
}

monitor_disk() {
    local read_rate write_rate name temp

    print_header "STORAGE"

    print_subheader "Filesystems"
    printf "%-22s %-8s %8s %8s %8s %6s  %s\n" "DEVICE" "TYPE" "SIZE" "USED" "AVAIL" "USE%" "MOUNT"
    df -hT -x tmpfs -x devtmpfs -x squashfs -x efivarfs 2>/dev/null |
        awk 'NR > 1 && ($7 == "/" || $7 == "/home" || $7 ~ /^\/mnt\//) {
            printf "%-22s %-8s %8s %8s %8s %6s  %s\n", $1, $2, $3, $4, $5, $6, $7
        }'

    read -r read_rate write_rate < <(monitor_disk_rates)
    print_subheader "I/O Rate"
    print_status_value "Read:" "$(monitor_human_bytes "$read_rate")/s" "normal"
    print_status_value "Write:" "$(monitor_human_bytes "$write_rate")/s" "normal"

    print_subheader "NVMe Temperature"
    local nvme_data
    nvme_data="$(monitor_nvme_temperatures)"
    if [[ -z "$nvme_data" ]]; then
        print_info "NVMe temperatures require readable SMART data. Run sudo -v, then retry; no password is requested by LabCTL."
    else
        while IFS=$'\t' read -r name temp; do
            [[ -n "$name" && "$temp" =~ ^[0-9]+$ ]] || continue
            print_status_value "$name:" "$(color_by_temperature "$temp" 60 75)" "normal"
        done <<< "$nvme_data"
    fi
}

monitor_network() {
    local iface rx_rate tx_rate state address

    print_header "NETWORK"

    while read -r iface rx_rate tx_rate; do
        [[ -n "$iface" ]] || continue
        state="$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || printf 'unknown')"
        address="$(ip -o -4 addr show dev "$iface" 2>/dev/null | awk '{print $4; exit}')"
        print_subheader "$iface"
        print_status_value "State:" "${state^^}" "$([[ "$state" == "up" ]] && printf active || printf warning)"
        print_status_value "IPv4:" "${address:-Unavailable}" "normal"
        if [[ "$iface" == wl* ]]; then
            print_status_value "SSID:" "$(monitor_network_ssid "$iface")" "normal"
            print_status_value "Signal:" "$(monitor_network_signal "$iface")" "normal"
        fi
        print_status_value "Link Speed:" "$(monitor_network_link_speed "$iface")" "normal"
        print_status_value "Download:" "$(monitor_human_bytes "$rx_rate")/s" "normal"
        print_status_value "Upload:" "$(monitor_human_bytes "$tx_rate")/s" "normal"
    done < <(monitor_network_rates)

    print_subheader "Routing"
    print_status_value "Gateway:" "$(monitor_default_gateway)" "normal"
    print_status_value "DNS:" "$(monitor_dns_servers "$iface")" "normal"
}

monitor_power() {
    local profile="Unavailable" battery capacity status cycle_count power_now

    print_header "POWER"

    if command_exists tuned-adm; then
        profile="$(tuned-adm active 2>/dev/null | sed 's/^Current active profile: //')"
    elif command_exists powerprofilesctl; then
        profile="$(powerprofilesctl get 2>/dev/null || true)"
    fi
    print_status_value "Power Profile:" "$profile" "info"

    battery="$(find /sys/class/power_supply -maxdepth 1 -type l -name 'BAT*' 2>/dev/null | head -1)"
    if [[ -z "$battery" ]]; then
        print_info "No battery was detected."
        return 0
    fi

    capacity="$(cat "$battery/capacity" 2>/dev/null || printf 'Unavailable')"
    status="$(cat "$battery/status" 2>/dev/null || printf 'Unavailable')"
    cycle_count="$(cat "$battery/cycle_count" 2>/dev/null || printf 'Unavailable')"
    power_now="$(cat "$battery/power_now" 2>/dev/null || true)"

    if [[ "$capacity" =~ ^[0-9]+$ ]]; then
        print_status_value "Battery:" "${capacity}%" "normal"
    else
        print_status_value "Battery:" "$capacity" "warning"
    fi
    print_status_value "Status:" "$status" "normal"
    print_status_value "Cycle Count:" "$cycle_count" "normal"
    if [[ "$power_now" =~ ^[0-9]+$ ]]; then
        print_status_value "Power Rate:" "$(awk -v p="$power_now" 'BEGIN {printf "%.2f W", p/1000000}')" "normal"
    fi
}

monitor_services() {
    local profile_file="$HOME/.local/state/labctl/profile"
    local profile="unmanaged"

    [[ -r "$profile_file" ]] && read -r profile < "$profile_file"

    print_header "LABCTL SERVICES"
    print_status_value "Selected Profile:" "$profile" "info"
    print_status_value "Docker:" "$(monitor_service_value docker.service)" "normal"
    print_status_value "Containerd:" "$(monitor_service_value containerd.service)" "normal"
    print_status_value "Libvirt:" "$(monitor_service_value virtqemud.service)" "normal"
    print_status_value "VMware:" "$(monitor_service_value vmware.service)" "normal"
    print_status_value "Ollama:" "$(monitor_service_value ollama.service)" "normal"
}

monitor_root_storage_values() {
    df -Pk / 2>/dev/null |
        awk 'NR == 2 {
            gsub(/%/, "", $5)
            printf "%d %d %d\n", $2 * 1024, $4 * 1024, $5
        }'
}

monitor_primary_ipv4() {
    local interface="${1:-}"

    [[ -n "$interface" ]] || {
        printf 'Unavailable'
        return
    }

    ip -4 -o address show dev "$interface" scope global 2>/dev/null |
        awk '{sub(/\/.*/, "", $4); print $4; exit}'
}

monitor_vpn_state() {
    if command_exists nmcli &&
       nmcli -t -f TYPE connection show --active 2>/dev/null |
           grep -Eq '^(vpn|wireguard)$'; then
        printf 'CONNECTED'
    else
        printf 'DISCONNECTED'
    fi
}

monitor_firewall_state() {
    if command_exists ufw; then
        if [[ -r /etc/ufw/ufw.conf ]] &&
           grep -Eq '^[[:space:]]*ENABLED=yes([[:space:]]|$)' /etc/ufw/ufw.conf; then
            printf 'ENABLED'
        else
            printf 'DISABLED'
        fi
    elif command_exists firewall-cmd; then
        if service_is_active firewalld.service; then
            printf 'ENABLED'
        else
            printf 'DISABLED'
        fi
    else
        printf 'UNAVAILABLE'
    fi
}

monitor_update_count() {
    if command_exists apt; then
        apt list --upgradable 2>/dev/null |
            awk 'NR > 1 {count++} END {print count + 0}'
    elif command_exists dnf; then
        dnf check-upgrade --cacheonly --quiet 2>/dev/null |
            awk '/^[[:alnum:]_.+-]+[[:space:]]+[[:alnum:]_.+-]+/ {count++}
                 END {print count + 0}'
    else
        printf 'Unavailable'
    fi
}

monitor_cache_directory() {
    printf '%s/labctl\n' "${XDG_CACHE_HOME:-$HOME/.cache}"
}

monitor_cached_update_count() {
    local cache_directory cache_file cache_ttl now modified value

    cache_directory="$(monitor_cache_directory)"
    cache_file="$cache_directory/update-count"
    cache_ttl="${LABCTL_UPDATE_CACHE_TTL:-3600}"
    now="$(date +%s)"

    if ! [[ "$cache_ttl" =~ ^[0-9]+$ ]]; then
        cache_ttl=3600
    fi

    if [[ -r "$cache_file" ]]; then
        modified="$(stat -c %Y "$cache_file" 2>/dev/null || printf '0')"
        if (( now - modified < cache_ttl )); then
            read -r value < "$cache_file"
            printf '%s' "$value"
            return
        fi
    fi

    value="$(monitor_update_count)"
    if mkdir -p "$cache_directory" 2>/dev/null; then
        printf '%s\n' "$value" > "$cache_file.tmp"
        mv -f "$cache_file.tmp" "$cache_file"
    fi
    printf '%s' "$value"
}

monitor_command_count() {
    local command_name="${1:?Missing command name}"
    shift

    if ! command_exists "$command_name"; then
        printf 'Unavailable'
        return
    fi

    "$command_name" "$@" 2>/dev/null |
        awk 'NF {count++} END {print count + 0}'
}

monitor_json_escape() {
    local value="${1:-}"

    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '%s' "$value"
}

monitor_json_string() {
    printf '"%s"' "$(monitor_json_escape "${1:-}")"
}

monitor_json_number() {
    local value="${1:-}"
    [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]] && printf '%s' "$value" || printf 'null'
}

monitor_alert_configuration() {
    local config_file="${LABCTL_ALERT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/labctl/alerts.conf}"
    local key value

    DASH_CPU_WARNING=80
    DASH_CPU_CRITICAL=90
    DASH_CPU_HYSTERESIS=3
    DASH_GPU_WARNING=80
    DASH_GPU_CRITICAL=90
    DASH_GPU_HYSTERESIS=3
    DASH_STORAGE_WARNING=80
    DASH_STORAGE_CRITICAL=90
    DASH_STORAGE_HYSTERESIS=2
    DASH_UPDATES_WARNING=1
    DASH_FIREWALL_WARNING=true

    [[ -r "$config_file" ]] || return 0

    while IFS='=' read -r key value; do
        key="${key//[[:space:]]/}"
        value="${value%%#*}"
        value="${value//[[:space:]]/}"
        [[ -n "$key" && -n "$value" ]] || continue

        case "$key" in
            cpu_warning) [[ "$value" =~ ^[0-9]+$ ]] && DASH_CPU_WARNING="$value" ;;
            cpu_critical) [[ "$value" =~ ^[0-9]+$ ]] && DASH_CPU_CRITICAL="$value" ;;
            cpu_hysteresis) [[ "$value" =~ ^[0-9]+$ ]] && DASH_CPU_HYSTERESIS="$value" ;;
            gpu_warning) [[ "$value" =~ ^[0-9]+$ ]] && DASH_GPU_WARNING="$value" ;;
            gpu_critical) [[ "$value" =~ ^[0-9]+$ ]] && DASH_GPU_CRITICAL="$value" ;;
            gpu_hysteresis) [[ "$value" =~ ^[0-9]+$ ]] && DASH_GPU_HYSTERESIS="$value" ;;
            storage_warning) [[ "$value" =~ ^[0-9]+$ ]] && DASH_STORAGE_WARNING="$value" ;;
            storage_critical) [[ "$value" =~ ^[0-9]+$ ]] && DASH_STORAGE_CRITICAL="$value" ;;
            storage_hysteresis) [[ "$value" =~ ^[0-9]+$ ]] && DASH_STORAGE_HYSTERESIS="$value" ;;
            updates_warning) [[ "$value" =~ ^[0-9]+$ ]] && DASH_UPDATES_WARNING="$value" ;;
            firewall_warning) [[ "$value" =~ ^(true|false)$ ]] && DASH_FIREWALL_WARNING="$value" ;;
        esac
    done < "$config_file"
}

monitor_add_alert() {
    local id="${1:?Missing alert identifier}"
    local severity="${2:?Missing alert severity}"
    local title="${3:?Missing alert title}"
    local message="${4:?Missing alert message}"

    DASH_ALERTS+=("$id"$'\t'"$severity"$'\t'"$title"$'\t'"$message")
    [[ "$severity" == "critical" ]] && DASH_HEALTH="CRITICAL"
    if [[ "$severity" == "warning" && "$DASH_HEALTH" == "NORMAL" ]]; then
        DASH_HEALTH="WARNING"
    fi
}

monitor_threshold_alert() {
    local id="${1:?Missing alert identifier}"
    local title="${2:?Missing alert title}"
    local value="${3:?Missing current value}"
    local warning="${4:?Missing warning threshold}"
    local critical="${5:?Missing critical threshold}"
    local hysteresis="${6:?Missing hysteresis}"
    local unit="${7:-}"
    local cache_directory state_file previous="normal" level="normal"

    [[ "$value" =~ ^[0-9]+$ ]] || return 0
    cache_directory="$(monitor_cache_directory)/alert-state"
    state_file="$cache_directory/$id"
    [[ -r "$state_file" ]] && read -r previous < "$state_file"

    if (( value >= critical )); then
        level="critical"
    elif [[ "$previous" == "critical" ]] && (( value >= critical - hysteresis )); then
        level="critical"
    elif (( value >= warning )); then
        level="warning"
    elif [[ "$previous" != "normal" ]] && (( value >= warning - hysteresis )); then
        level="warning"
    fi

    if mkdir -p "$cache_directory" 2>/dev/null; then
        printf '%s\n' "$level" > "$state_file"
    fi

    case "$level" in
        critical)
            monitor_add_alert "$id" critical "$title" \
                "$title is ${value}${unit} (critical threshold: ${critical}${unit})."
            ;;
        warning)
            monitor_add_alert "$id" warning "$title" \
                "$title is ${value}${unit} (warning threshold: ${warning}${unit})."
            ;;
    esac
}

monitor_collect_workloads_uncached() {
    local name state line running_names

    DASH_WORKLOADS=()

    if command_exists docker && service_is_active docker.service; then
        while IFS=$'\t' read -r name state; do
            [[ -n "$name" ]] && DASH_WORKLOADS+=("docker"$'\t'"$name"$'\t'"$state")
        done < <(docker ps -a --format '{{.Names}}\t{{.Status}}' 2>/dev/null)
    fi

    if command_exists virsh; then
        while IFS=$'\t' read -r name state; do
            [[ -n "$name" ]] && DASH_WORKLOADS+=("libvirt"$'\t'"$name"$'\t'"$state")
        done < <(
            virsh -c qemu:///system list --all 2>/dev/null |
                awk 'NR > 2 && NF >= 3 {
                    state=""
                    for (i=3; i<=NF; i++) state=state (i == 3 ? "" : " ") $i
                    print $2 "\t" state
                }'
        )
    fi

    if command_exists VBoxManage; then
        running_names="$(VBoxManage list runningvms 2>/dev/null || true)"
        while IFS= read -r line; do
            [[ "$line" =~ ^\"(.*)\"[[:space:]]+\{ ]] || continue
            name="${BASH_REMATCH[1]}"
            state="stopped"
            grep -Fqx -- "$line" <<< "$running_names" && state="running"
            DASH_WORKLOADS+=("virtualbox"$'\t'"$name"$'\t'"$state")
        done < <(VBoxManage list vms 2>/dev/null)
    fi

    if command_exists vmrun; then
        while IFS= read -r name; do
            [[ -n "$name" ]] && DASH_WORKLOADS+=("vmware"$'\t'"$name"$'\t'"running")
        done < <(vmrun list 2>/dev/null | tail -n +2)
    fi
}

monitor_collect_workloads() {
    local cache_directory cache_file cache_ttl now modified item

    cache_directory="$(monitor_cache_directory)"
    cache_file="$cache_directory/workloads.tsv"
    cache_ttl="${LABCTL_WORKLOAD_CACHE_TTL:-20}"
    now="$(date +%s)"
    [[ "$cache_ttl" =~ ^[0-9]+$ ]] || cache_ttl=20

    DASH_WORKLOADS=()
    if [[ -r "$cache_file" ]]; then
        modified="$(stat -c %Y "$cache_file" 2>/dev/null || printf '0')"
        if (( now - modified < cache_ttl )); then
            while IFS= read -r item; do
                [[ -n "$item" ]] && DASH_WORKLOADS+=("$item")
            done < "$cache_file"
            return
        fi
    fi

    monitor_collect_workloads_uncached
    if mkdir -p "$cache_directory" 2>/dev/null; then
        printf '%s\n' "${DASH_WORKLOADS[@]}" > "$cache_file.tmp"
        mv -f "$cache_file.tmp" "$cache_file"
    fi
}

monitor_dashboard_collect() {
    local gpu_data battery profile_file item backend _name state
    local memory_total memory_used swap_used
    local gpu_name gpu_temp gpu_util gpu_mem_used gpu_mem_total gpu_power gpu_pstate
    local disk_read disk_write interface network_rx network_tx
    local storage_total storage_available storage_percent profile
    local -a memory_values

    declare -gA DASH=()
    declare -ga DASH_ALERTS=()
    declare -ga DASH_WORKLOADS=()

    DASH[timestamp]="$(date --iso-8601=seconds)"
    DASH[cpu_usage]="$(monitor_cpu_usage)"
    DASH[cpu_temp]="$(monitor_cpu_temperature)"

    mapfile -t memory_values < <(monitor_memory_values)
    read -r memory_total memory_used _ _ swap_used <<< "${memory_values[0]}"
    DASH[memory_total]="$memory_total"
    DASH[memory_used]="$memory_used"
    DASH[swap_used]="$swap_used"
    DASH[swap_total]="${memory_values[1]}"
    DASH[memory_percent]=0
    (( DASH[memory_total] > 0 )) &&
        DASH[memory_percent]=$((100 * DASH[memory_used] / DASH[memory_total]))

    DASH[gpu_name]="Unavailable"
    DASH[gpu_temp]="Unavailable"
    DASH[gpu_util]="Unavailable"
    DASH[gpu_mem_used]="Unavailable"
    DASH[gpu_mem_total]="Unavailable"
    DASH[gpu_power]="Unavailable"
    DASH[gpu_pstate]="Unavailable"
    DASH[gpu_runtime]="$(monitor_nvidia_runtime_pm)"
    gpu_data="$(monitor_nvidia_data || true)"
    if [[ -n "$gpu_data" ]]; then
        IFS=',' read -r gpu_name gpu_temp gpu_util gpu_mem_used gpu_mem_total \
            gpu_power gpu_pstate <<< "$gpu_data"
        DASH[gpu_name]="$gpu_name"
        DASH[gpu_temp]="$gpu_temp"
        DASH[gpu_util]="$gpu_util"
        DASH[gpu_mem_used]="$gpu_mem_used"
        DASH[gpu_mem_total]="$gpu_mem_total"
        DASH[gpu_power]="$gpu_power"
        DASH[gpu_pstate]="$gpu_pstate"
        for item in gpu_name gpu_temp gpu_util gpu_mem_used gpu_mem_total gpu_power gpu_pstate; do
            DASH[$item]="$(xargs <<< "${DASH[$item]}")"
        done
    fi

    read -r disk_read disk_write < <(monitor_disk_rates)
    DASH[disk_read]="$disk_read"
    DASH[disk_write]="$disk_write"
    read -r interface network_rx network_tx < <(monitor_network_rates | head -1)
    DASH[interface]="$interface"
    DASH[network_rx]="$network_rx"
    DASH[network_tx]="$network_tx"
    read -r storage_total storage_available storage_percent < <(monitor_root_storage_values)
    DASH[storage_total]="$storage_total"
    DASH[storage_available]="$storage_available"
    DASH[storage_percent]="$storage_percent"
    DASH[ipv4]="$(monitor_primary_ipv4 "${DASH[interface]:-}")"
    DASH[vpn]="$(monitor_vpn_state)"
    DASH[firewall]="$(monitor_firewall_state)"
    DASH[updates]="$(monitor_cached_update_count)"

    monitor_collect_workloads
    DASH[containers]=0
    DASH[libvirt_vms]=0
    DASH[vmware_vms]=0
    DASH[virtualbox_vms]=0
    for item in "${DASH_WORKLOADS[@]}"; do
        IFS=$'\t' read -r backend _name state <<< "$item"
        case "$backend:$state" in
            docker:Up*) DASH[containers]=$((DASH[containers] + 1)) ;;
            libvirt:running) DASH[libvirt_vms]=$((DASH[libvirt_vms] + 1)) ;;
            vmware:running) DASH[vmware_vms]=$((DASH[vmware_vms] + 1)) ;;
            virtualbox:running) DASH[virtualbox_vms]=$((DASH[virtualbox_vms] + 1)) ;;
        esac
    done

    DASH[power_profile]="Unavailable"
    if command_exists tuned-adm; then
        DASH[power_profile]="$(tuned-adm active 2>/dev/null | sed 's/^Current active profile: //')"
    elif command_exists powerprofilesctl; then
        DASH[power_profile]="$(powerprofilesctl get 2>/dev/null || true)"
    fi

    DASH[battery]="Unavailable"
    battery="$(find /sys/class/power_supply -maxdepth 1 -type l -name 'BAT*' 2>/dev/null | head -1)"
    [[ -n "$battery" ]] && DASH[battery]="$(cat "$battery/capacity" 2>/dev/null || printf 'Unavailable')"

    profile_file="$HOME/.local/state/labctl/profile"
    DASH[profile]="unmanaged"
    if [[ -r "$profile_file" ]]; then
        read -r profile < "$profile_file"
        DASH[profile]="$profile"
    fi

    DASH[docker_state]="$(monitor_service_value docker.service)"
    DASH[libvirt_state]="$(monitor_service_value virtqemud.service)"
    DASH[vmware_state]="$(monitor_service_value vmware.service)"
    DASH[ollama_state]="$(monitor_service_value ollama.service)"

    monitor_alert_configuration
    DASH_HEALTH="NORMAL"

    monitor_threshold_alert cpu-temperature "CPU temperature" \
        "${DASH[cpu_temp]}" "$DASH_CPU_WARNING" "$DASH_CPU_CRITICAL" \
        "$DASH_CPU_HYSTERESIS" " °C"
    monitor_threshold_alert gpu-temperature "GPU temperature" \
        "${DASH[gpu_temp]}" "$DASH_GPU_WARNING" "$DASH_GPU_CRITICAL" \
        "$DASH_GPU_HYSTERESIS" " °C"
    monitor_threshold_alert storage "Root filesystem usage" \
        "${DASH[storage_percent]}" "$DASH_STORAGE_WARNING" \
        "$DASH_STORAGE_CRITICAL" "$DASH_STORAGE_HYSTERESIS" "%"

    if [[ "$DASH_FIREWALL_WARNING" == true && "${DASH[firewall]}" != ENABLED ]]; then
        monitor_add_alert firewall warning "Firewall" \
            "Firewall is ${DASH[firewall],,}; enable it if this is not intentional."
    fi
    if [[ "${DASH[updates]}" =~ ^[0-9]+$ ]] &&
       (( DASH[updates] >= DASH_UPDATES_WARNING )); then
        monitor_add_alert updates warning "Package updates" \
            "${DASH[updates]} package updates are available."
    fi

    DASH[health]="$DASH_HEALTH"
    DASH[alert_count]="${#DASH_ALERTS[@]}"
}

monitor_dashboard_text() {
    monitor_dashboard_collect

    print_header "LABCTL WORKSTATION"
    print_status_value "Profile:" "${DASH[profile]}" "info"
    print_status_value "Power Profile:" "${DASH[power_profile]}" "info"
    print_status_value "Health:" "${DASH[health]}" "$([[ "${DASH[health]}" == NORMAL ]] && printf healthy || printf warning)"
    print_status_value "Alerts:" "${DASH[alert_count]}" "$([[ "${DASH[alert_count]}" -gt 0 ]] && printf warning || printf normal)"
    echo
    print_status_value "CPU:" "$(color_by_percentage "${DASH[cpu_usage]}" 70 90)   ${DASH[cpu_temp]} °C" "normal"
    print_status_value "RAM:" "$(monitor_human_bytes "${DASH[memory_used]}") / $(monitor_human_bytes "${DASH[memory_total]}") ($(color_by_percentage "${DASH[memory_percent]}" 75 90))" "normal"
    if [[ "${DASH[gpu_util]}" =~ ^[0-9]+$ ]]; then
        print_status_value "GPU:" "$(color_by_percentage "${DASH[gpu_util]}" 75 95)   ${DASH[gpu_temp]} °C   ${DASH[gpu_power]} W" "normal"
        print_status_value "VRAM:" "${DASH[gpu_mem_used]} / ${DASH[gpu_mem_total]} MiB" "normal"
        print_status_value "GPU State:" "${DASH[gpu_pstate]}   Runtime PM: ${DASH[gpu_runtime]}" "normal"
    else
        print_status_value "GPU:" "Telemetry unavailable (Runtime PM: ${DASH[gpu_runtime]})" "warning"
    fi
    print_status_value "Disk I/O:" "↓ $(monitor_human_bytes "${DASH[disk_read]}")/s   ↑ $(monitor_human_bytes "${DASH[disk_write]}")/s" "normal"
    print_status_value "Storage:" "$(monitor_human_bytes "${DASH[storage_available]}") free / $(monitor_human_bytes "${DASH[storage_total]}") (${DASH[storage_percent]}% used)" "normal"
    if [[ -n "${DASH[interface]:-}" ]]; then
        print_status_value "Network (${DASH[interface]}):" "↓ $(monitor_human_bytes "${DASH[network_rx]}")/s   ↑ $(monitor_human_bytes "${DASH[network_tx]}")/s" "normal"
    else
        print_status_value "Network:" "Unavailable" "warning"
    fi
    print_status_value "IPv4:" "${DASH[ipv4]:-Unavailable}" "normal"
    print_status_value "VPN:" "${DASH[vpn]}" "$([[ "${DASH[vpn]}" == CONNECTED ]] && printf active || printf normal)"
    if [[ "${DASH[battery]}" =~ ^[0-9]+$ ]]; then
        print_status_value "Battery:" "${DASH[battery]}%" "normal"
    else
        print_status_value "Battery:" "${DASH[battery]}" "warning"
    fi
    echo
    print_status_value "Docker:" "$(monitor_service_indicator "${DASH[docker_state]}")" "$([[ "${DASH[docker_state]}" == ACTIVE ]] && printf active || printf normal)"
    print_status_value "Libvirt:" "$(monitor_service_indicator "${DASH[libvirt_state]}")" "$([[ "${DASH[libvirt_state]}" == ACTIVE ]] && printf active || printf normal)"
    print_status_value "VMware:" "$(monitor_service_indicator "${DASH[vmware_state]}")" "$([[ "${DASH[vmware_state]}" == ACTIVE ]] && printf active || printf normal)"
    print_status_value "Ollama:" "$(monitor_service_indicator "${DASH[ollama_state]}")" "$([[ "${DASH[ollama_state]}" == ACTIVE ]] && printf active || printf normal)"
    echo
    print_status_value "Containers:" "${DASH[containers]}" "normal"
    print_status_value "Libvirt VMs:" "${DASH[libvirt_vms]}" "normal"
    print_status_value "VMware VMs:" "${DASH[vmware_vms]}" "normal"
    print_status_value "VirtualBox VMs:" "${DASH[virtualbox_vms]}" "normal"
    print_status_value "Firewall:" "${DASH[firewall]}" "$([[ "${DASH[firewall]}" == ENABLED ]] && printf active || printf warning)"
    print_status_value "Updates:" "${DASH[updates]}" "$([[ "${DASH[updates]}" == 0 ]] && printf normal || printf warning)"
}

monitor_dashboard_json() {
    local item id severity title message backend name state separator=""

    monitor_dashboard_collect
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "timestamp": '; monitor_json_string "${DASH[timestamp]}"; printf ',\n'
    printf '  "health": '; monitor_json_string "${DASH[health],,}"; printf ',\n'
    printf '  "profile": '; monitor_json_string "${DASH[profile]}"; printf ',\n'
    printf '  "power_profile": '; monitor_json_string "${DASH[power_profile]}"; printf ',\n'
    printf '  "resources": {\n'
    printf '    "cpu": {"usage_percent": '; monitor_json_number "${DASH[cpu_usage]}"; printf ', "temperature_c": '; monitor_json_number "${DASH[cpu_temp]}"; printf '},\n'
    printf '    "memory": {"used_bytes": '; monitor_json_number "${DASH[memory_used]}"; printf ', "total_bytes": '; monitor_json_number "${DASH[memory_total]}"; printf ', "usage_percent": '; monitor_json_number "${DASH[memory_percent]}"; printf '},\n'
    printf '    "gpu": {"name": '; monitor_json_string "${DASH[gpu_name]}"; printf ', "usage_percent": '; monitor_json_number "${DASH[gpu_util]}"; printf ', "temperature_c": '; monitor_json_number "${DASH[gpu_temp]}"; printf ', "power_w": '; monitor_json_number "${DASH[gpu_power]}"; printf ', "vram_used_mib": '; monitor_json_number "${DASH[gpu_mem_used]}"; printf ', "vram_total_mib": '; monitor_json_number "${DASH[gpu_mem_total]}"; printf '},\n'
    printf '    "storage": {"available_bytes": '; monitor_json_number "${DASH[storage_available]}"; printf ', "total_bytes": '; monitor_json_number "${DASH[storage_total]}"; printf ', "usage_percent": '; monitor_json_number "${DASH[storage_percent]}"; printf '},\n'
    printf '    "disk_io": {"read_bytes_per_second": '; monitor_json_number "${DASH[disk_read]}"; printf ', "write_bytes_per_second": '; monitor_json_number "${DASH[disk_write]}"; printf '}\n'
    printf '  },\n'
    printf '  "network": {"interface": '; monitor_json_string "${DASH[interface]:-}"; printf ', "ipv4": '; monitor_json_string "${DASH[ipv4]:-Unavailable}"; printf ', "vpn": '; monitor_json_string "${DASH[vpn],,}"; printf ', "receive_bytes_per_second": '; monitor_json_number "${DASH[network_rx]:-}"; printf ', "transmit_bytes_per_second": '; monitor_json_number "${DASH[network_tx]:-}"; printf '},\n'
    printf '  "battery_percent": '; monitor_json_number "${DASH[battery]}"; printf ',\n'
    printf '  "services": {"docker": '; monitor_json_string "${DASH[docker_state],,}"; printf ', "libvirt": '; monitor_json_string "${DASH[libvirt_state],,}"; printf ', "vmware": '; monitor_json_string "${DASH[vmware_state],,}"; printf ', "ollama": '; monitor_json_string "${DASH[ollama_state],,}"; printf '},\n'
    printf '  "security": {"firewall": '; monitor_json_string "${DASH[firewall],,}"; printf ', "updates_available": '; monitor_json_number "${DASH[updates]}"; printf '},\n'
    printf '  "workloads": {"running": {"containers": %s, "libvirt": %s, "vmware": %s, "virtualbox": %s}, "items": [' "${DASH[containers]}" "${DASH[libvirt_vms]}" "${DASH[vmware_vms]}" "${DASH[virtualbox_vms]}"
    for item in "${DASH_WORKLOADS[@]}"; do
        IFS=$'\t' read -r backend name state <<< "$item"
        printf '%s{"backend": ' "$separator"; monitor_json_string "$backend"
        printf ', "name": '; monitor_json_string "$name"
        printf ', "state": '; monitor_json_string "$state"; printf '}'
        separator=", "
    done
    printf ']},\n'
    printf '  "alerts": ['
    separator=""
    for item in "${DASH_ALERTS[@]}"; do
        IFS=$'\t' read -r id severity title message <<< "$item"
        printf '%s{"id": ' "$separator"; monitor_json_string "$id"
        printf ', "severity": '; monitor_json_string "$severity"
        printf ', "title": '; monitor_json_string "$title"
        printf ', "message": '; monitor_json_string "$message"; printf '}'
        separator=", "
    done
    printf ']\n}\n'
}

monitor_dashboard() {
    if [[ "${1:-}" == "--json" || "${1:-}" == "json" ]]; then
        monitor_dashboard_json
    else
        monitor_dashboard_text
    fi
}

monitor_summary() {
    monitor_cpu
    echo
    monitor_memory
    echo
    monitor_gpu
    echo
    monitor_disk
    echo
    monitor_network
    echo
    monitor_power
    echo
    monitor_services
}

monitor_live() {
    local interval="${1:-2}"

    if ! [[ "$interval" =~ ^[1-9][0-9]*$ ]]; then
        print_error "Refresh interval must be a positive integer."
        return 1
    fi

    trap 'printf "\n"; return 0' INT

    while true; do
        clear
        printf 'LabCTL live dashboard — refresh interval: %ss — press Ctrl+C to exit\n\n' "$interval"
        monitor_dashboard
        sleep "$interval"
    done
}

monitor_dispatch() {
    local action="${1:-dashboard}"
    shift || true

    case "$action" in
        dashboard|status) monitor_dashboard "${1:-}" ;;
        summary|detailed|detail) monitor_summary ;;
        live) monitor_live "${1:-2}" ;;
        cpu) monitor_cpu ;;
        memory|mem|ram) monitor_memory ;;
        gpu) monitor_gpu ;;
        disk|storage) monitor_disk ;;
        network|net) monitor_network ;;
        power|battery) monitor_power ;;
        help|-h|--help) monitor_help ;;
        *)
            print_error "Unknown monitor action: $action"
            monitor_help
            return 1
            ;;
    esac
}
