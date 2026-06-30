#!/usr/bin/env bash
set -euo pipefail

# =============================================================
#  Chainlaunch + Fabric custom binaries helper
#  Môi trường đích: Ubuntu 22.04 (amd64)
#
#  WORKFLOW cho máy mới (chưa có gì):
#    1. ./setup-fabric-binaries.sh setup   # cài chainlaunch (pin version) + custom binaries
#    2. ./setup-fabric-binaries.sh run     # khởi động chainlaunch
#    3. Mở UI, tạo node → dùng version mặc định (3.1.3) → tự dùng custom binary
#
#  Đã có Chainlaunch đang chạy, muốn swap sang custom binary:
#    ./setup-fabric-binaries.sh replace    # dừng node, thay binary, khởi động lại
#
#  Kiểm tra trạng thái:
#    ./setup-fabric-binaries.sh check
# =============================================================

# Resolve home dir đúng khi chạy dưới sudo
real_home() {
  if [ "${SUDO_USER:-}" != "" ] && [ "${SUDO_USER:-}" != "root" ]; then
    local h
    h="$(getent passwd "$SUDO_USER" | cut -d: -f6 || true)"
    [ -n "$h" ] && echo "$h" && return
  fi
  echo "${HOME:-/root}"
}

REAL_HOME="$(real_home)"

# ----- CẤU HÌNH -----
DATA_PATH="${DATA_PATH:-$REAL_HOME/chainlaunch-data}"
DB_PATH="${DB_PATH:-$REAL_HOME/chainlaunch.db}"
PORT="${PORT:-3100}"
CHAINLAUNCH_USER="${CHAINLAUNCH_USER:-admin}"
CHAINLAUNCH_PASSWORD="${CHAINLAUNCH_PASSWORD:-admin123}"

# Version ChainLaunch ghim cố định (đã kiểm chứng). install.sh nhận tag qua positional arg.
# Để trống ("") sẽ cài bản latest — KHÔNG khuyến nghị (lệch version giữa các máy).
CHAINLAUNCH_VERSION="${CHAINLAUNCH_VERSION:-v0.5.0-beta.2}"

# VERSION phải là một trong các version có trong Chainlaunch UI:
#   3.1.3 (mặc định UI), 3.1.2, 3.1.0, 3.0.0, 2.5.12
# Dùng 3.1.3 để người dùng không cần đổi gì khi tạo node trên UI.
VERSION="${VERSION:-3.1.3}"

# GitHub fork fabric của bạn (KHÔNG phải fork chainlaunch)
GITHUB_REPO="${GITHUB_REPO:-vnkmasc/fabric}"
RELEASE_TAG="${RELEASE_TAG:-v3.1.1-mkv}"
BINARY_VERSION="${BINARY_VERSION:-3.1.1}"
# Token cho repo private (tạo tại https://github.com/settings/tokens → repo scope)
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
# ---------------------

BIN_DIR="${DATA_PATH}/bin/${VERSION}/bin"
BASE_URL="https://github.com/${GITHUB_REPO}/releases/download/${RELEASE_TAG}"
TARBALL="fabric-mkv-linux-amd64-${BINARY_VERSION}.tar.gz"

# API Chainlaunch (dùng trong lệnh replace)
API="http://localhost:${PORT}/api/v1"
AUTH="-u ${CHAINLAUNCH_USER}:${CHAINLAUNCH_PASSWORD}"

# ---------------------------------------------------------------

print_header() {
  echo "============================================================"
  echo "  Chainlaunch + Fabric custom binaries (Ubuntu 22.04)"
  echo "  Chainlaunch version (ghim) : ${CHAINLAUNCH_VERSION:-latest}"
  echo "  Fork: ${GITHUB_REPO} @ ${RELEASE_TAG}"
  echo "  Binary version : ${BINARY_VERSION}"
  echo "  Chainlaunch UI version slot : ${VERSION}"
  echo "  Binary dir : ${BIN_DIR}"
  echo "============================================================"
  echo
}

