#!/usr/bin/env bash
# backup.sh — Automated backup: DB dump + web content, compress, timestamp,
# retention, and rsync to a second VM.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

# ── Usage ──────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTION]

Back up the capstone database and web content.

Options:
  -h, --help         Show this help message
  -d, --dest DIR     Local backup destination (default: ${BACKUP_DIR})
      --no-rsync     Skip rsync to remote VM
      --retention N  Override retention in days (default: ${RETENTION_DAYS})
EOF
}

# ── Dump database ──────────────────────────────────────────────────────────────
dump_database() {
    local output_file="$1"

    case "${DB_TYPE}" in
        postgresql|postgres|psql)
            log_info "Dumping PostgreSQL database '${DB_NAME}'..."
            if PGPASSWORD="$(grep DB_PASSWORD "${APP_ENVFILE}" 2>/dev/null | cut -d= -f2)" \
                pg_dump -h "${DB_HOST}" -U "${DB_USER}" -d "${DB_NAME}" \
                -Fc -f "${output_file}" 2>/dev/null; then
                log_info "PostgreSQL dump complete: ${output_file}"
            else
                log_error "PostgreSQL dump failed"
                return 1
            fi
            ;;
        mysql|maria)
            log_info "Dumping MySQL database '${DB_NAME}'..."
            local db_pass
            db_pass="$(grep DB_PASSWORD "${APP_ENVFILE}" 2>/dev/null | cut -d= -f2)"
            if mysqldump -h "${DB_HOST}" -u "${DB_USER}" -p"${db_pass}" \
                "${DB_NAME}" --single-transaction > "${output_file}" 2>/dev/null; then
                log_info "MySQL dump complete: ${output_file}"
            else
                log_error "MySQL dump failed"
                return 1
            fi
            ;;
        *)
            log_error "Unsupported DB_TYPE: ${DB_TYPE}"
            return 1
            ;;
    esac
}

# ── Create backup archive ──────────────────────────────────────────────────────
create_backup() {
    local dest_dir="${1:-${BACKUP_DIR}}"
    local timestamp
    timestamp="$(date +%Y%m%d-%H%M%S)"
    local backup_name="capstone-backup-${timestamp}"
    local work_dir="${dest_dir}/${backup_name}"
    local archive="${dest_dir}/${backup_name}.tar.gz"

    mkdir -p "${dest_dir}" "${work_dir}"

    log_section "Backup — ${timestamp}"

    # 1. Dump database
    local db_dump="${work_dir}/database.dump"
    if [[ -f "${APP_ENVFILE}" ]]; then
        dump_database "${db_dump}" || log_warn "Database dump failed — continuing with web-only backup"
    else
        log_warn "Environment file ${APP_ENVFILE} not found — skipping DB dump"
    fi

    # 2. Copy web content
    if [[ -d "${WEB_CONTENT}" ]]; then
        log_info "Copying web content..."
        cp -a "${WEB_CONTENT}" "${work_dir}/web-content"
        log_info "Web content copied"
    else
        log_warn "Web content directory not found: ${WEB_CONTENT}"
    fi

    # 3. Copy relevant config files
    log_info "Backing up configuration files..."
    mkdir -p "${work_dir}/config"
    for f in /etc/nginx/nginx.conf /etc/httpd/conf/httpd.conf \
             /etc/fail2ban/jail.local /etc/audit/audit.rules \
             /etc/ssh/sshd_config; do
        if [[ -f "$f" ]]; then
            cp "$f" "${work_dir}/config/" 2>/dev/null || true
        fi
    done

    # 4. Compress
    log_info "Compressing backup..."
    tar -czf "${archive}" -C "${dest_dir}" "${backup_name}"
    rm -rf "${work_dir}"
    log_info "Archive created: ${archive} ($(du -h "${archive}" | cut -f1))"

    echo "${archive}"
}

# ── Retention ──────────────────────────────────────────────────────────────────
apply_retention() {
    local dest_dir="${1:-${BACKUP_DIR}}"
    local retention_days="${2:-${RETENTION_DAYS}}"

    log_info "Applying retention policy: removing backups older than ${retention_days} days..."

    local count=0
    while IFS= read -r -d '' old_file; do
        rm -f "${old_file}"
        log_info "Removed old backup: $(basename "${old_file}")"
        count=$((count + 1))
    done < <(find "${dest_dir}" -maxdepth 1 -name 'capstone-backup-*.tar.gz' -mtime "+${retention_days}" -print0 2>/dev/null)

    if [[ "${count}" -eq 0 ]]; then
        log_info "No old backups to remove"
    else
        log_info "Removed ${count} old backup(s)"
    fi
}

# ── Rsync to remote ────────────────────────────────────────────────────────────
rsync_to_remote() {
    local archive="$1"

    if [[ -z "${RSYNC_REMOTE}" ]]; then
        log_warn "RSYNC_REMOTE not set — skipping remote sync"
        return 0
    fi

    log_info "Syncing backup to remote: ${RSYNC_REMOTE}..."
    if rsync -avz --progress "${archive}" "${RSYNC_REMOTE}/" 2>&1; then
        log_info "Remote sync complete"
    else
        log_error "Remote sync failed"
        return 1
    fi
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
    local dest_dir="${BACKUP_DIR}"
    local do_rsync=1
    local retention="${RETENTION_DAYS}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)       usage; exit 0 ;;
            -d|--dest)       dest_dir="$2"; shift 2 ;;
            --no-rsync)      do_rsync=0; shift ;;
            --retention)     retention="$2"; shift 2 ;;
            *)               log_error "Unknown option: $1"; usage; exit 1 ;;
        esac
    done

    require_non_root
    require_commands tar
    ensure_dirs

    local archive
    archive="$(create_backup "${dest_dir}")"

    apply_retention "${dest_dir}" "${retention}"

    if [[ "${do_rsync}" -eq 1 && -n "${RSYNC_REMOTE}" ]]; then
        rsync_to_remote "${archive}"
    fi

    log_info "Backup process complete"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup created: $(basename "${archive}")" >> "${LOG_DIR}/backup.log"
}

main "$@"
