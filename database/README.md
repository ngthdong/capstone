# Setup Database & Backup

## 1. Cài PostgreSQL
```bash
sudo apt install postgresql postgresql-contrib -y
sudo systemctl enable --now postgresql
```
# 2. Tạo database + role least-privilege
```bash
sudo -u postgres psql
sql
CREATE DATABASE tododb;
CREATE USER appuser WITH PASSWORD '<DB_PASSWORD>';
\c tododb
GRANT CONNECT ON DATABASE tododb TO appuser;
GRANT USAGE, CREATE ON SCHEMA public TO appuser;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO appuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO appuser;
```
appuser không phải superuser, không được CREATE DATABASE/DROP DATABASE — đây chính là "least privilege" mà rubric yêu cầu, ghi rõ trong report.

## 3. Schema mẫu

schema.sql:

```sql
CREATE TABLE IF NOT EXISTS todos (
                    id SERIAL PRIMARY KEY,
                    title TEXT NOT NULL,
                    done BOOLEAN NOT NULL DEFAULT FALSE,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
                );

```
```bash
sudo -u postgres psql -d tododb -f schema.sql
```
Gửi ngay file schema.sql này cho Đông — đây là bước hay bị trễ nhất trong nhóm vì Đông không code được nếu chưa có bảng.

## 4. Chỉ nghe localhost

Sửa /etc/postgresql/*/main/postgresql.conf:
```
listen_addresses = 'localhost'
```
Sửa /etc/postgresql/*/main/pg_hba.conf — đảm bảo chỉ có dòng cho phép kết nối local:
```
local   all             all                                     peer
host    all             all             127.0.0.1/32            scram-sha-256
```
```bash
sudo systemctl restart postgresql
```
Chứng minh cho demo/report:

```bash
ss -tlnp | grep 5432
# phải chỉ thấy 127.0.0.1:5432, KHÔNG có 0.0.0.0:5432
```
## 5. Test thủ công dump/restore (làm TRƯỚC khi Huy viết script tự động)
```bash
# Dump
pg_dump -U appuser -h 127.0.0.1 -d tododb -F c -f /tmp/tododb_test.dump

# Giả lập mất data
sudo -u postgres psql -d tododb -c "DELETE FROM todos;"

# Restore
pg_restore -U appuser -h 127.0.0.1 -d tododb --clean --if-exists /tmp/tododb_test.dump

# Kiểm tra data đã về
sudo -u postgres psql -d tododb -c "SELECT count(*) FROM todos;"
```
Chạy được quy trình này thủ công trước rồi mới đưa 3 câu lệnh (dump/xoá-giả-lập/restore) này cho Huy đóng gói vào backup.sh/restore.sh — tránh việc Huy phải tự đoán cú pháp pg_dump đúng của nhóm.

## 6. Chuẩn bị VM2 (phối hợp với Dũng)
```bash
# Trên VM2
sudo mkdir -p /data/backup-received
sudo chown opsadmin:opsadmin /data/backup-received
```
Đảm bảo VM1 SSH vào VM2 bằng key (không password) — test:

```bash

# Trên VM1
ssh-copy-id opsadmin@192.168.56.11     # IP VM2, xin Dũng nếu chưa có
ssh opsadmin@192.168.56.11 "echo ok"
```
