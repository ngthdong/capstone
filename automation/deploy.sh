#!/usr/bin/env bash
# deploy.sh — Deploy application and web content safely.
# Test → reload → confirm → rollback on failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

# ── Usage ──────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTION]

Deploy the capstone application and web content.

Options:
  -h, --help        Show this help message
  -s, --src DIR     Source directory containing the app (default: ./app)
  -w, --web DIR     Source directory for web content  (default: ./web)
      --dry-run     Show what would be done without making changes
      --rollback    Roll back to the last known-good state
EOF
}

# ── Trap / cleanup ─────────────────────────────────────────────────────────────
ROLLBACK_NEEDED=0

cleanup() {
    local exit_code=$?
    if [[ "${ROLLBACK_NEEDED}" -eq 1 && ${exit_code} -ne 0 ]]; then
        log_warn "Deploy failed (exit ${exit_code}). Initiating rollback..."
        do_rollback
    fi
}
trap cleanup EXIT

# ── Backup current state before deploying ──────────────────────────────────────
snapshot_current() {
    local snapshot_dir
    snapshot_dir="${BACKUP_DIR}/pre-deploy-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "${snapshot_dir}"

    if [[ -d "${WEB_CONTENT}" ]]; then
        cp -a "${WEB_CONTENT}" "${snapshot_dir}/web-content" 2>/dev/null || true
        log_info "Web content snapshotted to ${snapshot_dir}/web-content"
    fi

    if [[ -d "/etc/nginx" ]]; then
        cp -a /etc/nginx "${snapshot_dir}/nginx-conf" 2>/dev/null || true
        log_info "Nginx config snapshotted to ${snapshot_dir}/nginx-conf"
    elif [[ -d "/etc/httpd" ]]; then
        cp -a /etc/httpd "${snapshot_dir}/httpd-conf" 2>/dev/null || true
        log_info "Apache config snapshotted to ${snapshot_dir}/httpd-conf"
    fi

    # Store snapshot path for rollback
    echo "${snapshot_dir}" > "${BACKUP_DIR}/.last-pre-deploy"
    log_info "Pre-deploy snapshot saved: ${snapshot_dir}"
}

# ── Rollback ───────────────────────────────────────────────────────────────────
do_rollback() {
    if [[ ! -f "${BACKUP_DIR}/.last-pre-deploy" ]]; then
        log_error "No pre-deploy snapshot found. Cannot rollback automatically."
        return 1
    fi

    local snapshot_dir
    snapshot_dir="$(cat "${BACKUP_DIR}/.last-pre-deploy")"

    if [[ ! -d "${snapshot_dir}" ]]; then
        log_error "Snapshot directory not found: ${snapshot_dir}"
        return 1
    fi

    log_warn "Rolling back from ${snapshot_dir}..."

    if [[ -d "${snapshot_dir}/web-content" ]]; then
        rm -rf "${WEB_CONTENT}"
        cp -a "${snapshot_dir}/web-content" "${WEB_CONTENT}"
        log_info "Web content restored"
    fi

    if [[ -d "${snapshot_dir}/nginx-conf" ]]; then
        rm -rf /etc/nginx
        cp -a "${snapshot_dir}/nginx-conf" /etc/nginx
        systemctl reload nginx 2>/dev/null || true
        log_info "Nginx config restored and reloaded"
    elif [[ -d "${snapshot_dir}/httpd-conf" ]]; then
        rm -rf /etc/httpd
        cp -a "${snapshot_dir}/httpd-conf" /etc/httpd
        systemctl reload httpd 2>/dev/null || true
        log_info "Apache config restored and reloaded"
    fi

    log_info "Rollback complete"
}

