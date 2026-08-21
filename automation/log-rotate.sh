#!/usr/bin/env bash
# log-rotate.sh — Rotate and compress a chosen log, keep N generations, remove older.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

# ── Usage ──────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTION]

Rotate and compress log files with configurable retention.

Options:
  -h, --help        Show this help message
  -f, --file LOG    Log file to rotate (required unless --all)
      --all         Rotate all capstone logs
  -n, --keep N      Number of generations to keep (default: 5)
      --dry-run     Show what would be done without making changes
EOF
}

# ── Rotate a single log file ──────────────────────────────────────────────────
rotate_log() {
    local logfile="$1"
    local keep="${2:-5}"
    local dry_run="${3:-0}"

    if [[ ! -f "${logfile}" ]]; then
        log_error "Log file not found: ${logfile}"
        return 1
    fi

    local basename
    basename="$(basename "${logfile}")"
    local dir
    dir="$(dirname "${logfile}")"

    log_info "Rotating: ${logfile}"

    # 1. Compress the current log if it has content and is not already compressed
    if [[ -s "${logfile}" && "${logfile}" != *.gz ]]; then
        local timestamp
        timestamp="$(date +%Y%m%d-%H%M%S)"
        local archive="${dir}/${basename}.${timestamp}.gz"

        if [[ "${dry_run}" -eq 0 ]]; then
            gzip -c "${logfile}" > "${archive}"
            : > "${logfile}"  # Truncate the original
            log_info "Compressed to: ${archive} ($(du -h "${archive}" | cut -f1))"
        else
            log_info "[dry-run] Would compress ${logfile} → ${archive}"
        fi
    fi

    # 2. Remove old rotated copies beyond retention
    log_info "Keeping ${keep} most recent rotations..."
    local remove_count=0

    while IFS= read -r -d '' old_file; do
        if [[ "${dry_run}" -eq 0 ]]; then
            rm -f "${old_file}"
            log_info "Removed: $(basename "${old_file}")"
        else
            log_info "[dry-run] Would remove: $(basename "${old_file}")"
        fi
        remove_count=$((remove_count + 1))
    done < <(find "${dir}" -maxdepth 1 -name "${basename}.*.gz" -type f -printf '%T@ %p\0' 2>/dev/null \
        | sort -rn | tail -n "+$((keep + 1))" | cut -d' ' -f2- | tr '\0' '\n' | head -n "${remove_count:-999}" | xargs -0 -I{} printf '%s\0' {})

    # Alternative approach using sort + head
    if [[ "${remove_count}" -eq 0 ]]; then
        local total
        total="$(find "${dir}" -maxdepth 1 -name "${basename}.*.gz" -type f 2>/dev/null | wc -l)"

        if [[ "${total}" -gt "${keep}" ]]; then
            local to_remove=$((total - keep))
            while IFS= read -r old_file; do
                if [[ "${dry_run}" -eq 0 ]]; then
                    rm -f "${old_file}"
                    log_info "Removed: $(basename "${old_file}")"
                else
                    log_info "[dry-run] Would remove: $(basename "${old_file}")"
                fi
            done < <(find "${dir}" -maxdepth 1 -name "${basename}.*.gz" -type f -printf '%T+ %p\n' 2>/dev/null \
                | sort | head -n "${to_remove}" | awk '{print $2}')
        fi
    fi
}

# ── Rotate capstone-specific logs ─────────────────────────────────────────────
rotate_capstone_logs() {
    local keep="${1:-5}"
    local dry_run="${2:-0}"

    log_section "Capstone Log Rotation"

    # Rotate capstone toolkit logs
    local logs=(
        "${LOG_DIR}/health-check.log"
        "${LOG_DIR}/deploy.log"
        "${LOG_DIR}/restore.log"
        "${LOG_DIR}/backup.log"
    )

    # Also rotate system logs we care about
    local system_logs=(
        "/var/log/syslog"
        "/var/log/auth.log"
        "/var/log/fail2ban.log"
        "/var/log/nginx/access.log"
        "/var/log/nginx/error.log"
    )

    for logfile in "${logs[@]}" "${system_logs[@]}"; do
        if [[ -f "${logfile}" ]]; then
            rotate_log "${logfile}" "${keep}" "${dry_run}"
        fi
    done
}

# ── Rotate a custom log (user-specified) ──────────────────────────────────────
rotate_custom_log() {
    local logfile="$1"
    local keep="${2:-5}"
    local dry_run="${3:-0}"

    log_section "Custom Log Rotation"
    rotate_log "${logfile}" "${keep}" "${dry_run}"
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
    local logfile=""
    local do_all=0
    local keep=5
    local dry_run=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)      usage; exit 0 ;;
            -f|--file)      logfile="$2"; shift 2 ;;
            --all)          do_all=1; shift ;;
            -n|--keep)      keep="$2"; shift 2 ;;
            --dry-run)      dry_run=1; shift ;;
            *)              log_error "Unknown option: $1"; usage; exit 1 ;;
        esac
    done

    require_non_root
    ensure_dirs

    if [[ "${do_all}" -eq 1 ]]; then
        rotate_capstone_logs "${keep}" "${dry_run}"
    elif [[ -n "${logfile}" ]]; then
        rotate_custom_log "${logfile}" "${keep}" "${dry_run}"
    else
        log_error "Specify --all or --file LOG"
        usage
        exit 1
    fi

    log_info "Log rotation complete"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Log rotation completed (keep=${keep})" >> "${LOG_DIR}/logrotate.log"
}

main "$@"
