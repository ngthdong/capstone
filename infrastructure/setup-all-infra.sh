#!/usr/bin/env bash
# Master Script tự động hóa triển khai toàn bộ hạ tầng Module 1 (Infrastructure & Security)

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

trap 'echo -e "${RED}[ERROR]${NC} Lỗi tại dòng $LINENO trong quá trình thiết lập hạ tầng." >&2' ERR

# Kiểm tra quyền root
if [[ "${EUID}" -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Script yêu cầu quyền root: sudo bash $0" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly HOSTNAME="${1:-capstone-srv01}"

echo -e "${BLUE} TRIỂN KHAI TOÀN BỘ HẠ TẦNG MODULE 1 (INFRASTRUCTURE & SECURITY) ${NC}\n"

# 1. Đặt Hostname có ý nghĩa theo yêu cầu H3.1 Baseline
echo -e "${YELLOW}[1/7]${NC} Cấu hình Hostname: ${HOSTNAME}..."
hostnamectl set-hostname "${HOSTNAME}"
if ! grep -qs "${HOSTNAME}" /etc/hosts; then
    echo "127.0.1.1 ${HOSTNAME}" >> /etc/hosts
fi

# 2. Cài đặt các gói dịch vụ thiết yếu của hệ thống
echo -e "${YELLOW}[2/7]${NC} Cài đặt các package cần thiết (ufw, fail2ban, auditd, openssl, rsync)..."
apt-get update -qq && apt-get install -y -qq ufw fail2ban auditd openssl rsync lynis

# 3. Nạp cấu hình SSH Hardening (§3.2)
echo -e "${YELLOW}[3/7]${NC} Triển khai cấu hình SSH Hardening..."
mkdir -p /etc/ssh/sshd_config.d
cp "${SCRIPT_DIR}/ssh/sshd_config.d/99-capstone.conf" /etc/ssh/sshd_config.d/
chmod 644 /etc/ssh/sshd_config.d/99-capstone.conf
systemctl restart ssh

# 4. Thiết lập phân vùng lưu trữ bền vững qua /etc/fstab (H3.1)
echo -e "${YELLOW}[4/7]${NC} Thiết lập phân vùng lưu trữ bền vững..."
bash "${SCRIPT_DIR}/storage/setup-storage.sh"

# 5. Sinh chứng chỉ TLS Self-Signed (+1 Điểm Bonus H7)
echo -e "${YELLOW}[5/7]${NC} Khởi tạo chứng chỉ SSL/TLS Self-Signed..."
bash "${SCRIPT_DIR}/tls/generate-cert.sh"

# 6. Cấu hình Fail2ban và Auditd Kernel Rules (H3.2)
echo -e "${YELLOW}[6/7]${NC} Cấu hình Fail2ban và Auditd Rules..."
mkdir -p /etc/fail2ban/jail.d /etc/audit/rules.d
cp "${SCRIPT_DIR}/fail2ban/jail.d/sshd-capstone.local" /etc/fail2ban/jail.d/
chmod 644 /etc/fail2ban/jail.d/sshd-capstone.local
systemctl restart fail2ban

cp "${SCRIPT_DIR}/audit/rules.d/99-capstone-audit.rules" /etc/audit/rules.d/
chmod 640 /etc/audit/rules.d/99-capstone-audit.rules
augenrules --load >/dev/null

# 7. Kích hoạt tường lửa UFW (Luôn chạy cuối cùng để đảm bảo an toàn kết nối)
echo -e "${YELLOW}[7/7]${NC} Kích hoạt tường lửa UFW..."
bash "${SCRIPT_DIR}/firewall/setup-ufw.sh"

echo -e "\n${GREEN}[SUCCESS]${NC} Toàn bộ hạ tầng và bảo mật Module 1 đã được thiết lập hoàn tất!\n"