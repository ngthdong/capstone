#!/usr/bin/env bash
# health-check.sh — Inspect real system state: CPU, disk, RAM, listening ports,
# and service status. Alerts on threshold breach.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

# ── Usage ──────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTION]

Health-check: CPU, disk, RAM, listening ports, and service status.

Options:
  -h, --help              Show this help message
      --cpu-threshold N   CPU usage % threshold (default: ${HEALTH_CPU_THRESHOLD})
      --disk-threshold N  Disk usage % threshold (default: ${HEALTH_DISK_THRESHOLD})
      --ram-threshold N   RAM usage % threshold (default: ${HEALTH_RAM_THRESHOLD})
EOF
}

# ── Checks ─────────────────────────────────────────────────────────────────────
ISSUES=0

check_cpu() {
    local threshold="${1:-${HEALTH_CPU_THRESHOLD}}"
    local cpu_usage

    # Get CPU usage from /proc/stat (1-second sample)
    cpu_usage="$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}' | cut -d. -f1)"

    if [[ -z "${cpu_usage}" ]]; then
        # Fallback: vmstat
        cpu_usage="$(vmstat 1 2 | tail -1 | awk '{print 100 - $15}' | cut -d. -f1)"
    fi

    if [[ "${cpu_usage}" -ge "${threshold}" ]]; then
        log_error "CPU usage: ${cpu_usage}% (threshold: ${threshold}%)"
        ISSUES=$((ISSUES + 1))
        return 1
    else
        log_info "CPU usage: ${cpu_usage}% — OK"
        return 0
    fi
}

check_disk() {
    local threshold="${1:-${HEALTH_DISK_THRESHOLD}}"
    local issues_before=${ISSUES}

    log_info "Checking disk usage..."
    while IFS= read -r line; do
        local usage mount
        usage="$(echo "${line}" | awk '{print $5}' | tr -d '%')"
        mount="$(echo "${line}" | awk '{print $6}')"

        if [[ "${usage}" -ge "${threshold}" ]]; then
            log_error "Disk ${mount}: ${usage}% used (threshold: ${threshold}%)"
            ISSUES=$((ISSUES + 1))
        fi
    done < <(df -h --output=pcent,target -x tmpfs -x devtmpfs 2>/dev/null | tail -n +2)

    if [[ "${ISSUES}" -eq "${issues_before}" ]]; then
        log_info "Disk usage: all partitions under ${threshold}% — OK"
    fi
}

check_ram() {
    local threshold="${1:-${HEALTH_RAM_THRESHOLD}}"
    local ram_usage

    # Parse free -m for memory usage percentage
    ram_usage="$(free | awk '/^Mem:/ {printf "%.0f", ($3/$2) * 100}')"

    if [[ "${ram_usage}" -ge "${threshold}" ]]; then
        log_error "RAM usage: ${ram_usage}% (threshold: ${threshold}%)"
        ISSUES=$((ISSUES + 1))
        return 1
    else
        log_info "RAM usage: ${ram_usage}% — OK"
        return 0
    fi
}

check_services() {
    local services=("${WEB_SERVER}" "${APP_SERVICE}" "sshd" "fail2ban")
    local issues_before=${ISSUES}

    log_info "Checking services..."
    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "${svc}" 2>/dev/null; then
            log_info "  ${svc}: running — OK"
        else
            log_error "  ${svc}: NOT running"
            ISSUES=$((ISSUES + 1))
        fi
    done
}

check_listening_ports() {
    log_info "Checking listening ports..."

    # Expected ports: 80/443 (web), app port (e.g. 5000/8000), 22 (SSH)
    local expected_ports=(22 80 443 5000 8000 3306 5432)
    local found_any=0

    for port in "${expected_ports[@]}"; do
        if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
            log_info "  Port ${port}: listening"
            found_any=1
        fi
    done

    if [[ "${found_any}" -eq 0 ]]; then
        log_warn "No expected services found listening"
    fi
}

check_database() {
    log_info "Checking database..."

    if [[ ! -f "${APP_ENVFILE}" ]]; then
        log_warn "Environment file not found — skipping DB check"
        return 0
    fi

    case "${DB_TYPE}" in
        postgresql|postgres|psql)
            if PGPASSWORD="$(grep DB_PASSWORD "${APP_ENVFILE}" 2>/dev/null | cut -d= -f2)" \
                pg_isready -h "${DB_HOST}" -U "${DB_USER}" -d "${DB_NAME}" &>/dev/null; then
                log_info "  PostgreSQL: accepting connections — OK"
            else
                log_error "  PostgreSQL: not responding"
                ISSUES=$((ISSUES + 1))
            fi
            ;;
        mysql|maria)
            local db_pass
            db_pass="$(grep DB_PASSWORD "${APP_ENVFILE}" 2>/dev/null | cut -d= -f2)"
            if mysqladmin -h "${DB_HOST}" -u "${DB_USER}" -p"${db_pass}" ping &>/dev/null; then
                log_info "  MySQL: responding — OK"
            else
                log_error "  MySQL: not responding"
                ISSUES=$((ISSUES + 1))
            fi
            ;;
    esac
}

check_backup_freshness() {
    log_info "Checking backup freshness..."

    if [[ ! -d "${BACKUP_DIR}" ]]; then
        log_warn "No backup directory found"
        return 0
    fi

    local newest
    newest="$(find "${BACKUP_DIR}" -maxdepth 1 -name 'capstone-backup-*.tar.gz' -type f 2>/dev/null | sort -r | head -1)"

    if [[ -z "${newest}" ]]; then
        log_warn "No backups found"
        return 0
    fi

    local age_days
    age_days="$(( ($(date +%s) - $(stat -c %Y "${newest}")) / 86400 ))"

    if [[ "${age_days}" -gt "${RETENTION_DAYS}" ]]; then
        log_error "Newest backup is ${age_days} days old (retention: ${RETENTION_DAYS} days)"
        ISSUES=$((ISSUES + 1))
    else
        log_info "  Newest backup: $(basename "${newest}") (${age_days} days old) — OK"
    fi
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
    local cpu_thresh="${HEALTH_CPU_THRESHOLD}"
    local disk_thresh="${HEALTH_DISK_THRESHOLD}"
    local ram_thresh="${HEALTH_RAM_THRESHOLD}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)            usage; exit 0 ;;
            --cpu-threshold)      cpu_thresh="$2"; shift 2 ;;
            --disk-threshold)     disk_thresh="$2"; shift 2 ;;
            --ram-threshold)      ram_thresh="$2"; shift 2 ;;
            *)                    log_error "Unknown option: $1"; usage; exit 1 ;;
        esac
    done

    ensure_dirs

    log_section "Health Check — $(date '+%Y-%m-%d %H:%M:%S')"

    check_cpu "${cpu_thresh}"
    check_disk "${disk_thresh}"
    check_ram "${ram_thresh}"
    check_services
    check_listening_ports
    check_database
    check_backup_freshness

    echo
    if [[ "${ISSUES}" -gt 0 ]]; then
        log_error "Health check: ${ISSUES} issue(s) detected"
        alert "Health Check ALERT" "${ISSUES} issue(s) detected on $(hostname). Check ${HEALTH_LOG} for details."
        exit 1
    else
        log_info "Health check: all OK"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Health check: PASS" >> "${HEALTH_LOG}"
        exit 0
    fi
}

main "$@"
