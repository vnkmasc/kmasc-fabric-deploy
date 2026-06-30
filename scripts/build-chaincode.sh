#!/usr/bin/env bash
#
# build-chaincode.sh — Build lại chaincode Go thành binary tĩnh linux/amd64
#
# Chỉ cần chạy lại khi sửa logic chaincode. Output ghi đè chaincode/bin/cc-cert.
# packageID KHÔNG đổi khi rebuild (package CCaaS chỉ chứa connection.json),
# nên sau rebuild chỉ cần: sample-chaincode.sh reload  — không phải install lại.
#
set -euo pipefail

# Đường dẫn tới source chaincode (certificate-management-system/chaincode)
CC_SRC="${CC_SRC:-V:/Project/Kmasc/chaincode}"
# Package main nằm trong subdir nào
CC_PKG="${CC_PKG:-./contractapi}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${REPO_ROOT}/chaincode/bin/cc-cert"

[ -f "$CC_SRC/go.mod" ] || { echo "Không thấy go.mod tại $CC_SRC" >&2; exit 1; }

echo "[build] source = $CC_SRC  →  out = $OUT"
cd "$CC_SRC"
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
  go build -mod=vendor -trimpath -ldflags="-s -w" -o "$OUT" "$CC_PKG"

echo "[build] OK"
sha256sum "$OUT" 2>/dev/null || shasum -a 256 "$OUT"