# ── Deploy ─────────────────────────────────────────────────────────────────────
do_deploy() {
    local src_dir="${1:-./app}"
    local web_dir="${2:-./web}"
    local dry_run="${3:-0}"

    log_section "Deploy"

    if [[ "${dry_run}" -eq 1 ]]; then
        log_info "DRY RUN — no changes will be made"
    fi

    # 1. Snapshot current state
    if [[ "${dry_run}" -eq 0 ]]; then
        snapshot_current
        ROLLBACK_NEEDED=1
    fi

    # 2. Deploy web content
    if [[ -d "${web_dir}" ]]; then
        log_info "Deploying web content from ${web_dir}..."
        if [[ "${dry_run}" -eq 0 ]]; then
            mkdir -p "${WEB_CONTENT}"
            rsync -a --delete "${web_dir}/" "${WEB_CONTENT}/"
            chown -R www-data:www-data "${WEB_CONTENT}" 2>/dev/null || \
                chown -R nginx:nginx "${WEB_CONTENT}" 2>/dev/null || true
            chmod -R 755 "${WEB_CONTENT}"
            log_info "Web content deployed to ${WEB_CONTENT}"
        else
            log_info "[dry-run] Would sync ${web_dir} → ${WEB_CONTENT}"
        fi
    else
        log_warn "Web source directory not found: ${web_dir} (skipping)"
    fi

    # 3. Deploy application
    if [[ -d "${src_dir}" ]]; then
        log_info "Deploying application from ${src_dir}..."
        if [[ "${dry_run}" -eq 0 ]]; then
            local app_dir="/opt/capstone-app"
            mkdir -p "${app_dir}"
            rsync -a --delete "${src_dir}/" "${app_dir}/"

            # Set ownership for the app user (if exists)
            if id -u capstone &>/dev/null; then
                chown -R capstone:capstone "${app_dir}"
            fi

            log_info "Application deployed to ${app_dir}"
        else
            log_info "[dry-run] Would sync ${src_dir} → /opt/capstone-app"
        fi
    else
        log_warn "App source directory not found: ${src_dir} (skipping)"
    fi

    # 4. Test web server config
    log_info "Testing web server configuration..."
    if [[ "${dry_run}" -eq 0 ]]; then
        if [[ "${WEB_SERVER}" == "nginx" ]]; then
            if ! nginx -t 2>&1; then
                log_error "Nginx config test FAILED"
                log_warn "Rolling back..."
                do_rollback
                exit 1
            fi
            log_info "Nginx config test passed"
        elif [[ "${WEB_SERVER}" == "httpd" || "${WEB_SERVER}" == "apache2" ]]; then
            if ! apachectl configtest 2>&1; then
                log_error "Apache config test FAILED"
                log_warn "Rolling back..."
                do_rollback
                exit 1
            fi
            log_info "Apache config test passed"
        fi
    else
        log_info "[dry-run] Would test ${WEB_SERVER} config"
    fi

    # 5. Reload web server
    if [[ "${dry_run}" -eq 0 ]]; then
        log_info "Reloading ${WEB_SERVER}..."
        if ! systemctl reload "${WEB_SERVER}" 2>&1; then
            log_error "${WEB_SERVER} reload FAILED"
            log_warn "Rolling back..."
            do_rollback
            exit 1
        fi
        log_info "${WEB_SERVER} reloaded successfully"
    else
        log_info "[dry-run] Would reload ${WEB_SERVER}"
    fi

    # 6. Restart application service
    if [[ "${dry_run}" -eq 0 ]]; then
        log_info "Restarting application service..."
        if systemctl list-unit-files | grep -q "${APP_SERVICE}"; then
            if ! systemctl restart "${APP_SERVICE}" 2>&1; then
                log_error "Application service restart FAILED"
                log_warn "Rolling back..."
                do_rollback
                exit 1
            fi
            log_info "Application service restarted"
        else
            log_warn "Service ${APP_SERVICE} not found (skipping restart)"
        fi
    fi

    # 7. Confirm: check that services are running
    if [[ "${dry_run}" -eq 0 ]]; then
        log_info "Confirming services are up..."
        sleep 2

        local all_ok=1
        if ! systemctl is-active --quiet "${WEB_SERVER}" 2>/dev/null; then
            log_error "${WEB_SERVER} is NOT running after deploy!"
            all_ok=0
        fi

        if systemctl list-unit-files | grep -q "${APP_SERVICE}"; then
            if ! systemctl is-active --quiet "${APP_SERVICE}" 2>/dev/null; then
                log_error "${APP_SERVICE} is NOT running after deploy!"
                all_ok=0
            fi
        fi

        if [[ "${all_ok}" -eq 0 ]]; then
            log_error "Post-deploy health check FAILED. Rolling back..."
            do_rollback
            exit 1
        fi

        ROLLBACK_NEEDED=0
        log_info "Deploy completed successfully — all services confirmed running"
    fi

    # Log deploy event
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Deploy completed (src=${src_dir}, web=${web_dir})" >> "${DEPLOY_LOG}"
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
    local src_dir="./app"
    local web_dir="./web"
    local dry_run=0
    local rollback=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)      usage; exit 0 ;;
            -s|--src)       src_dir="$2"; shift 2 ;;
            -w|--web)       web_dir="$2"; shift 2 ;;
            --dry-run)      dry_run=1; shift ;;
            --rollback)     rollback=1; shift ;;
            *)              log_error "Unknown option: $1"; usage; exit 1 ;;
        esac
    done

    require_non_root

    if [[ "${rollback}" -eq 1 ]]; then
        do_rollback
        return
    fi

    do_deploy "${src_dir}" "${web_dir}" "${dry_run}"
}

main "$@"
