#!/usr/bin/env bash
set -euo pipefail

SCHEDULE="0 3 * * *"
CLEANUP_SCRIPT="/usr/local/sbin/docker-cleanup.sh"
CRON_FILE="/etc/cron.d/docker-cleanup"
LOG_FILE="/var/log/docker-cleanup.log"

if [ "$(id -u)" -ne 0 ]; then
  echo "请用 sudo 执行：sudo bash $0"
  exit 1
fi

echo "[1/5] 检查 Docker..."
if ! command -v docker >/dev/null 2>&1; then
  echo "未找到 docker 命令，请先安装 Docker。"
  exit 1
fi

echo "[2/5] 安装并启动 cron..."
if ! command -v cron >/dev/null 2>&1; then
  apt-get update
  apt-get install -y cron
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl enable cron || true
  systemctl start cron || true
else
  service cron start || true
fi

echo "[3/5] 创建 Docker 清理脚本：$CLEANUP_SCRIPT"
cat > "$CLEANUP_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/var/log/docker-cleanup.log"
LOCK_FILE="/var/run/docker-cleanup.lock"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "$(date '+%F %T') docker cleanup already running" >> "$LOG_FILE"
  exit 0
fi

{
  echo "===== $(date '+%F %T') docker cleanup start ====="

  echo "[before]"
  docker system df || true

  echo "[cleanup stopped containers]"
  docker container prune -f || true

  echo "[cleanup unused networks]"
  docker network prune -f || true

  echo "[cleanup unused images older than 7 days]"
  docker image prune -af --filter "until=168h" || true

  echo "[cleanup build cache older than 7 days]"
  docker builder prune -af --filter "until=168h" || true

  echo "[after]"
  docker system df || true

  echo "===== $(date '+%F %T') docker cleanup done ====="
  echo
} >> "$LOG_FILE" 2>&1
EOF

chmod +x "$CLEANUP_SCRIPT"

echo "[4/5] 配置 cron：每天凌晨 3 点执行"
cat > "$CRON_FILE" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

$SCHEDULE root $CLEANUP_SCRIPT
EOF

chmod 644 "$CRON_FILE"

echo "[5/5] 执行一次测试清理..."
"$CLEANUP_SCRIPT"

echo
echo "配置完成。"
echo "清理脚本：$CLEANUP_SCRIPT"
echo "定时任务：$CRON_FILE"
echo "日志文件：$LOG_FILE"
echo
echo "查看日志："
echo "  sudo tail -n 100 $LOG_FILE"
echo
echo "查看定时任务："
echo "  cat $CRON_FILE"
