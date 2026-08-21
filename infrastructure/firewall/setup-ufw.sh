#!/usr/bin/env bash
# Cấu hình tường lửa UFW (Uncomplicated Firewall) theo chuẩn Security Baseline

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

trap 'echo -e "${RED}[ERROR]${NC} Lỗi tại dòng $LINENO khi cấu hình UFW." >&2' ERR

# Kiểm tra quyền root
if [[ "${EUID}" -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Script yêu cầu quyền root: sudo bash $0" >&2
    exit 1
fi

echo -e "${BLUE} KHỞI TẠO VÀ CẤU HÌNH TƯỜNG LỬA UFW BASELINE ${NC}\n"

# 2. Đảm bảo gói UFW đã được cài đặt                                        
if ! command -v ufw &>/dev/null; then
    echo -e "${YELLOW}[INFO]${NC} Đang cài đặt ufw..."
    apt-get update -qq && apt-get install -y -qq ufw
fi

# 3. Reset toàn bộ rules cũ về mặc định (Đảm bảo tính Idempotent)          
echo -e "${YELLOW}[1/5]${NC} Đang đặt lại trạng thái ban đầu của UFW..."
ufw --force reset >/dev/null

# 4. Thiết lập chính sách mặc định (Default Policies)                        
# Default-Deny Inbound: Chặn toàn bộ kết nối từ ngoài vào trừ khi có rule mở
echo -e "${YELLOW}[2/5]${NC} Thiết lập chính sách: Default-Deny Inbound & Default-Allow Outbound..."
ufw default deny incoming >/dev/null

# Default-Allow Outbound: Cho phép server gửi gói tin ra ngoài (update, DNS, mail, rsync)
ufw default allow outgoing >/dev/null

# 5. Mở các cổng dịch vụ thiết yếu (Least Privilege)                        
echo -e "${YELLOW}[3/5]${NC} Cấu hình các cổng dịch vụ được phép..."

# Port 22/tcp: SSH Quản trị & Đồng bộ Backup rsync giữa 2 VM
# Dùng 'limit' thay vì 'allow' để tự động chặn IP kết nối quá 6 lần trong 30 giây
ufw limit 22/tcp comment 'SSH Remote Management with rate-limiting'
echo -e "  ${GREEN}✓${NC} Đã mở và rate-limit cổng 22/tcp (SSH)"

# Port 80/tcp: HTTP Web Traffic (dùng để phục vụ web hoặc 301 redirect sang HTTPS)
ufw allow 80/tcp comment 'Nginx HTTP Web Server'
echo -e "  ${GREEN}✓${NC} Đã mở cổng 80/tcp (HTTP)"

# Port 443/tcp: HTTPS Secure Web Traffic (Tiêu chí +1 điểm Bonus TLS)
ufw allow 443/tcp comment 'Nginx HTTPS Web Server'
echo -e "  ${GREEN}✓${NC} Đã mở cổng 443/tcp (HTTPS)"

# 6. Bật tính năng ghi log của UFW để phục vụ điều tra an ninh              
echo -e "${YELLOW}[4/5]${NC} Kích hoạt ghi log UFW (mức medium)..."
ufw logging medium >/dev/null

# 7. Kích hoạt và kiểm tra trạng thái tường lửa                             
echo -e "${YELLOW}[5/5]${NC} Kích hoạt UFW..."
ufw --force enable >/dev/null

echo -e "\n${GREEN}[SUCCESS]${NC} Tường lửa UFW đã được cấu hình và kích hoạt thành công!\n"
ufw status verbose
echo