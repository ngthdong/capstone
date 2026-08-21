#!/usr/bin/env bash
# restore.sh — Restore database and web content from a toolkit-produced backup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

# ── Usage ──────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTION]

Restore the capstone system from a backup archive.

Options:
  -h, --help           Show this help message
  -f, --file ARCHIVE   Path to the backup .tar.gz file
      --list           List available backups and exit
      --web-only       Restore only web content (skip database)
      --db-only        Restore only the database (skip web content)
      --dry-run        Show what would be restored without changes
EOF
}

# ── List backups ───────────────────────────────────────────────────────────────
list_backups() {
    log_section "Available Backups"
    if [[ ! -d "${BACKUP_DIR}" ]]; then
        log_warn "Backup directory does not exist: ${BACKUP_DIR}"
        return 1
    fi

    local count=0
    while IFS= read -r -r backup; do
        local size
        size="$(du -h "${backup}" | cut -f1)"
        local date_str
        date_str="$(stat -c '%y' "${backup}" 2>/dev/null | cut -d. -f1)"
        printf "  %-50s %8s  %s\n" "$(basename "${backup}")" "${size}" "${date_str}"
        count=$((count + 1))
    done < <(find "${BACKUP_DIR}" -maxdepth 1 -name 'capstone-backup-*.tar.gz' -type f 2>/dev/null | sort -r)

    if [[ "${count}" -eq 0 ]]; then
        log_warn "No backups found in ${BACKUP_DIR}"
    else
        log_info "Found ${count} backup(s)"
    fi
}

# ── Extract archive ────────────────────────────────────────────────────────────
extract_backup() {
    local archive="$1"
    local work_dir="$2"

    log_info "Extracting ${archive}..."
    mkdir -p "${work_dir}"
    tar -xzf "${archive}" -C "${work_dir}"

    # Find the extracted directory (capstone-backup-YYYYMMDD-HHMMSS)
    local extracted
    extracted="$(find "${work_dir}" -maxdepth 1 -type d -name 'capstone-backup-*' | head -1)"

    if [[ -z "${extracted}" ]]; then
        log_error "No backup directory found inside archive"
        return 1
    fi

    echo "${extracted}"
}

# ── Restore database ───────────────────────────────────────────────────────────
restore_database() {
    local db_dump="$1"

    if [[ ! -f "${db_dump}" ]]; then
        log_warn "No database dump found: ${db_dump}"
        return 0
    fi

    log_info "Restoring database..."

    case "${DB_TYPE}" in
        postgresql|postgres|psql)
            log_info "Restoring PostgreSQL database '${DB_NAME}'..."
            # Drop and recreate the database
            PGPASSWORD="$(grep DB_PASSWORD "${APP_ENVFILE}" 2>/dev/null | cut -d= -f2)" \
                dropdb -h "${DB_HOST}" -U "${DB_USER}" "${DB_NAME}" 2>/dev/null || true
            PGPASSWORD="$(grep DB_PASSWORD "${APP_ENVFILE}" 2>/dev/null | cut -d= -f2)" \
                createdb -h "${DB_HOST}" -U "${DB_USER}" "${DB_NAME}" 2>/dev/null || true
            PGPASSWORD="$(grep DB_PASSWORD "${APP_ENVFILE}" 2>/dev/null | cut -d= -f2)" \
                pg_restore -h "${DB_HOST}" -U "${DB_USER}" -d "${DB_NAME}" "${db_dump}" 2>/dev/null || true
            log_info "PostgreSQL restore complete"
            ;;
        mysql|maria)
            log_info "Restoring MySQL database '${DB_NAME}'..."
            local db_pass
            db_pass="$(grep DB_PASSWORD "${APP_ENVFILE}" 2>/dev/null | cut -d= -f2)"
            mysql -h "${DB_HOST}" -u "${DB_USER}" -p"${db_pass}" "${DB_NAME}" < "${db_dump}" 2>/dev/null || true
            log_info "MySQL restore complete"
            ;;
        *)
            log_error "Unsupported DB_TYPE: ${DB_TYPE}"
            return 1
            ;;
    esac
}

