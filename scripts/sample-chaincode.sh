#!/usr/bin/env bash
#
# sample-chaincode.sh — Quản lý chaincode CCaaS (Go) bằng systemd
#
# Tách bạch 2 mặt phẳng:
#   - Control plane (install/approve/commit): dùng `chainlaunch fabric install`
#   - Data plane (chạy chaincode server):     script này, qua systemd
#
# Chaincode là binary Go tĩnh, chạy ở chế độ CCaaS server. Nó đăng ký với peer
# bằng packageID (CORE_CHAINCODE_ID_NAME) — lấy từ file .env mà chainlaunch sinh ra.
#
set -euo pipefail

# ─── Cấu hình (override qua biến môi trường) ──────────────────────────────────
CC_NAME="${CC_NAME:-cert}"                       # tên chaincode (chỉ để đặt tên service)
CC_PORT="${CC_PORT:-9996}"                        # port CCaaS server lắng nghe
CC_BIN="${CC_BIN:-/opt/kmasc/cc-cert}"            # nơi đặt binary khi chạy
ENV_FILE="${ENV_FILE:-$HOME/chaincode/.env}"      # .env do `chainlaunch fabric install` sinh
SERVICE_USER="${SERVICE_USER:-$(id -un)}"         # user chạy service
SERVICE_NAME="kmasc-cc-${CC_NAME}"
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

# Binary build sẵn trong repo (dùng cho lệnh `install-bin`)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_BIN="${REPO_ROOT}/chaincode/bin/cc-cert"

# ─── Tiện ích ─────────────────────────────────────────────────────────────────
log()  { printf '\033[1;32m[cc]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[cc]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[cc] LỖI:\033[0m %s\n' "$*" >&2; exit 1; }

read_package_id() {
  [ -f "$ENV_FILE" ] || die "Không thấy file .env: $ENV_FILE
  → Chạy 'chainlaunch fabric install ... --envFile=$ENV_FILE' trước."
  local pid
  pid="$(grep -E '^CORE_CHAINCODE_ID_NAME=' "$ENV_FILE" | head -1 | cut -d= -f2-)"
  [ -n "$pid" ] || die "Không đọc được CORE_CHAINCODE_ID_NAME trong $ENV_FILE"
  printf '%s' "$pid"
}

write_unit() {
  local pkg_id="$1"
  log "Ghi unit file: $UNIT_PATH"
  sudo tee "$UNIT_PATH" >/dev/null <<EOF
[Unit]
Description=KMASC Chaincode (CCaaS) - ${CC_NAME}
After=network.target

[Service]
Type=simple
User=${SERVICE_USER}
ExecStart=${CC_BIN}
Environment="CORE_CHAINCODE_ID_NAME=${pkg_id}"
Environment="CHAINCODE_SERVER_ADDRESS=0.0.0.0:${CC_PORT}"
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
}

# ─── Lệnh ─────────────────────────────────────────────────────────────────────
cmd_install_bin() {
  [ -f "$REPO_BIN" ] || die "Không thấy binary trong repo: $REPO_BIN"
  log "Cài binary → $CC_BIN"
  sudo mkdir -p "$(dirname "$CC_BIN")"
  sudo cp "$REPO_BIN" "$CC_BIN"
  sudo chmod +x "$CC_BIN"
  log "Xong. SHA256:"; sha256sum "$CC_BIN"
}

cmd_run() {
  [ -x "$CC_BIN" ] || die "Chưa có binary tại $CC_BIN — chạy '$0 install-bin' trước."
  local pkg_id; pkg_id="$(read_package_id)"
  log "packageID = $pkg_id"
  write_unit "$pkg_id"
  sudo systemctl daemon-reload
  sudo systemctl enable "$SERVICE_NAME"
  sudo systemctl restart "$SERVICE_NAME"
  log "Đã start $SERVICE_NAME. Kiểm tra: $0 status"
}

cmd_reload() {
  # Dùng sau khi: reinstall (packageID mới) HOẶC rebuild binary (logic mới)
  cmd_run
}

cmd_stop()   { sudo systemctl stop "$SERVICE_NAME"; log "Đã stop $SERVICE_NAME"; }

cmd_status() {
  systemctl --no-pager status "$SERVICE_NAME" || true
  echo "--- Port $CC_PORT ---"
  ss -tlnp 2>/dev/null | grep ":$CC_PORT" || warn "Port $CC_PORT chưa lắng nghe"
}

cmd_logs() { journalctl -u "$SERVICE_NAME" -f; }

usage() {
  cat <<EOF
Cách dùng: $0 <lệnh>

  install-bin   Copy binary build sẵn (repo) → $CC_BIN
  run           Đọc packageID từ .env → sinh systemd unit → enable + start
  reload        Ghi lại unit + restart (sau khi reinstall hoặc rebuild binary)
  stop          Dừng service
  status        Trạng thái service + kiểm port $CC_PORT
  logs          Xem log live

Biến môi trường (có default):
  CC_NAME=$CC_NAME  CC_PORT=$CC_PORT  CC_BIN=$CC_BIN
  ENV_FILE=$ENV_FILE
  SERVICE_USER=$SERVICE_USER

Quy trình lần đầu trên mỗi máy:
  1) chainlaunch fabric install ... --chaincodeAddress=localhost:$CC_PORT --envFile=$ENV_FILE
  2) $0 install-bin
  3) $0 run
EOF
}

case "${1:-}" in
  install-bin) cmd_install_bin ;;
  run)         cmd_run ;;
  reload)      cmd_reload ;;
  stop)        cmd_stop ;;
  status)      cmd_status ;;
  logs)        cmd_logs ;;
  *)           usage; exit 1 ;;
esac
