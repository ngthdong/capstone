#!/usr/bin/env bash
# Sinh chứng chỉ số SSL/TLS tự ký (Self-Signed) cho Web Server Nginx 

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

trap 'echo -e "${RED}[ERROR]${NC} Lỗi tại dòng $LINENO khi sinh chứng chỉ TLS." >&2' ERR

# Kiểm tra quyền root
if [[ "${EUID}" -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Script yêu cầu quyền root: sudo bash $0" >&2
    exit 1
fi

# Đường dẫn lưu trữ chứng chỉ chuẩn trên Ubuntu
readonly CERT_DIR="/etc/ssl/certs"
readonly KEY_DIR="/etc/ssl/private"
readonly CERT_FILE="${CERT_DIR}/capstone-selfsigned.crt"
readonly KEY_FILE="${KEY_DIR}/capstone-selfsigned.key"
readonly DAYS_VALID=365

echo -e "${BLUE} KHỞI TẠO CHỨNG CHỈ SSL/TLS SELF-SIGNED CHO NGINX ${NC}\n"

# 1. Đảm bảo thư mục lưu trữ tồn tại
mkdir -p "${CERT_DIR}" "${KEY_DIR}"

# 2. Sinh Private Key và Certificate với OpenSSL (kèm SAN cho 2 Virtual Hosts)
echo -e "${YELLOW}[1/3]${NC} Đang sinh RSA 2048-bit Private Key và X.509 Certificate (hạn ${DAYS_VALID} ngày)..."

openssl req -x509 -nodes -days "${DAYS_VALID}" -newkey rsa:2048 \
    -keyout "${KEY_FILE}" \
    -out "${CERT_FILE}" \
    -subj "/C=VN/ST=HCMC/O=HCMUS-FIT/OU=Capstone-Linux/CN=capstone.local" \
    -addext "subjectAltName=DNS:app.local,DNS:status.local,DNS:capstone.local,DNS:localhost,IP:127.0.0.1" \
    >/dev/null 2>&1

# 3. Phân quyền bảo mật nghiêm ngặt cho Private Key (chỉ root đọc được)
echo -e "${YELLOW}[2/3]${NC} Thiết lập phân quyền an toàn cho Private Key và Certificate..."
chmod 600 "${KEY_FILE}"
chmod 644 "${CERT_FILE}"

# 4. Kiểm tra tính toàn vẹn của chứng chỉ vừa tạo
echo -e "${YELLOW}[3/3]${NC} Kiểm tra thông tin chứng chỉ...\n"
echo -e "${GREEN}[SUCCESS]${NC} Chứng chỉ TLS đã được sinh thành công!"
echo -e "  ${GREEN}✓${NC} Certificate: ${CERT_FILE}"
echo -e "  ${GREEN}✓${NC} Private Key: ${KEY_FILE}"
echo -e "  ${GREEN}✓${NC} Hiệu lực:    ${DAYS_VALID} ngày"
echo -e "  ${GREEN}✓${NC} Fingerprint: $(openssl x509 -noout -fingerprint -sha256 -in "${CERT_FILE}" | cut -d= -f2)\n"