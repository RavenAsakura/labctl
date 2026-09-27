#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT_DIR

# shellcheck disable=SC1091
source "$PROJECT_DIR/modules/utils.sh"

if (( EUID == 0 )); then
    printf 'PolicyKit selection test skipped while running as root.\n'
    exit 0
fi

temporary_directory="$(mktemp -d)"
readonly temporary_directory
trap 'rm -rf "$temporary_directory"' EXIT

cat > "$temporary_directory/pkexec" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$LABCTL_TEST_PKEXEC_LOG"
"$@"
MOCK
chmod +x "$temporary_directory/pkexec"

export LABCTL_TEST_PKEXEC_LOG="$temporary_directory/pkexec.log"
export LABCTL_USE_PKEXEC=1
export PATH="$temporary_directory:$PATH"

run_privileged /bin/true

grep -Fxq '/bin/true' "$LABCTL_TEST_PKEXEC_LOG" || {
    printf 'FAIL: PolicyKit backend was not selected.\n' >&2
    exit 1
}

printf 'PolicyKit selection test passed.\n'
