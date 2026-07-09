#!/usr/bin/env bash
###############################################################################
# Khôi phục JENKINS_HOME (bind mount) từ file backup .tar.gz
# Dùng: bash scripts/restore.sh backups/jenkins-home-YYYYmmdd-HHMMSS.tar.gz
# CẢNH BÁO: ghi đè dữ liệu hiện tại trong JENKINS_HOME_HOST.
###############################################################################
set -euo pipefail

JENKINS_HOME_HOST="${JENKINS_HOME_HOST:-/data/jenkins_home}"
FILE="${1:-}"

if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "!! Vui lòng truyền đường dẫn file backup hợp lệ."
  echo "   Ví dụ: bash scripts/restore.sh backups/jenkins-home-20260709-120000.tar.gz"
  exit 1
fi

read -rp ">> Sẽ GHI ĐÈ '${JENKINS_HOME_HOST}'. Tiếp tục? (yes/no) " ans
[[ "$ans" == "yes" ]] || { echo "Đã huỷ."; exit 0; }

ABS="$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")"

echo ">> Dừng Jenkins ..."
docker compose down || true

echo ">> Đang khôi phục vào ${JENKINS_HOME_HOST} ..."
sudo mkdir -p "$JENKINS_HOME_HOST"
sudo find "$JENKINS_HOME_HOST" -mindepth 1 -delete
sudo tar xzf "$ABS" -C "$JENKINS_HOME_HOST"
sudo chown -R 1000:1000 "$JENKINS_HOME_HOST"

echo ">> Xong. Khởi động lại bằng: docker compose up -d"
