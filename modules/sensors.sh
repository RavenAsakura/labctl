#!/usr/bin/env bash

# LabCTL sensors module

sensors_help(){ cat <<'HELP'
Usage:
  labctl sensors
  labctl sensors status
  labctl sensors watch
  labctl sensors json
HELP
}

sensors_collect(){
command -v sensors >/dev/null || { echo '[ERROR] lm-sensors is not installed.' >&2; return 1; }
SENSOR_DATA="$(sensors 2>/dev/null)"
CPU_PACKAGE="$(printf '%s
' "$SENSOR_DATA"|awk '/Package id 0:/{print $4;exit}')"
CPU_MAX="$(printf '%s
' "$SENSOR_DATA"|awk '/^Core [0-9]+:/{v=$3;gsub(/\+|°C/,"",v);if(v+0>m)m=v+0}END{if(m)printf "%.1f°C",m;else print "N/A"}')"
GPU_TEMP="$(printf '%s
' "$SENSOR_DATA"|awk '/^GPU:/{print $2;exit}')"
FAN_LEFT="$(printf '%s
' "$SENSOR_DATA"|awk '/^fan1:/{print $2" RPM";exit}')"
FAN_RIGHT="$(printf '%s
' "$SENSOR_DATA"|awk '/^fan2:/{print $2" RPM";exit}')"
mapfile -t NVME_TEMPS < <(printf '%s
' "$SENSOR_DATA"|awk '/^nvme-pci-/{d=$1;i=1;next} i&&/^Composite:/{print d"|"$2;i=0}')
if command -v powerprofilesctl >/dev/null; then POWER_PROFILE=$(powerprofilesctl get); elif command -v tuned-adm >/dev/null; then POWER_PROFILE=$(tuned-adm active|sed 's/^Current active profile: //'); else POWER_PROFILE=unknown; fi
}

sensors_status(){ sensors_collect||return 1; echo '=============================================================='; echo ' HARDWARE STATUS'; echo '=============================================================='; echo "CPU Package: $CPU_PACKAGE"; echo "CPU Max: $CPU_MAX"; echo "GPU: $GPU_TEMP"; echo "Fan Left: $FAN_LEFT"; echo "Fan Right: $FAN_RIGHT"; if ((${#NVME_TEMPS[@]})); then for i in "${!NVME_TEMPS[@]}"; do d=${NVME_TEMPS[$i]%%|*}; t=${NVME_TEMPS[$i]#*|}; echo "NVMe$i ($d): $t"; done; else echo 'NVMe: N/A'; fi; echo "Power Profile: $POWER_PROFILE"; }

sensors_watch(){ while true; do clear; sensors_status; sleep 1; done; }

sensors_json(){ sensors_collect||return 1; printf '{\n  "cpu_package":"%s",\n  "cpu_max_core":"%s",\n  "gpu_temperature":"%s",\n  "fan_left":"%s",\n  "fan_right":"%s",\n  "power_profile":"%s"\n}\n' "$CPU_PACKAGE" "$CPU_MAX" "$GPU_TEMP" "$FAN_LEFT" "$FAN_RIGHT" "$POWER_PROFILE"; }

sensors_dispatch(){ case "${1:-status}" in status|'') sensors_status;; watch) sensors_watch;; json) sensors_json;; help|-h|--help) sensors_help;; *) echo "[ERROR] Unknown sensors command: ${1}"; return 1;; esac; }
