#!/usr/bin/env bash
###############################################################################
# Sao lưu toàn bộ JENKINS_HOME từ Docker volume.
# Kết quả: backups/jenkins-home-YYYYmmdd-HHMMSS.tar.gz
###############################################################################
set -euo pipefail

VOLUME="jenkins_home"
BACKUP_DIR="$(cd "$(dirname "$0")/.." && pwd)/backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="jenkins-home-${STAMP}.tar.gz"

mkdir -p "$BACKUP_DIR"

echo ">> Đang sao lưu volume '${VOLUME}' ..."
docker run --rm \
  -v "${VOLUME}:/data:ro" \
  -v "${BACKUP_DIR}:/backup" \
  alpine \
  sh -c "cd /data && tar czf /backup/${OUT} ."

echo ">> Xong: ${BACKUP_DIR}/${OUT}"
ls -lh "${BACKUP_DIR}/${OUT}"
