#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT_DIR

# shellcheck disable=SC1091
source "$PROJECT_DIR/modules/utils.sh"
# shellcheck disable=SC1091
source "$PROJECT_DIR/modules/profile.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

profile_load_modules() {
    return 0
}

power_current() {
    printf 'balanced\n'
}

profile_component_active() {
    [[ "${1:-}" == "docker" ]]
}

output="$(profile_apply_selection work --dry-run)"
[[ "$output" == *"Dry run"* ]] || fail "Profile dry run was not reported"

set +e
output="$(profile_apply_selection work </dev/null 2>&1)"
status=$?
set -e

(( status != 0 )) || fail "Non-interactive destructive profile was accepted"
[[ "$output" == *"Use --yes"* ]] || fail "Missing non-interactive safety message"

calls_file="$(mktemp)"
readonly calls_file
trap 'rm -f "$calls_file"' EXIT

profile_apply_component() {
    local component="${1:-}"
    local desired="${2:-}"

    printf '%s %s\n' "$component" "$desired" >> "$calls_file"

    [[ "$component $desired" != "qemu active" ]]
}

profile_set_power() {
    printf 'power %s\n' "${1:-}" >> "$calls_file"
}

set +e
output="$(profile_apply_selection qemu --yes 2>&1)"
status=$?
set -e

(( status != 0 )) || fail "Simulated component failure was ignored"
[[ "$output" == *"Restoring the previous component state"* ]] ||
    fail "Rollback was not attempted"
grep -Fxq 'docker active' "$calls_file" ||
    fail "Docker state was not restored"
grep -Fxq 'power balanced' "$calls_file" ||
    fail "Power profile was not restored"

printf 'All profile safety tests passed.\n'
