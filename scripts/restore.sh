#!/usr/bin/env bash
###############################################################################
# Khôi phục JENKINS_HOME từ file backup .tar.gz
# Dùng: bash scripts/restore.sh backups/jenkins-home-YYYYmmdd-HHMMSS.tar.gz
# CẢNH BÁO: ghi đè dữ liệu hiện tại trong volume jenkins_home.
###############################################################################
set -euo pipefail

VOLUME="jenkins_home"
FILE="${1:-}"

if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "!! Vui lòng truyền đường dẫn file backup hợp lệ."
  echo "   Ví dụ: bash scripts/restore.sh backups/jenkins-home-20260709-120000.tar.gz"
  exit 1
fi

read -rp ">> Sẽ GHI ĐÈ volume '${VOLUME}'. Tiếp tục? (yes/no) " ans
[[ "$ans" == "yes" ]] || { echo "Đã huỷ."; exit 0; }

echo ">> Dừng Jenkins ..."
docker compose down || true

ABS="$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")"

echo ">> Đang khôi phục ..."
docker run --rm \
  -v "${VOLUME}:/data" \
  -v "${ABS}:/backup.tar.gz:ro" \
  alpine \
  sh -c "rm -rf /data/* && cd /data && tar xzf /backup.tar.gz"

echo ">> Xong. Khởi động lại bằng: docker compose up -d"
