# Chuẩn bị VM GCP (Ubuntu 22.04)

Hướng dẫn tạo VM mới trên GCP và cài nền cho dự án. Làm cho **mỗi** máy (Org1/Org2/Org3).

---

## 1. Tạo VM

| Thông số | Đề xuất | Ghi chú |
|---|---|---|
| OS image | **Ubuntu 22.04 LTS** | amd64 |
| Machine type — Máy 1 (peer + 3 orderer) | `e2-standard-2` (2 vCPU, 8GB) | chạy nhiều process hơn |
| Machine type — Máy 2, 3 (chỉ 1 peer) | `e2-medium` (2 vCPU, 4GB) | đủ cho 1 peer + chaincode |
| Disk | **30GB** SSD | ledger + binaries + chaincode-data |
| External IP | **⚠️ Static (reserved)** | xem cảnh báo bên dưới |

### ⚠️ BẮT BUỘC: đặt Static IP

TLS cert của peer/orderer **nhúng cứng IP public vào SAN** (đã học ở phần identity/cert).  
GCP mặc định cấp **ephemeral IP** — đổi mỗi lần VM stop/start. Nếu IP đổi:
```
x509: certificate is valid for <ip-cũ>, not <ip-mới>
```
→ Cả mạng chết. Phải **reserve static external IP** cho mỗi VM ngay từ đầu.

```bash
# Reserve static IP (làm mỗi vùng/máy)
gcloud compute addresses create fabric-org1-ip --region=asia-southeast1
```

### Tạo VM bằng gcloud (ví dụ Máy 1)

```bash
gcloud compute instances create fabric-org1 \
  --zone=asia-southeast1-a \
  --machine-type=e2-standard-2 \
  --image-family=ubuntu-2204-lts --image-project=ubuntu-os-cloud \
  --boot-disk-size=30GB --boot-disk-type=pd-ssd \
  --address=fabric-org1-ip \
  --tags=fabric-node
```
(Máy 2/3: đổi tên, `--machine-type=e2-medium`, IP tương ứng.)

---

## 2. Mở firewall (VPC)

GCP chặn ingress mặc định — phải mở port qua **VPC firewall** (không phải ufw trong VM).  
Dùng network tag `fabric-node` (đã gắn khi tạo VM).

| Port | Ai cần | Máy nào mở |
|---|---|---|
| **3100** | Admin (UI ChainLaunch) | cả 3 |
| **7000** | Peer listen (gossip + endorsement liên org) | cả 3 |
| **9000, 9100, 9200** | Orderer listen (broadcast/deliver từ peer) | chỉ Máy 1 |
| ~~9996~~ | Chaincode CCaaS | **KHÔNG mở** — peer dial qua localhost cùng máy |

```bash
# Peer port — mở giữa các node (thay <cidr> bằng dải IP 3 máy, hoặc để rộng hơn nếu demo)
gcloud compute firewall-rules create fabric-peer \
  --allow=tcp:7000 --target-tags=fabric-node --source-ranges=0.0.0.0/0

# Orderer ports — chỉ cần cho Máy 1 (nhưng target-tag chung cũng không sao)
gcloud compute firewall-rules create fabric-orderer \
  --allow=tcp:9000,tcp:9100,tcp:9200 --target-tags=fabric-node --source-ranges=0.0.0.0/0

# ChainLaunch UI — NÊN giới hạn về IP admin, không để 0.0.0.0/0
gcloud compute firewall-rules create fabric-chainlaunch-ui \
  --allow=tcp:3100 --target-tags=fabric-node --source-ranges=<admin-ip>/32
```

> **Bảo mật:** mở peer/orderer ra `0.0.0.0/0` tiện cho demo nhưng rủi ro. Nếu được, giới hạn `--source-ranges` về đúng 3 IP static của cụm. UI `3100` nên chỉ mở cho IP admin.

---

## 3. Cài nền trong VM

```bash
# SSH vào VM, rồi:
git clone <repo-url> kmasc-fabric-deploy
cd kmasc-fabric-deploy

# 1) Cài gói cần thiết (vim, git, python3, curl, ...)
./scripts/bootstrap-vm.sh
#   Muốn build chaincode ngay trên VM: WITH_GO=1 ./scripts/bootstrap-vm.sh

# 2) Cài ChainLaunch (pin v0.5.0-beta.2) + custom Fabric binaries
export GITHUB_TOKEN=ghp_...
./scripts/setup-fabric-binaries.sh setup
source ~/.bashrc
./scripts/setup-fabric-binaries.sh run
```

`bootstrap-vm.sh` cài:
- **Bắt buộc:** `curl git python3 ca-certificates iproute2` (python3 để `setup-fabric-binaries.sh` parse JSON; `ss` để kiểm port)
- **Tiện ích:** `vim jq htop tmux wget unzip tree net-tools`
- **Tuỳ chọn:** Go (chỉ khi `WITH_GO=1`, để rebuild chaincode)

---

## 4. Thứ tự tổng thể mỗi VM

```
Tạo VM (static IP, tag fabric-node)
  └─► Mở firewall VPC (3100 / 7000 / 9000-9200)
       └─► SSH vào
            ├─► bootstrap-vm.sh              (gói hệ thống)
            ├─► setup-fabric-binaries.sh     (ChainLaunch + Fabric binaries)
            ├─► UI :3100 → tạo org/node/channel (External Endpoint = static IP)
            ├─► chainlaunch fabric install   (→ .env packageID)
            └─► sample-chaincode.sh run      (chaincode CCaaS qua systemd)
```

Chi tiết bước deploy: [deploy-guide.md](deploy-guide.md).
