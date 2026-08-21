# Infrastructure & Security Module

Thư mục này chứa toàn bộ script và file cấu hình cho phần Hạ tầng và Bảo mật của đồ án Capstone Linux.

## Cấu trúc thư mục

```text
infrastructure/
├── ssh/
│   └── sshd_config.d/
│       └── 99-capstone.conf        # Cấu hình SSH hardening (tắt root, ép key, allow users)
├── firewall/
│   └── setup-ufw.sh                # Cấu hình tường lửa UFW (mở 22, 80, 443)
├── fail2ban/
│   └── jail.d/
│       └── sshd-capstone.local     # Cấu hình jail fail2ban cho SSH
├── audit/
│   └── rules.d/
│       └── 99-capstone-audit.rules # Rule auditd theo dõi /etc/passwd và /etc/shadow
├── storage/
│   └── setup-storage.sh            # Tạo và mount ổ đĩa lưu trữ backup qua /etc/fstab
├── tls/
│   └── generate-cert.sh            # Tạo chứng chỉ self-signed SSL/TLS cho Nginx
├── lynis/
│   └── run-audit.sh                # Script chạy kiểm tra bảo mật bằng Lynis
├── provision-vmware.ps1            # Script tự động tạo 2 máy ảo VMware
├── setup-all-infra.sh              # Script chạy toàn bộ cài đặt trên máy mới
└── README.md
```

## Hướng dẫn cài đặt

### Cách 1: Chạy tự động toàn bộ (Khuyên dùng)

```bash
sudo bash setup-all-infra.sh capstone-srv01
```

### Cách 2: Chạy từng phần thủ công

1. **Cấu hình SSH:**
   ```bash
   sudo cp ssh/sshd_config.d/99-capstone.conf /etc/ssh/sshd_config.d/
   sudo systemctl restart ssh
   ```

2. **Cấu hình UFW Firewall:**
   ```bash
   sudo bash firewall/setup-ufw.sh
   ```

3. **Cấu hình Fail2ban:**
   ```bash
   sudo cp fail2ban/jail.d/sshd-capstone.local /etc/fail2ban/jail.d/
   sudo systemctl restart fail2ban
   ```

4. **Cấu hình Auditd:**
   ```bash
   sudo cp audit/rules.d/99-capstone-audit.rules /etc/audit/rules.d/
   sudo augenrules --load
   ```

5. **Tạo phân vùng lưu trữ backup:**
   ```bash
   sudo bash storage/setup-storage.sh
   ```

6. **Tạo chứng chỉ SSL:**
   ```bash
   sudo bash tls/generate-cert.sh
   ```

7. **Chạy kiểm toán bảo mật với Lynis:**
   ```bash
   sudo bash lynis/run-audit.sh
   ```

## Kiểm tra sau khi cài đặt

```bash
# Kiểm tra firewall
sudo ufw status verbose

# Kiểm tra fail2ban
sudo fail2ban-client status sshd

# Kiểm tra auditd
sudo auditctl -l

# Kiểm tra phân vùng mount
df -hT /var/backups/capstone

# Kiểm tra chứng chỉ SSL
openssl x509 -in /etc/ssl/certs/capstone-selfsigned.crt -text -noout | grep -E 'Issuer:|Subject:|DNS:'
```
