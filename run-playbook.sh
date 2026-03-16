#!/usr/bin/env bash
# run-playbook.sh
# Wrapper around ansible-playbook that tee-s all output into a timestamped
# log file under ./logs/.
#
# Usage: ./run-playbook.sh [ansible-playbook arguments...]
# Example:
#   ./run-playbook.sh site.yml \
#     -e @inventories/production/group_vars/vault.yml \
#     --vault-password-file .vault_pass

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
_red()   { printf '\033[31m%s\033[0m\n' "$*"; }
_green() { printf '\033[32m%s\033[0m\n' "$*"; }
_cyan()  { printf '\033[36m%s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# Require at least one argument (the playbook file)
# ---------------------------------------------------------------------------
if [[ $# -eq 0 ]]; then
    _red "Usage: $0 <playbook.yml> [ansible-playbook options...]"
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve the playbook name for use in the log filename.
# Walk the argument list and take the first positional argument (no leading -)
# that ends in .yml or .yaml.
# ---------------------------------------------------------------------------
PLAYBOOK_NAME="playbook"
for arg in "$@"; do
    if [[ "$arg" != -* && ( "$arg" == *.yml || "$arg" == *.yaml ) ]]; then
        PLAYBOOK_NAME="$(basename "${arg%.*}")"
        break
    fi
done

# ---------------------------------------------------------------------------
# Build log file path: logs/YYYYMMDD_HHMMSS_<playbook>.log
# ---------------------------------------------------------------------------
LOGS_DIR="$(cd "$(dirname "$0")" && pwd)/logs"
mkdir -p "$LOGS_DIR"

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
LOG_FILE="${LOGS_DIR}/${TIMESTAMP}_${PLAYBOOK_NAME}.log"

# ---------------------------------------------------------------------------
# Write a structured header into the log
# ---------------------------------------------------------------------------
{
    echo "================================================================"
    echo " Ansible Playbook Execution Log"
    echo "================================================================"
    echo " Timestamp : $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo " Playbook  : ${PLAYBOOK_NAME}"
    echo " User      : $(id -un)"
    echo " Host      : $(hostname -f 2>/dev/null || hostname)"
    echo " Command   : ansible-playbook $*"
    echo "================================================================"
    echo
} >> "$LOG_FILE"

_cyan "Logging to: ${LOG_FILE}"
echo

# ---------------------------------------------------------------------------
# Run ansible-playbook, streaming output to terminal AND log file.
# Capture the exit code from ansible-playbook, not from tee.
# ---------------------------------------------------------------------------
set +e
ansible-playbook "$@" 2>&1 | tee -a "$LOG_FILE"
EXIT_CODE="${PIPESTATUS[0]}"
set -e

# ---------------------------------------------------------------------------
# Write a footer with the result
# ---------------------------------------------------------------------------
{
    echo
    echo "================================================================"
    if [[ "$EXIT_CODE" -eq 0 ]]; then
        echo " Result    : SUCCESS (exit code 0)"
    else
        echo " Result    : FAILED  (exit code ${EXIT_CODE})"
    fi
    echo " Finished  : $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "================================================================"
} >> "$LOG_FILE"

# Mirror the result to the terminal
echo
if [[ "$EXIT_CODE" -eq 0 ]]; then
    _green "Playbook completed successfully. Log: ${LOG_FILE}"
else
    _red "Playbook failed (exit code ${EXIT_CODE}). Log: ${LOG_FILE}"
fi

exit "$EXIT_CODE"