usage() {
  cat <<EOF
Usage: $0 <lệnh>

  setup    Cài Chainlaunch (pin version ${CHAINLAUNCH_VERSION:-latest}) + tải custom Fabric binaries.
           Chạy lệnh này TRƯỚC khi tạo node trên UI lần đầu.

  run      Khởi động Chainlaunch serve.

  replace  Thay custom binaries vào Chainlaunch đang chạy.
           Dùng khi đã có node đang chạy với version ${VERSION}.
           Tự động: dừng node → swap binary → khởi động lại.

  check    Kiểm tra binary đang chạy và version (cả chainlaunch).

  clean    Xoá toàn bộ data (hỏi lại trước khi xoá).

Biến môi trường tuỳ chỉnh:
  CHAINLAUNCH_VERSION, VERSION, GITHUB_REPO, RELEASE_TAG, BINARY_VERSION,
  DATA_PATH, DB_PATH, PORT, CHAINLAUNCH_USER, CHAINLAUNCH_PASSWORD
EOF
}

ensure_dep() {
  local cmd="$1" pkg="${2:-$1}"
  command -v "$cmd" >/dev/null 2>&1 && return
  echo "Thiếu '$cmd', đang cài '$pkg'..."
  if command -v apt-get >/dev/null 2>&1; then sudo apt-get install -y "$pkg"
  elif command -v yum >/dev/null 2>&1; then sudo yum install -y "$pkg"
  elif command -v dnf >/dev/null 2>&1; then sudo dnf install -y "$pkg"
  else echo "Không tự cài được '$pkg'. Hãy cài thủ công."; exit 1; fi
}

# Đường dẫn binary chainlaunch (PATH hoặc ~/.chainlaunch/bin)
chainlaunch_bin() {
  command -v chainlaunch 2>/dev/null && return
  [ -x "${REAL_HOME}/.chainlaunch/bin/chainlaunch" ] && echo "${REAL_HOME}/.chainlaunch/bin/chainlaunch" && return
  return 1
}

# In version chainlaunch hiện tại + cảnh báo nếu lệch pin
verify_chainlaunch_version() {
  local bin ver
  bin="$(chainlaunch_bin || true)"
  [ -z "$bin" ] && { echo "  chainlaunch: chưa cài"; return; }
  ver="$("$bin" version 2>/dev/null | grep -i '^Version:' | head -1 | awk '{print $2}' || true)"
  echo "  chainlaunch: ${ver:-?}"
  if [ -n "${CHAINLAUNCH_VERSION:-}" ] && [ -n "$ver" ] && [ "$ver" != "$CHAINLAUNCH_VERSION" ]; then
    echo "  ⚠️  Version đang cài ($ver) KHÁC version ghim ($CHAINLAUNCH_VERSION)."
    echo "     Gỡ chainlaunch cũ rồi chạy lại 'setup' nếu muốn đồng nhất."
  fi
}