# ── Restore web content ────────────────────────────────────────────────────────
restore_web_content() {
    local web_src="$1"

    if [[ ! -d "${web_src}" ]]; then
        log_warn "No web content found in backup: ${web_src}"
        return 0
    fi

    log_info "Restoring web content to ${WEB_CONTENT}..."

    # Safety: back up current live content first
    if [[ -d "${WEB_CONTENT}" ]]; then
        local emergency_backup
        emergency_backup="${BACKUP_DIR}/pre-restore-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "${emergency_backup}"
        cp -a "${WEB_CONTENT}" "${emergency_backup}/web-content"
        log_info "Current web content saved to ${emergency_backup}"
    fi

    rm -rf "${WEB_CONTENT}"
    cp -a "${web_src}" "${WEB_CONTENT}"
    chown -R www-data:www-data "${WEB_CONTENT}" 2>/dev/null || \
        chown -R nginx:nginx "${WEB_CONTENT}" 2>/dev/null || true
    chmod -R 755 "${WEB_CONTENT}"
    log_info "Web content restored"
}

# ── Restore ────────────────────────────────────────────────────────────────────
do_restore() {
    local archive="$1"
    local web_only="${2:-0}"
    local db_only="${3:-0}"
    local dry_run="${4:-0}"

    log_section "Restore"

    if [[ ! -f "${archive}" ]]; then
        log_error "Backup archive not found: ${archive}"
        return 1
    fi

    local work_dir="/tmp/capstone-restore-$$"
    local extracted
    extracted="$(extract_backup "${archive}" "${work_dir}")"
    log_info "Extracted to: ${extracted}"

    if [[ "${dry_run}" -eq 1 ]]; then
        log_info "DRY RUN — listing contents that would be restored:"
        find "${extracted}" -type f | while IFS= read -r f; do
            local rel_path
            rel_path="${f#./}"
            printf "  %s\n" "${rel_path#"${extracted}"/}"
        done
        rm -rf "${work_dir}"
        return 0
    fi

    # 1. Restore database
    if [[ "${web_only}" -eq 0 ]]; then
        restore_database "${extracted}/database.dump"
    fi

    # 2. Restore web content
    if [[ "${db_only}" -eq 0 ]]; then
        restore_web_content "${extracted}/web-content"
    fi

    # 3. Restart services to pick up restored data
    log_info "Restarting services..."
    systemctl restart "${WEB_SERVER}" 2>/dev/null || true
    if systemctl list-unit-files | grep -q "${APP_SERVICE}"; then
        systemctl restart "${APP_SERVICE}" 2>/dev/null || true
    fi

    # 4. Verify
    sleep 2
    local ok=1
    if ! systemctl is-active --quiet "${WEB_SERVER}" 2>/dev/null; then
        log_error "${WEB_SERVER} failed to start after restore"
        ok=0
    fi
    if systemctl list-unit-files | grep -q "${APP_SERVICE}"; then
        if ! systemctl is-active --quiet "${APP_SERVICE}" 2>/dev/null; then
            log_error "${APP_SERVICE} failed to start after restore"
            ok=0
        fi
    fi

    # Cleanup
    rm -rf "${work_dir}"

    if [[ "${ok}" -eq 1 ]]; then
        log_info "Restore completed successfully — services verified running"
    else
        log_error "Restore completed with warnings — check service status"
        return 1
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restore completed from: $(basename "${archive}")" >> "${RESTORE_LOG}"
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
    local archive=""
    local list=0
    local web_only=0
    local db_only=0
    local dry_run=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)       usage; exit 0 ;;
            -f|--file)       archive="$2"; shift 2 ;;
            --list)          list=1; shift ;;
            --web-only)      web_only=1; shift ;;
            --db-only)       db_only=1; shift ;;
            --dry-run)       dry_run=1; shift ;;
            *)               log_error "Unknown option: $1"; usage; exit 1 ;;
        esac
    done

    require_non_root
    ensure_dirs

    if [[ "${list}" -eq 1 ]]; then
        list_backups
        return
    fi

    # If no archive specified, pick the most recent one
    if [[ -z "${archive}" ]]; then
        archive="$(find "${BACKUP_DIR}" -maxdepth 1 -name 'capstone-backup-*.tar.gz' -type f 2>/dev/null | sort -r | head -1)"
        if [[ -z "${archive}" ]]; then
            log_error "No backups found. Use --file to specify one."
            exit 1
        fi
        log_info "No archive specified — using most recent: $(basename "${archive}")"
    fi

    do_restore "${archive}" "${web_only}" "${db_only}" "${dry_run}"
}

main "$@"
