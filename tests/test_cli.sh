#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT_DIR
readonly LABCTL="$PROJECT_DIR/labctl"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    local output="${1:-}"
    local expected="${2:-}"

    [[ "$output" == *"$expected"* ]] ||
        fail "Expected output to contain: $expected"
}

test_syntax() {
    local file

    bash -n "$LABCTL" "$PROJECT_DIR/labctl.health.backup"

    for file in "$PROJECT_DIR"/modules/*.sh; do
        bash -n "$file"
    done
}

test_general_commands() {
    local output

    output="$($LABCTL version)"
    assert_contains "$output" "labctl 2.3.0-dev"

    output="$($LABCTL modules)"
    assert_contains "$output" "doctor"
    assert_contains "$output" "profile"
    assert_contains "$output" "virtualbox"
}

test_qemu_dispatch() {
    local output

    output="$($LABCTL qemu backend)"

    case "$output" in
        classic|modular|unavailable) ;;
        *) fail "Unexpected qemu backend output: $output" ;;
    esac
}

test_profile_dry_run() {
    local output

    output="$($LABCTL work --dry-run)"
    assert_contains "$output" "Dry run"
    assert_contains "$output" "no services or settings were changed"
}

test_redirected_output_has_no_ansi() {
    local output

    output="$($LABCTL about)"

    if [[ "$output" == *$'\033['* ]]; then
        fail "Redirected output contains ANSI escape sequences"
    fi
}

test_dashboard_json_contract() {
    local output cache_home alert_config

    cache_home="$(mktemp -d)"
    trap 'rm -rf "$cache_home"' RETURN
    output="$(XDG_CACHE_HOME="$cache_home" "$LABCTL" monitor dashboard --json)"

    python3 -c '
import json, sys
data = json.load(sys.stdin)
assert data["schema_version"] == 1
assert data["health"] in {"normal", "warning", "critical"}
assert "cpu" in data["resources"]
assert "items" in data["workloads"]
assert isinstance(data["alerts"], list)
' <<< "$output" || fail "Dashboard did not return valid schema version 1 JSON"

    alert_config="$cache_home/alerts.conf"
    cat > "$alert_config" <<'ALERTS'
storage_warning=0
storage_critical=0
storage_hysteresis=0
updates_warning=999999
firewall_warning=false
ALERTS
    output="$(
        XDG_CACHE_HOME="$cache_home" \
        LABCTL_ALERT_CONFIG="$alert_config" \
        "$LABCTL" monitor dashboard --json
    )"
    python3 -c '
import json, sys
data = json.load(sys.stdin)
assert data["health"] == "critical"
assert any(
    alert["id"] == "storage" and alert["severity"] == "critical"
    for alert in data["alerts"]
)
' <<< "$output" || fail "Custom dashboard alert thresholds were not applied"
}

test_syntax
test_general_commands
test_qemu_dispatch
test_profile_dry_run
test_redirected_output_has_no_ansi
test_dashboard_json_contract

printf 'All CLI tests passed.\n'
