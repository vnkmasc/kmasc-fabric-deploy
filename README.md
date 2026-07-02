# kmasc-fabric-deploy

Bộ triển khai (one-stop) cho mạng Hyperledger Fabric dự án **certificate-management-system** của nhóm KMASC.  
Clone repo này về là có đủ: **chaincode binary build sẵn + scripts + tài liệu** để dựng mạng.

> Môi trường: **Ubuntu 22.04**. Chỉ dùng **Fabric** (không Besu). Chaincode viết bằng **Go** (CCaaS), chạy bằng **systemd**.

---

## Repo có gì

```
kmasc-fabric-deploy/
├── chaincode/
│   └── bin/
│       ├── cc-cert                  # binary tĩnh linux/amd64 (build sẵn, CGO_ENABLED=0)
│       └── BUILD-INFO.txt           # version, sha256, nguồn build
├── scripts/
│   ├── setup-fabric-binaries.sh     # cài ChainLaunch (pin version) + custom Fabric binaries
│   ├── sample-chaincode.sh          # quản lý chaincode CCaaS bằng systemd
│   └── build-chaincode.sh           # build lại binary khi sửa logic
└── docs/
    ├── vm-setup.md                  # tạo VM GCP, firewall, static IP
    ├── deploy-guide.md              # quy trình triển khai đầy đủ
    └── versions.md                  # version cố định (chainlaunch, fabric fork, chaincode)
```

---

## Mô hình

| Mặt phẳng | Lo việc gì | Công cụ |
|---|---|---|
| **Control plane** | install / approve / commit chaincode | `chainlaunch fabric install` |
| **Data plane** | chạy chaincode server (CCaaS) | `scripts/sample-chaincode.sh` + systemd |

Hai mặt phẳng độc lập — đúng tinh thần CCaaS. ChainLaunch không quản service chaincode này.

---

## Quy trình triển khai (mỗi máy / mỗi org)

```bash
# 0a) VM mới (GCP Ubuntu 22.04) — tạo VM (static IP), mở firewall, cài gói hệ thống
#     Toàn bộ lệnh apt-get + gcloud xem: docs/vm-setup.md

# 0b) Cài nền: ChainLaunch (pin v0.5.0-beta.2) + custom Fabric binaries
# vào để lấy token : https://github.com/settings/tokens
export GITHUB_TOKEN=ghp_...                    # repo vnkmasc/fabric private
./scripts/setup-fabric-binaries.sh setup
./scripts/setup-fabric-binaries.sh run         # ChainLaunch :3100
# → vào UI tạo org/peer/orderer/channel (xem docs/deploy-guide.md)

# 1) Control plane — install + approve (+ commit) qua chainlaunch
#    Sinh file .env chứa packageID (CORE_CHAINCODE_ID_NAME)
chainlaunch fabric install --local \
    --config=network-config.yaml \
    --channel=mychannel \
    --chaincode=cert \
    -o Org1MSP -u admin \
    --policy="OR('Org1MSP.member','Org2MSP.member','Org3MSP.member')" \
    --chaincodeAddress=localhost:9996 \
    --envFile=$HOME/chaincode/.env

# 2) Data plane — cài binary + chạy service
./scripts/sample-chaincode.sh install-bin     # copy binary → /opt/kmasc/cc-cert
./scripts/sample-chaincode.sh run             # đọc packageID từ .env → systemd service

# 3) Kiểm tra
./scripts/sample-chaincode.sh status
```

Chi tiết: [docs/deploy-guide.md](docs/deploy-guide.md).

---

## Quy tắc quan trọng

1. **Port phải khớp:** `--chaincodeAddress=localhost:<PORT>` (lúc install) và `CHAINCODE_SERVER_ADDRESS` (service) cùng `<PORT>`. Script dùng chung biến `CC_PORT` (mặc định 9996).
2. **Sửa logic chaincode** → `build-chaincode.sh` → `sample-chaincode.sh reload`. **Không cần** install/commit lại (packageID không đổi vì package CCaaS chỉ chứa connection.json).
3. **Đổi version/sequence chaincode** (governance) → install lại qua chainlaunch → packageID mới → `sample-chaincode.sh reload`.

---

## Version cố định

Xem [docs/versions.md](docs/versions.md) — ghim ChainLaunch, custom Fabric binaries (`vnkmasc/fabric`), và chaincode để tái lập đúng môi trường.