# Tải binary từ GitHub về BIN_DIR
download_binaries() {
  echo "[2/3] Tải custom binaries → ${BIN_DIR}"
  sudo mkdir -p "${BIN_DIR}"

  echo "  Tải ${BASE_URL}/${TARBALL} ..."
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    # Repo private: dùng GitHub API để lấy asset ID rồi download đúng cách
    ASSET_ID=$(curl -fsSL \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      "https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${RELEASE_TAG}" \
      | python3 -c "
import sys, json
d = json.load(sys.stdin)
t = '${TARBALL}'
assets = [a for a in d.get('assets', []) if a['name'] == t]
print(assets[0]['id'] if assets else '')
")
    if [ -z "$ASSET_ID" ]; then
      echo "  LỖI: Không tìm thấy asset '${TARBALL}' trong release ${RELEASE_TAG}" >&2
      exit 1
    fi
    curl -fsSL \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Accept: application/octet-stream" \
      -o "/tmp/${TARBALL}" \
      "https://api.github.com/repos/${GITHUB_REPO}/releases/assets/${ASSET_ID}"
  else
    curl -fsSL -o "/tmp/${TARBALL}" "${BASE_URL}/${TARBALL}"
  fi

  EXTRACT_DIR="$(mktemp -d)"
  tar -xzf "/tmp/${TARBALL}" -C "$EXTRACT_DIR"

  find "$EXTRACT_DIR" -type f -executable | while read -r f; do
    name="$(basename "$f")"
    echo "  + $name"
    sudo cp "$f" "${BIN_DIR}/${name}"
    sudo chmod +x "${BIN_DIR}/${name}"
  done

  rm -rf "$EXTRACT_DIR" "/tmp/${TARBALL}"

  echo
  echo "  Kiểm tra nhanh:"
  if "${BIN_DIR}/peer" version 2>/dev/null | grep -q "Version:"; then
    echo "  peer  : $("${BIN_DIR}/peer" version 2>/dev/null | grep 'Version:' | head -1 | xargs)"
  else
    echo "  peer  : LỖI — chạy '${BIN_DIR}/peer version' để xem chi tiết"
  fi
  if "${BIN_DIR}/orderer" version 2>/dev/null | grep -q "Version:"; then
    echo "  orderer: $("${BIN_DIR}/orderer" version 2>/dev/null | grep 'Version:' | head -1 | xargs)"
  else
    echo "  orderer: LỖI"
  fi
}

cmd_setup() {
  print_header
  ensure_dep curl curl

  if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "CẢNH BÁO: GITHUB_TOKEN chưa được set."
    echo "  Repo '${GITHUB_REPO}' là private — tải sẽ thất bại nếu không có token."
    echo "  Tạo token tại: https://github.com/settings/tokens (scope: repo)"
    echo "  Sau đó chạy: export GITHUB_TOKEN=<token> && $0 setup"
    echo
  fi

  # 1) Cài Chainlaunch (pin đúng version qua positional arg của install.sh)
  if ! chainlaunch_bin >/dev/null 2>&1; then
    echo "[1/3] Cài Chainlaunch ${CHAINLAUNCH_VERSION:-latest}..."
    if [ -n "${CHAINLAUNCH_VERSION:-}" ]; then
      curl -fsSL https://chainlaunch.dev/install.sh | bash -s "${CHAINLAUNCH_VERSION}"
    else
      curl -fsSL https://chainlaunch.dev/install.sh | bash
    fi
    echo
  else
    echo "[1/3] Chainlaunch đã có, bỏ qua."
  fi
  verify_chainlaunch_version
  echo

  # 2+3) Tải binary
  download_binaries

  echo
  echo "============================================================"
  echo "  DONE. Bước tiếp theo:"
  echo
  echo "  1. Nếu terminal chưa nhận 'chainlaunch', chạy:"
  echo "       source \"\$HOME/.bashrc\""
  echo
  echo "  2. Khởi động Chainlaunch:"
  echo "       $0 run"
  echo
  echo "  3. Mở UI tại http://localhost:${PORT}"
  echo "     Tạo node → chọn version '${VERSION}' (mặc định) → tự dùng custom binary"
  echo "============================================================"
}

cmd_run() {
  print_header

  CHAINLAUNCH_BIN="$(chainlaunch_bin || true)"
  if [ -z "$CHAINLAUNCH_BIN" ]; then
    echo "Lỗi: chainlaunch chưa cài. Chạy: $0 setup"
    exit 1
  fi

  echo "Khởi động Chainlaunch tại http://localhost:${PORT} ..."
  echo "  data = ${DATA_PATH}"
  echo "  db   = ${DB_PATH}"
  echo
  export CHAINLAUNCH_USER CHAINLAUNCH_PASSWORD
  sudo -E "$CHAINLAUNCH_BIN" serve \
    --data="$DATA_PATH" \
    --db="$DB_PATH" \
    --port="$PORT"
}

cmd_replace() {
  print_header
  ensure_dep curl curl

  echo "Bước 1/4: Tải custom binaries mới..."
  download_binaries
  echo

  echo "Bước 2/4: Tìm nodes đang chạy với version '${VERSION}'..."
  # Lấy danh sách node ID đang dùng VERSION qua API
  NODE_IDS=$(curl -sf ${AUTH} "${API}/nodes" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
ids = []
for n in data.get('items', []):
    fab = n.get('fabricPeer') or n.get('fabricOrderer') or {}
    if fab.get('version') == '${VERSION}' and n.get('status') == 'RUNNING':
        ids.append(str(n['id']))
print(' '.join(ids))
" 2>/dev/null || true)

  if [ -z "$NODE_IDS" ]; then
    echo "  Không có node nào đang RUNNING với version '${VERSION}'."
    echo "  Binary đã được đặt vào ${BIN_DIR}. Xong."
    return
  fi

  echo "  Nodes cần restart: $NODE_IDS"
  echo

  # Dừng từng node — binary đã bị swap khi download nên process cũ đang dùng inode cũ,
  # cần kill process thực sự để reload binary mới
  echo "Bước 3/4: Dừng và restart nodes..."
  for id in $NODE_IDS; do
    name=$(curl -sf ${AUTH} "${API}/nodes/${id}" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('name','node-'+str(${id})))" 2>/dev/null || echo "node-${id}")
    echo "  Stop ${name} (id=${id})..."
    curl -sf ${AUTH} -X POST "${API}/nodes/${id}/stop" -o /dev/null 2>/dev/null || true
    sleep 1
    # Kill process thực sự nếu còn
    sudo pkill -f "${BIN_DIR}/peer node start" 2>/dev/null || true
    sudo pkill -f "${BIN_DIR}/orderer" 2>/dev/null || true
    sleep 1
    echo "  Start ${name} (id=${id})..."
    curl -sf ${AUTH} -X POST "${API}/nodes/${id}/start" -o /dev/null 2>/dev/null || true
    sleep 2
  done

  echo
  echo "Bước 4/4: Kiểm tra..."
  sleep 2
  RUNNING=$(ps aux | grep -E "${VERSION}/bin/(peer|orderer)" | grep -v grep | awk '{print $11}' | sort -u)
  if [ -n "$RUNNING" ]; then
    echo "  OK — đang chạy:"
    echo "$RUNNING" | sed 's/^/    /'
    echo
    echo "  Version binary:"
    "${BIN_DIR}/peer" version 2>/dev/null | head -3 | sed 's/^/    /'
  else
    echo "  Chưa thấy process — Chainlaunch có thể cần thêm vài giây. Chạy '$0 check' để kiểm tra."
  fi
}

cmd_check() {
  print_header

  echo "--- Chainlaunch ---"
  verify_chainlaunch_version
  echo

  echo "--- Thư mục bin/ ---"
  ls -1 "${DATA_PATH}/bin/" 2>/dev/null | sed 's/^/  /' || echo "  (chưa có)"
  echo

  echo "--- Binary custom (${VERSION}) ---"
  if [ -x "${BIN_DIR}/peer" ]; then
    "${BIN_DIR}/peer" version 2>/dev/null | head -3 | sed 's/^/  /'
  else
    echo "  CHƯA CÀI — chạy '$0 setup'"
  fi
  echo

  echo "--- Processes đang chạy ---"
  PROCS=$(ps aux | grep -E 'peer node|orderer' | grep -v grep | awk '{print $11}' | sort -u)
  if [ -z "$PROCS" ]; then
    echo "  (không có)"
  else
    echo "$PROCS" | while read -r p; do
      if echo "$p" | grep -q "${VERSION}"; then
        echo "  [custom] $p"
      else
        echo "  [other]  $p"
      fi
    done
  fi
}

cmd_clean() {
  print_header
  echo "Sắp xoá:"
  echo "  DATA_PATH = $DATA_PATH"
  echo "  DB_PATH   = $DB_PATH"
  echo
  read -r -p "Chắc chắn? (y/N) " ans
  case "$ans" in
    y|Y|yes|YES)
      rm -rf "$DATA_PATH" "$DB_PATH"
      echo "Đã xoá."
      ;;
    *)
      echo "Huỷ."
      ;;
  esac
}

main() {
  case "${1:-help}" in
    setup)   cmd_setup ;;
    run)     cmd_run ;;
    replace) cmd_replace ;;
    check)   cmd_check ;;
    clean)   cmd_clean ;;
    -h|--help|help) usage ;;
    *)
      echo "Lệnh không hợp lệ: $1"
      echo
      usage
      exit 1
      ;;
  esac
}

main "$@"
