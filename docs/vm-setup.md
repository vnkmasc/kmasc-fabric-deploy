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

### 3.1. Cài gói hệ thống

```bash
sudo apt-get update -y

# Bắt buộc cho dự án
#   python3        → setup-fabric-binaries.sh dùng parse JSON
#   iproute2       → lệnh 'ss' (sample-chaincode.sh kiểm port)
sudo apt-get install -y curl git python3 ca-certificates iproute2

# Tiện ích (tuỳ chọn)
sudo apt-get install -y vim jq htop tmux wget unzip tree net-tools
```

> Chaincode chạy bằng binary Go **tĩnh** (build sẵn trong repo) → VM **không cần** cài Go.
> Chỉ cài Go nếu muốn build lại chaincode ngay trên VM (xem `scripts/build-chaincode.sh`).

### 3.2. Cài Docker (bắt buộc — kể cả không dùng docker-mode node)

ChainLaunch khởi động `pluginManager` lúc `serve`, và bước đó **check Docker engine** ngay cả khi
mọi peer/orderer chạy ở mode `service` (systemd), không phải `docker`. Thiếu Docker → log lỗi:
```
Failed to initialize plugin manager: failed to check if Docker engine is running:
Cannot connect to the Docker daemon at unix:///var/run/docker.sock
```

Cài Docker Engine (theo hướng dẫn chính thức, Ubuntu 22.04):

```bash
# Gỡ bản cũ nếu có (bỏ qua lỗi nếu chưa cài)
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  sudo apt-get remove -y $pkg 2>/dev/null || true
done

# Thêm GPG key + repo chính thức của Docker
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y

# Cài Docker Engine + CLI + Compose plugin
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Cho user hiện tại chạy docker không cần sudo (đăng nhập lại hoặc `newgrp docker` để áp dụng)
sudo usermod -aG docker "$USER"

# Kiểm tra
sudo systemctl enable --now docker
docker version
```

> Nếu chạy script `setup-fabric-binaries.sh` bằng `sudo` (như trong `cmd_run`), Docker daemon cần chạy
> sẵn trước — `docker.sock` do root sở hữu, `sudo -E chainlaunch serve` sẽ dùng được ngay không cần vào group.

### 3.3. Clone repo + cài ChainLaunch/Fabric

```bash
git clone <repo-url> kmasc-fabric-deploy
cd kmasc-fabric-deploy

export GITHUB_TOKEN=ghp_...                     # repo vnkmasc/fabric private
./scripts/setup-fabric-binaries.sh setup        # ChainLaunch (pin v0.5.0-beta.2) + Fabric binaries
source ~/.bashrc
./scripts/setup-fabric-binaries.sh run          # ChainLaunch :3100
```

---

## 4. Thứ tự tổng thể mỗi VM

```
Tạo VM (static IP, tag fabric-node)
  └─► Mở firewall VPC (3100 / 7000 / 9000-9200)
       └─► SSH vào
            ├─► apt-get install ...          (gói hệ thống — mục 3.1)
            ├─► cài Docker                   (bắt buộc — mục 3.2, xem cảnh báo)
            ├─► setup-fabric-binaries.sh     (ChainLaunch + Fabric binaries)
            ├─► UI :3100 → tạo org/node/channel (External Endpoint = static IP)
            ├─► chainlaunch fabric install   (→ .env packageID)
            └─► sample-chaincode.sh run      (chaincode CCaaS qua systemd)
```

Chi tiết bước deploy: [deploy-guide.md](deploy-guide.md).
