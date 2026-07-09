#!/usr/bin/env bash
###############################################################################
# Dọn image/layer/build-cache thừa để tránh đầy disk (nguyên nhân chết #1).
# An toàn: KHÔNG đụng volume có tên, KHÔNG đụng image đang được container dùng.
# Chạy định kỳ qua cron (xem README).
###############################################################################
set -euo pipefail

KEEP="${KEEP_HOURS:-168h}"   # giữ lại thứ mới hơn 7 ngày (mặc định)

echo "===== Docker maintenance $(date '+%F %T') ====="
echo ">> Disk trước khi dọn:"
docker system df

echo ">> Xoá container đã dừng > ${KEEP} ..."
docker container prune -f --filter "until=${KEEP}"

echo ">> Xoá image không dùng > ${KEEP} ..."
docker image prune -af --filter "until=${KEEP}"

echo ">> Xoá build cache > ${KEEP} ..."
docker builder prune -af --filter "until=${KEEP}"

echo ">> Xoá network mồ côi ..."
docker network prune -f

echo ">> Disk sau khi dọn:"
docker system df

# Cảnh báo nếu phân vùng chứa /data còn dưới 15% trống
DATA_DIR="${JENKINS_HOME_HOST:-/data/jenkins_home}"
AVAIL_PCT=$(df --output=pcent "$DATA_DIR" 2>/dev/null | tail -1 | tr -dc '0-9' || echo 0)
if [[ -n "$AVAIL_PCT" && "$AVAIL_PCT" -ge 85 ]]; then
  echo "!! CẢNH BÁO: phân vùng chứa ${DATA_DIR} đã dùng ${AVAIL_PCT}% — cần dọn thêm/mở rộng disk."
fi
echo "===== Done ====="
