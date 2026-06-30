# Quy trình triển khai đầy đủ

> Mạng: 3 máy / 3 org (Org1MSP, Org2MSP, Org3MSP), IP public. Orderer (3, Raft) nằm ở Org1.
> Chaincode: `cert` (Go, CCaaS). Channel: `mychannel`.

---

## 0. Chuẩn bị mỗi máy (Ubuntu 22.04)

```bash
# Gói cơ bản
sudo apt-get update && sudo apt-get install -y curl git python3

# Clone repo này
git clone <repo-url> kmasc-fabric-deploy
cd kmasc-fabric-deploy

# Cài ChainLaunch (pin v0.5.0-beta.2) + custom Fabric binaries (vnkmasc/fabric)
export GITHUB_TOKEN=ghp_...          # repo vnkmasc/fabric là private
./scripts/setup-fabric-binaries.sh setup
source ~/.bashrc
./scripts/setup-fabric-binaries.sh run    # ChainLaunch chạy ở :3100
```

> Version cố định: ChainLaunch `v0.5.0-beta.2`, Fabric fork `v3.1.1-mkv` (slot UI `3.1.3`). Xem [versions.md](versions.md).
> `setup-fabric-binaries.sh check` để kiểm tra version + cảnh báo nếu lệch pin.

---

## 1. Dựng mạng qua ChainLaunch UI (http://localhost:3100)

1. Tạo **Org** trên mỗi máy: Org1MSP / Org2MSP / Org3MSP.
2. Máy 1: tạo **1 peer + 3 orderer** (để version mặc định `3.1.3` → dùng custom binary).
3. Máy 2, 3: tạo **1 peer** mỗi máy.
4. **External Endpoint** mỗi node = **IP public** của máy đó (không để localhost).
5. Tạo **channel** `mychannel`, cho cả 3 org join. Set anchor peer mỗi org.

> Vì dùng IP public: đảm bảo SAN của TLS cert chứa IP public, và firewall mở port peer (7000) + orderer (9000–9200) giữa các máy. Xem `research/do-an-truong/notes/01-topology.md`.

---

## 2. Control plane — install chaincode (qua ChainLaunch CLI)

Lấy network config (mỗi máy, đổi MSP_ID tương ứng):
```bash
chainlaunch fabric network-config pull \
    --network=mychannel --msp-id=Org1MSP \
    --url="http://localhost:3100/api/v1" \
    --username=admin --password=admin123 \
    --output=$HOME/chaincode/network-config.yaml
```

Install + approve (+ commit). Lifecycle policy MAJORITY của 3 org = cần **2/3** org approve thì commit chạy. Chạy lần lượt, máy commit là máy làm đủ majority:
```bash
chainlaunch fabric install --local \
    --config=$HOME/chaincode/network-config.yaml \
    --channel=mychannel \
    --chaincode=cert \
    -o Org1MSP -u admin \
    --policy="OR('Org1MSP.member','Org2MSP.member','Org3MSP.member')" \
    --chaincodeAddress=localhost:9996 \
    --envFile=$HOME/chaincode/.env
```
→ Sinh `$HOME/chaincode/.env` chứa `CORE_CHAINCODE_ID_NAME=<packageID>`.

---

## 3. Data plane — chạy chaincode server (systemd)

```bash
# Trỏ ENV_FILE tới .env vừa sinh (nếu khác default)
export ENV_FILE=$HOME/chaincode/.env

./scripts/sample-chaincode.sh install-bin    # copy binary → /opt/kmasc/cc-cert
./scripts/sample-chaincode.sh run            # sinh systemd unit, enable + start
./scripts/sample-chaincode.sh status         # kiểm service + port 9996
```

Service tên `kmasc-cc-cert`, tự khởi động lại khi VM reboot (đã `enable`).

---

## 4. Khởi tạo & test

```bash
chainlaunch fabric invoke --chaincode=cert --config=$HOME/chaincode/network-config.yaml \
    --channel mychannel --fcn IssueCertificate --user=admin --mspID=Org1MSP \
    -a '{"cert_id":"C001","serial_number":"SN001","registration_number":"RG001"}'

chainlaunch fabric query --chaincode=cert --config=$HOME/chaincode/network-config.yaml \
    --channel mychannel --fcn ReadCertificate --user=admin --mspID=Org1MSP -a 'C001'
```

> Hàm chaincode có sẵn: `IssueCertificate`, `ReadCertificate`, `UpdateCertificate`, `CertificateExists`, `IssueCertificateBatch`, `IssueEDiplomaBatch`, `ReadEDiplomaBatch`, `ReadCertificateBatch`.

---

## Vận hành

| Tình huống | Làm gì |
|---|---|
| VM reboot | Tự phục hồi: ChainLaunch + peer/orderer (systemd) + chaincode (`kmasc-cc-cert`) đều auto-start |
| Sửa logic chaincode | `build-chaincode.sh` → copy binary mới lên máy → `sample-chaincode.sh reload`. KHÔNG cần install lại |
| Nâng version chaincode (governance) | `chainlaunch fabric install` lại (sequence mới) → `sample-chaincode.sh reload` |
| Chaincode crash | `sample-chaincode.sh status` / `logs`; service tự restart sau 10s |

---

## Checklist nhanh (mỗi máy)

```
[ ] setup-fabric-binaries.sh setup + run   (ChainLaunch + custom binaries)
[ ] UI: tạo org, node, channel, anchor peer (External Endpoint = IP public)
[ ] network-config pull
[ ] chainlaunch fabric install (→ .env có packageID)
[ ] sample-chaincode.sh install-bin
[ ] sample-chaincode.sh run
[ ] invoke IssueCertificate / query ReadCertificate
```
