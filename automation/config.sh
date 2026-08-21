#!/usr/bin/env bash
# config.sh — Shared configuration and helper functions for the capstone toolkit.
# Source this file; do not execute directly.
# shellcheck disable=SC2034  # Variables are used by sourcing scripts

# ── Paths ──────────────────────────────────────────────────────────────────────
_TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TOOLKIT_DIR="${_TOOLKIT_DIR}"
readonly LOG_DIR="/var/log/capstone"
readonly BACKUP_DIR="/var/backups/capstone"
readonly HEALTH_LOG="${LOG_DIR}/health-check.log"
readonly DEPLOY_LOG="${LOG_DIR}/deploy.log"
readonly RESTORE_LOG="${LOG_DIR}/restore.log"
readonly APP_ENVFILE="/etc/capstone/app.env"
readonly APP_SERVICE="capstone-app"
readonly WEB_SERVER="nginx"
readonly DB_TYPE="${DB_TYPE:-postgresql}"          # postgresql | mysql
readonly DB_NAME="${DB_NAME:-capstone}"
readonly DB_USER="${DB_USER:-capstone}"
readonly DB_HOST="127.0.0.1"
readonly WEB_CONTENT="/var/www/capstone"
readonly RSYNC_REMOTE="${RSYNC_REMOTE:-}"          # user@host:/path (second VM)
readonly RETENTION_DAYS="${RETENTION_DAYS:-7}"
readonly HEALTH_CPU_THRESHOLD="${HEALTH_CPU_THRESHOLD:-90}"
readonly HEALTH_DISK_THRESHOLD="${HEALTH_DISK_THRESHOLD:-85}"
readonly HEALTH_RAM_THRESHOLD="${HEALTH_RAM_THRESHOLD:-85}"
readonly ALERT_CHANNEL="${ALERT_CHANNEL:-email}"   # email | telegram | log-only
readonly TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
readonly TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
readonly ALERT_EMAIL="${ALERT_EMAIL:-root@localhost}"

# ── Colours / formatting ──────────────────────────────────────────────────────
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'  # No Colour

# ── Helper functions ──────────────────────────────────────────────────────────
log_info()    { printf '%b\n' "${GREEN}[INFO]${NC}  $*"; }
log_warn()    { printf '%b\n' "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { printf '%b\n' "${RED}[ERROR]${NC} $*" >&2; }
log_section() { printf '\n%b\n' "${BOLD}${BLUE}══ $* ══${NC}"; }

ensure_dirs() {
    mkdir -p "${LOG_DIR}" "${BACKUP_DIR}"
}

# Send an alert via the configured channel.
# Usage: alert "subject" "message body"
alert() {
    local subject="$1"
    local body="$2"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    # Always log locally
    printf "[%s] %s: %s\n" "${timestamp}" "${subject}" "${body}" >> "${HEALTH_LOG}"

    case "${ALERT_CHANNEL}" in
        email)
            if command -v mail &>/dev/null; then
                echo "${body}" | mail -s "[Capstone] ${subject}" "${ALERT_EMAIL}"
                log_info "Alert emailed to ${ALERT_EMAIL}"
            else
                log_warn "mail command not found; alert logged only"
            fi
            ;;
        telegram)
            if [[ -n "${TELEGRAM_BOT_TOKEN}" && -n "${TELEGRAM_CHAT_ID}" ]]; then
                curl -s -X POST \
                    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                    -d "chat_id=${TELEGRAM_CHAT_ID}" \
                    -d "text=[Capstone] ${subject}: ${body}" \
                    &>/dev/null
                log_info "Alert sent to Telegram"
            else
                log_warn "Telegram credentials not set; alert logged only"
            fi
            ;;
        log-only|*)
            log_warn "Alert logged only (channel=${ALERT_CHANNEL})"
            ;;
    esac
}

# Confirm a prompt. Returns 0 for yes, 1 for no.
confirm() {
    local prompt="${1:-Continue?}"
    read -r -p "${prompt} [y/N]: " answer
    case "${answer}" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# Check that the script is NOT running as root.
require_non_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        log_error "Do not run this script as root. Use sudo where needed."
        exit 1
    fi
}

# Check that required commands exist.
require_commands() {
    local cmd
    for cmd in "$@"; do
        if ! command -v "${cmd}" &>/dev/null; then
            log_error "Required command '${cmd}' not found. Please install it."
            exit 1
        fi
    done
}
