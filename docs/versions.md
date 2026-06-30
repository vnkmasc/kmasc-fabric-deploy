# Version cố định

Ghim version để mọi lần triển khai đều tái lập đúng môi trường đã kiểm chứng.

| Thành phần | Version | Nguồn |
|---|---|---|
| **ChainLaunch** | ⚠️ _cần điền_ | chạy `chainlaunch version` trên máy đang chạy tốt rồi ghi vào đây |
| **Custom Fabric binaries** | `v3.1.1-mkv` (slot UI `3.1.3`) | `github.com/vnkmasc/fabric` releases (hybrid PQ: ML-DSA-65 + MKV256) |
| **Chaincode** | `cert v2.0.0` | `github.com/tuyenngduc/certificate-management-system` (xem `chaincode/bin/BUILD-INFO.txt`) |
| **Go (build chaincode)** | `go1.26.3` | binary tĩnh, CGO_ENABLED=0 |

---

## Vì sao phải ghim ChainLaunch

ChainLaunch nâng version có thể đổi: schema DB, format config node, hành vi CLI `fabric install`.  
Nếu các máy chạy version khác nhau → cert/config sinh ra có thể lệch. Ghim 1 version → đồng nhất 3 máy.

**Cách ghim:** thay vì cài bản mới nhất, tải đúng release ChainLaunch đã dùng. Ghi lại:
```
# Trên máy đang chạy ổn:
chainlaunch version
# → điền kết quả vào bảng trên + lưu lại URL/binary của release đó
```

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
