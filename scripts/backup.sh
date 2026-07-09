#!/usr/bin/env bash
###############################################################################
# Sao lưu toàn bộ JENKINS_HOME (bind mount trên host).
# Kết quả: backups/jenkins-home-YYYYmmdd-HHMMSS.tar.gz
###############################################################################
set -euo pipefail

JENKINS_HOME_HOST="${JENKINS_HOME_HOST:-/data/jenkins_home}"
BACKUP_DIR="$(cd "$(dirname "$0")/.." && pwd)/backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="jenkins-home-${STAMP}.tar.gz"

if [[ ! -d "$JENKINS_HOME_HOST" ]]; then
  echo "!! Không thấy thư mục dữ liệu: $JENKINS_HOME_HOST"
  exit 1
fi

mkdir -p "$BACKUP_DIR"

echo ">> Đang sao lưu '${JENKINS_HOME_HOST}' ..."
# Loại trừ cache/log nặng, không cần thiết cho khôi phục
sudo tar czf "${BACKUP_DIR}/${OUT}" \
  --exclude='./workspace' \
  --exclude='./caches' \
  --exclude='./war' \
  --exclude='./logs' \
  -C "$JENKINS_HOME_HOST" .

sudo chown "$(id -u):$(id -g)" "${BACKUP_DIR}/${OUT}" || true

echo ">> Xong: ${BACKUP_DIR}/${OUT}"
ls -lh "${BACKUP_DIR}/${OUT}"
