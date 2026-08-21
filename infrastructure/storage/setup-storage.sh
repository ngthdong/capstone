#!/usr/bin/env bash
# Thiết lập và Mount phân vùng lưu trữ Backup bền vững qua /etc/fstab

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

trap 'echo -e "${RED}[ERROR]${NC} Lỗi xảy ra tại dòng $LINENO khi thiết lập lưu trữ." >&2' ERR

# Kiểm tra quyền root 
if [[ "${EUID}" -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Script yêu cầu quyền root: sudo bash $0" >&2
    exit 1
fi

# 1. Định nghĩa thư mục đích lưu trữ backup và file image block storage
readonly MOUNT_POINT="/var/backups/capstone"
readonly STORAGE_IMG="/var/lib/capstone-storage.img"
readonly STORAGE_SIZE_MB=5120  # 5 GB

echo -e "${BLUE} THIẾT LẬP PHÂN VÙNG LƯU TRỮ BỀN VỮNG (/ETC/FSTAB) ${NC}\n"

# 2. Tạo thư mục mount point  
echo -e "${YELLOW}[1/5]${NC} Khởi tạo thư mục mount point: ${MOUNT_POINT}..."
mkdir -p "${MOUNT_POINT}"

# 3. Kiểm tra xem thư mục đã được mount từ trước chưa           
if mountpoint -q "${MOUNT_POINT}"; then
    echo -e "${GREEN}[INFO]${NC} Thư mục ${MOUNT_POINT} đã được mount từ trước. Bỏ qua bước tạo mới."
    df -hT "${MOUNT_POINT}"
    exit 0
fi

# 4. Tạo block storage container và format Ext4              
if [[ ! -f "${STORAGE_IMG}" ]]; then
    echo -e "${YELLOW}[2/5]${NC} Đang tạo Sparse Block Storage Image (${STORAGE_SIZE_MB}MB)..."
    # Dùng truncate để tạo sparse file dung lượng 5GB (không tốn dung lượng ảo)
    truncate -s "${STORAGE_SIZE_MB}M" "${STORAGE_IMG}"
    chmod 600 "${STORAGE_IMG}"

    echo -e "${YELLOW}[3/5]${NC} Format hệ thống tập tin chuẩn Ext4 với label 'CAPSTONE_BAK'..."
    mkfs.ext4 -F -L "CAPSTONE_BAK" "${STORAGE_IMG}" >/dev/null
else
    echo -e "${YELLOW}[INFO]${NC} File lưu trữ ${STORAGE_IMG} đã tồn tại."
fi

# 5. Cập nhật /etc/fstab (Đảm bảo tồn tại sau khi Reboot)         
echo -e "${YELLOW}[4/5]${NC} Đang cấu hình tự động mount vào /etc/fstab..."

# Kiểm tra xem cấu hình đã có trong /etc/fstab chưa để tránh ghi trùng lặp
if ! grep -qs "${STORAGE_IMG}" /etc/fstab; then
    # Thêm entry mount loopback device với các cờ tối ưu:
    # - loop: gắn kết file image dưới dạng block device
    # - defaults: các quyền cơ bản (rw, suid, dev, exec, auto, nouser, async)
    # - noatime: giúp tăng tốc I/O (không ghi thời gian truy cập file khi đọc)
    # - nofail: ngăn chặn treo máy khi boot nếu file storage có sự cố
    echo "${STORAGE_IMG} ${MOUNT_POINT} ext4 loop,defaults,noatime,nofail 0 0" >> /etc/fstab
    echo -e "  ${GREEN}✓${NC} Đã nạp entry vào /etc/fstab thành công."
else
    echo -e "  ${GREEN}✓${NC} Entry đã tồn tại trong /etc/fstab."
fi

# 6. Nạp cấu hình và kiểm tra an toàn với mount -a (quan trọng để tránh lỗi boot)    
echo -e "${YELLOW}[5/5]${NC} Thực thi 'mount -a' để kiểm tra tính toàn vẹn của /etc/fstab..."
mount -a

# 7. Phân quyền bảo mật cho thư mục backup (chỉ root và nhóm sudo có quyền đọc/ghi)
chmod 770 "${MOUNT_POINT}"

echo -e "\n${GREEN}[SUCCESS]${NC} Phân vùng lưu trữ đã được mount thành công và sẵn sàng sau khi reboot!\n"
df -hT "${MOUNT_POINT}"
echo