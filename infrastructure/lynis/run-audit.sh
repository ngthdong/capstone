#!/usr/bin/env bash
# Chạy kiểm toán an ninh hệ thống tự động với Lynis và trích xuất Hardening Index

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

trap 'echo -e "${RED}[ERROR]${NC} Lỗi tại dòng $LINENO khi chạy Lynis audit." >&2' ERR

# Kiểm tra quyền root
if [[ "${EUID}" -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Script yêu cầu quyền root: sudo bash $0" >&2
    exit 1
fi

readonly REPORT_DIR="/var/log/lynis"
readonly REPORT_FILE="${REPORT_DIR}/lynis-report.dat"
readonly LOG_FILE="${REPORT_DIR}/lynis.log"

echo -e "${BLUE} KIỂM TOÁN AN NINH HỆ THỐNG VỚI LYNIS ${NC}\n"

# 1. Đảm bảo công cụ Lynis đã được cài đặt
if ! command -v lynis &>/dev/null; then
    echo -e "${YELLOW}[1/3]${NC} Đang cài đặt công cụ Lynis..."
    apt-get update -qq && apt-get install -y -qq lynis
else
    echo -e "${YELLOW}[1/3]${NC} Công cụ Lynis đã sẵn sàng."
fi

mkdir -p "${REPORT_DIR}"

# 2. Thực thi quy trình quét hệ thống toàn diện ở chế độ non-interactive
echo -e "${YELLOW}[2/3]${NC} Đang thực thi kiểm toán an ninh (quá trình mất khoảng 30–60 giây)..."
lynis audit system --quick --no-colors \
    --report-file "${REPORT_FILE}" \
    --log-file "${LOG_FILE}" >/dev/null 2>&1

# 3. Trích xuất chỉ số Hardening Index và các cảnh báo
echo -e "${YELLOW}[3/3]${NC} Trích xuất kết quả đánh giá an ninh...\n"

HARDENING_INDEX=$(grep -E '^hardening_index=' "${REPORT_FILE}" | cut -d= -f2 || echo "N/A")
readonly HARDENING_INDEX
WARNINGS_COUNT=$(grep -c -E '^warning\[\]=' "${REPORT_FILE}" || echo "0")
readonly WARNINGS_COUNT
SUGGESTIONS_COUNT=$(grep -c -E '^suggestion\[\]=' "${REPORT_FILE}" || echo "0")
readonly SUGGESTIONS_COUNT

echo -e "${GREEN}[SUCCESS]${NC} Quá trình kiểm toán an ninh đã hoàn tất!"
echo -e "  ${GREEN}✓${NC} Hardening Index Score: ${BLUE}${HARDENING_INDEX}/100${NC}"
echo -e "  ${GREEN}✓${NC} Số cảnh báo (Warnings):   ${YELLOW}${WARNINGS_COUNT}${NC}"
echo -e "  ${GREEN}✓${NC} Số khuyến nghị (Suggestions): ${YELLOW}${SUGGESTIONS_COUNT}${NC}"
echo -e "  ${GREEN}✓${NC} File báo cáo chi tiết:     ${REPORT_FILE}\n"