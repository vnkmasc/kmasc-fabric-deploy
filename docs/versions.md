# Version cố định

Ghim version để mọi lần triển khai đều tái lập đúng môi trường đã kiểm chứng.

| Thành phần | Version | Nguồn |
|---|---|---|
| **OS** | Ubuntu 22.04 (amd64) | máy triển khai |
| **ChainLaunch** | `v0.5.0-beta.2` (commit `39cf3a7`, build 2026-05-06) | `github.com/LF-Decentralized-Trust-labs/chaindeploy` releases |
| **Custom Fabric binaries** | `v3.1.1-mkv` (slot UI `3.1.3`) | `github.com/vnkmasc/fabric` releases (hybrid PQ: ML-DSA-65 + MKV256) |
| **Chaincode** | `cert v2.0.0` | `github.com/tuyenngduc/certificate-management-system` (xem `chaincode/bin/BUILD-INFO.txt`) |
| **Go (build chaincode)** | `go1.26.3` | binary tĩnh, CGO_ENABLED=0 |

---

## Vì sao phải ghim ChainLaunch

ChainLaunch nâng version có thể đổi: schema DB, format config node, hành vi CLI `fabric install`.  
Nếu các máy chạy version khác nhau → cert/config sinh ra có thể lệch. Ghim 1 version → đồng nhất 3 máy.

**Cách ghim:** `install.sh` của ChainLaunch nhận version qua **positional arg**. Script `setup-fabric-binaries.sh` đã pin sẵn (biến `CHAINLAUNCH_VERSION=v0.5.0-beta.2`):
```bash
# Cài đúng version ghim:
curl -fsSL https://chainlaunch.dev/install.sh | bash -s v0.5.0-beta.2

# Kiểm tra version đang chạy:
chainlaunch version
# Version: v0.5.0-beta.2
# Git Commit: 39cf3a7b2fe656e531c3f4b1505dd5a20dbb3bd1
# Build Time: 2026-05-06T06:43:26Z
```
`setup-fabric-binaries.sh check` sẽ tự cảnh báo nếu version đang cài lệch khỏi pin.

## Custom Fabric binaries

Đã cố định qua `setup-fabric-binaries.sh` (repo `overview`):
```
GITHUB_REPO=vnkmasc/fabric
RELEASE_TAG=v3.1.1-mkv
BINARY_VERSION=3.1.1
VERSION=3.1.3            # slot hiển thị trong ChainLaunch UI
```
Khi tạo node để version mặc định **3.1.3** → ChainLaunch tự dùng custom binary.

## Chaincode

Binary build sẵn ở `chaincode/bin/cc-cert`. Thông tin build đầy đủ trong `chaincode/bin/BUILD-INFO.txt`.  
Build lại: `scripts/build-chaincode.sh` (cần Go + source certificate-management-system).
