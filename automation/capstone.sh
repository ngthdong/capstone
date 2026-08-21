#!/usr/bin/env bash
# capstone.sh — Interactive CLI menu and entry point for the capstone toolkit.
# Dispatches to each tool and handles invalid input gracefully.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

# ── Usage ──────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTION]

Capstone Operations & Automation Toolkit — interactive menu-driven CLI.

Options:
  -h, --help       Show this help message and exit
  -d, --deploy     Run deploy directly (non-interactive)
  -b, --backup     Run backup directly (non-interactive)
  -r, --restore    Run restore directly (non-interactive)
  -c, --check      Run health-check directly (non-interactive)
  -l, --logrotate  Run log-rotation directly (non-interactive)

Without options, an interactive menu is displayed.
EOF
}

# ── Banner ─────────────────────────────────────────────────────────────────────
show_banner() {
    clear
    printf '%b' "${BOLD}${BLUE}"
    cat <<'BANNER'
  ╔══════════════════════════════════════════════════════╗
  ║       Linux Capstone — Operations & Automation       ║
  ║                    Toolkit v1.0                      ║
  ╚══════════════════════════════════════════════════════╝
BANNER
    printf '%b\n' "${NC}"
}

# ── Menu ───────────────────────────────────────────────────────────────────────
show_menu() {
    printf '%b\n' "${BOLD}Main Menu${NC}"
    printf '%s\n' "────────────────────────────────────"
    printf '%b\n' "  ${GREEN}1${NC}) Deploy application & web content"
    printf '%b\n' "  ${GREEN}2${NC}) Backup database & web content"
    printf '%b\n' "  ${GREEN}3${NC}) Restore from backup"
    printf '%b\n' "  ${GREEN}4${NC}) Health-check (CPU / disk / RAM / services)"
    printf '%b\n' "  ${GREEN}5${NC}) Log rotation"
    printf '%b\n' "  ${GREEN}6${NC}) Show toolkit status"
    printf '%b\n' "  ${RED}0${NC}) Exit"
    printf '%s\n' "────────────────────────────────────"
}

dispatch() {
    local choice="$1"
    case "${choice}" in
        1) bash "${SCRIPT_DIR}/deploy.sh" ;;
        2) bash "${SCRIPT_DIR}/backup.sh" ;;
        3) bash "${SCRIPT_DIR}/restore.sh" ;;
        4) bash "${SCRIPT_DIR}/health-check.sh" ;;
        5) bash "${SCRIPT_DIR}/log-rotate.sh" ;;
        6) show_status ;;
        0) log_info "Goodbye!"; exit 0 ;;
        *) log_error "Invalid option. Please try again." ;;
    esac
}

show_status() {
    log_section "Toolkit Status"
    printf "  %-20s %s\n" "Toolkit dir:"  "${TOOLKIT_DIR}"
    printf "  %-20s %s\n" "Log dir:"      "${LOG_DIR}"
    printf "  %-20s %s\n" "Backup dir:"   "${BACKUP_DIR}"
    printf "  %-20s %s\n" "DB type:"      "${DB_TYPE}"
    printf "  %-20s %s\n" "App service:"  "${APP_SERVICE}"
    printf "  %-20s %s\n" "Web server:"   "${WEB_SERVER}"
    printf "  %-20s %s\n" "Alert channel:" "${ALERT_CHANNEL}"
    printf "  %-20s %s\n" "Retention:"    "${RETENTION_DAYS} days"

    if systemctl is-active --quiet "${WEB_SERVER}" 2>/dev/null; then
        printf "  %-20s %b\n" "Web server:" "${GREEN}running${NC}"
    else
        printf "  %-20s %b\n" "Web server:" "${RED}stopped${NC}"
    fi

    if systemctl is-active --quiet "${APP_SERVICE}" 2>/dev/null; then
        printf "  %-20s %b\n" "App service:" "${GREEN}running${NC}"
    else
        printf "  %-20s %b\n" "App service:" "${RED}stopped${NC}"
    fi

    if [[ -d "${BACKUP_DIR}" ]]; then
        local count
        count="$(find "${BACKUP_DIR}" -maxdepth 1 -name '*.tar.gz' 2>/dev/null | wc -l)"
        printf "  %-20s %s\n" "Backups found:" "${count}"
    fi
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
    ensure_dirs

    if [[ $# -gt 0 ]]; then
        case "$1" in
            -h|--help)    usage; exit 0 ;;
            -d|--deploy)  dispatch 1 ;;
            -b|--backup)  dispatch 2 ;;
            -r|--restore) dispatch 3 ;;
            -c|--check)   dispatch 4 ;;
            -l|--logrotate) dispatch 5 ;;
            *) log_error "Unknown option: $1"; usage; exit 1 ;;
        esac
        return
    fi

    # Interactive loop
    while true; do
        show_banner
        show_menu
        read -r -p "  Select an option: " choice
        echo
        dispatch "${choice}"
        echo
        read -r -p "  Press Enter to continue..." _
    done
}

main "$@"
