#!/usr/bin/env bash
#
# bootstrap-vm.sh — Cài các gói cần thiết cho VM Ubuntu 22.04 (GCP) mới
#
# Chạy NGAY sau khi SSH vào VM mới, TRƯỚC setup-fabric-binaries.sh.
# Idempotent: chạy lại nhiều lần không sao.
#
#   ./bootstrap-vm.sh            # cài gói bắt buộc + tiện ích
#   WITH_GO=1 ./bootstrap-vm.sh  # cài thêm Go (chỉ cần nếu muốn BUILD lại chaincode trên VM)
#
set -euo pipefail

# ─── Gói BẮT BUỘC cho dự án ───────────────────────────────────────────────────
#   curl            : tải install.sh + binaries
#   git             : clone repo
#   python3         : setup-fabric-binaries.sh dùng để parse JSON (download/replace/check)
#   ca-certificates : HTTPS
#   iproute2        : cung cấp 'ss' (sample-chaincode.sh status kiểm port)
REQUIRED=(curl git python3 ca-certificates iproute2)

# ─── Gói tiện ích (quality of life) ───────────────────────────────────────────
EXTRA=(vim jq htop tmux wget unzip tree net-tools)

# ─── Go (tuỳ chọn) — chỉ cần nếu build lại chaincode NGAY TRÊN VM ──────────────
GO_VERSION="${GO_VERSION:-1.26.3}"

log() { printf '\033[1;32m[bootstrap]\033[0m %s\n' "$*"; }

# ─── Kiểm tra OS ──────────────────────────────────────────────────────────────
if [ -r /etc/os-release ]; then
  . /etc/os-release
  log "OS: ${PRETTY_NAME:-unknown}"
  case "${VERSION_ID:-}" in
    22.04) : ;;
    *) log "⚠️  Script tối ưu cho Ubuntu 22.04. Bản khác có thể vẫn chạy được." ;;
  esac
fi

# ─── Cài gói ──────────────────────────────────────────────────────────────────
log "apt-get update..."
sudo apt-get update -y

log "Cài gói bắt buộc: ${REQUIRED[*]}"
sudo apt-get install -y "${REQUIRED[@]}"

log "Cài gói tiện ích: ${EXTRA[*]}"
sudo apt-get install -y "${EXTRA[@]}"

# ─── Go (tuỳ chọn) ────────────────────────────────────────────────────────────
if [ "${WITH_GO:-0}" = "1" ]; then
  if command -v go >/dev/null 2>&1 && go version | grep -q "go${GO_VERSION}"; then
    log "Go ${GO_VERSION} đã có, bỏ qua."
  else
    log "Cài Go ${GO_VERSION}..."
    TARBALL="go${GO_VERSION}.linux-amd64.tar.gz"
    curl -fsSL -o "/tmp/${TARBALL}" "https://go.dev/dl/${TARBALL}"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "/tmp/${TARBALL}"
    rm -f "/tmp/${TARBALL}"
    # Thêm vào PATH nếu chưa có
    if ! grep -q '/usr/local/go/bin' "$HOME/.bashrc" 2>/dev/null; then
      echo 'export PATH=$PATH:/usr/local/go/bin' >> "$HOME/.bashrc"
    fi
    export PATH="$PATH:/usr/local/go/bin"
    log "Go: $(/usr/local/go/bin/go version)"
  fi
fi

# ─── Tổng kết ─────────────────────────────────────────────────────────────────
echo
log "Xong. Version các công cụ chính:"
printf '  %-8s %s\n' "curl"    "$(curl --version 2>/dev/null | head -1 || echo '?')"
printf '  %-8s %s\n' "git"     "$(git --version 2>/dev/null || echo '?')"
printf '  %-8s %s\n' "python3" "$(python3 --version 2>/dev/null || echo '?')"
printf '  %-8s %s\n' "ss"      "$(command -v ss || echo '?')"
[ "${WITH_GO:-0}" = "1" ] && printf '  %-8s %s\n' "go" "$(/usr/local/go/bin/go version 2>/dev/null || echo '?')"

cat <<EOF

Bước tiếp theo:
  1. Clone repo (nếu chưa):  git clone <repo-url> kmasc-fabric-deploy && cd kmasc-fabric-deploy
  2. Cài ChainLaunch + Fabric binaries:
       export GITHUB_TOKEN=ghp_...      # repo vnkmasc/fabric là private
       ./scripts/setup-fabric-binaries.sh setup
       ./scripts/setup-fabric-binaries.sh run
  3. Mở firewall GCP cho các port (xem docs/vm-setup.md)
EOF
