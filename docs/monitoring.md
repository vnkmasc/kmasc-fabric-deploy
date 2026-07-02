# Giám sát & theo dõi hệ thống

Cheatsheet các lệnh để kiểm tra sức khoẻ mạng Fabric + ChainLaunch + chaincode.  
Chạy trên từng máy (Ubuntu 22.04). Giá trị mẫu: peer `:7000`, orderer `:9000/9100/9200`, chaincode `:9996`, ChainLaunch `:3100`.

---

## 1. systemd services

ChainLaunch tự sinh service tên `fabric-peer-<slug>` / `fabric-orderer-<slug>`. Chaincode là `kmasc-cc-cert`.

```bash
# Liệt kê tất cả service Fabric + chaincode
systemctl list-units 'fabric-*' 'kmasc-cc-*' --all

# Trạng thái nhanh (active/inactive) — không cần scroll
systemctl is-active 'fabric-peer-*' 'fabric-orderer-*' kmasc-cc-cert

# Chi tiết 1 service
systemctl status fabric-peer-peer0-org1msp --no-pager
systemctl status kmasc-cc-cert --no-pager

# Service nào đang enable (tự chạy khi reboot)?
systemctl list-unit-files 'fabric-*' 'kmasc-cc-*' | grep enabled
```

---

## 2. Logs

```bash
# Log live 1 service
journalctl -u fabric-peer-peer0-org1msp -f
journalctl -u kmasc-cc-cert -f

# 200 dòng gần nhất
journalctl -u fabric-orderer-orderer0-org1msp -n 200 --no-pager

# Lọc lỗi trong 1 giờ qua
journalctl -u fabric-peer-peer0-org1msp --since "1 hour ago" | grep -iE 'error|panic|fail'

# Log của tất cả orderer cùng lúc (theo dõi Raft)
journalctl -u 'fabric-orderer-*' -f

# Log ChainLaunch — tuỳ cách chạy (xem vm-setup.md mục "chạy nền"):
tail -f ~/chainlaunch.log        # nếu chạy bằng nohup
tmux attach -t chainlaunch       # nếu chạy trong tmux
```

---

## 3. Port & process

```bash
# Các port dịch vụ đang lắng nghe
ss -tlnp | grep -E ':(7000|9000|9100|9200|9996|3100)'

# Kiểm nhanh từng vai trò
ss -tlnp | grep :7000    # peer listen
ss -tlnp | grep :9996    # chaincode CCaaS (chỉ localhost)
ss -tlnp | grep :3100    # ChainLaunch

# Process Fabric đang chạy (kèm đường dẫn binary → xác nhận đang dùng custom build)
ps aux | grep -E 'peer node start|orderer' | grep -v grep

# Chaincode process
ps aux | grep cc-cert | grep -v grep
```

---

## 4. Tài nguyên hệ thống

```bash
# Disk — ledger nằm trong chainlaunch-data
df -h /
du -sh ~/chainlaunch-data 2>/dev/null            # tổng data ChainLaunch
du -sh ~/chainlaunch-data/peers/*/data 2>/dev/null   # ledger từng peer

# RAM / CPU
free -h
htop            # (nếu đã cài) — xem realtime

# Cảnh báo: ChainLaunch có disk-space monitor tự alert khi disk > 80%
```

---

## 5. ChainLaunch (API + UI)

```bash
# UI block explorer / trạng thái node:  http://<ip>:3100

# API — liệt kê node + trạng thái (basic auth admin/admin123)
curl -sf -u admin:admin123 http://localhost:3100/api/v1/nodes | python3 -m json.tool

# Chỉ lấy name + status
curl -sf -u admin:admin123 http://localhost:3100/api/v1/nodes \
  | python3 -c "import sys,json; [print(n['name'], n['status']) for n in json.load(sys.stdin)['items']]"

# ChainLaunch còn sống?
curl -sf -o /dev/null -w '%{http_code}\n' http://localhost:3100/api/v1/nodes -u admin:admin123
```

---

## 6. Chaincode (CCaaS) — liveness & ledger

```bash
# Service chaincode + port (dùng script có sẵn)
./scripts/sample-chaincode.sh status

# Liveness probe: query 1 hàm evaluate → ép peer dial vào chaincode :9996
# CertificateExists trả false (không lỗi) nếu chaincode sống & peer kết nối được
chainlaunch fabric query \
    --chaincode=cert --config=$HOME/chaincode/network-config.yaml \
    --channel mychannel --fcn CertificateExists -a 'PROBE' \
    --user=admin --mspID=Org1MSP

# Đọc thử 1 cert đã có
chainlaunch fabric query --chaincode=cert --config=$HOME/chaincode/network-config.yaml \
    --channel mychannel --fcn ReadCertificate -a 'C001' --user=admin --mspID=Org1MSP
```

> Nếu query lỗi `connection refused :9996` → chaincode service chưa chạy: `./scripts/sample-chaincode.sh run`.
> Nếu lỗi `namespace cert is not defined` → chaincode chưa commit (xem quy trình install).

---

## 7. Kết nối liên máy (vì dùng IP public)

Từ Máy 2/3, kiểm tra tới được peer/orderer của Máy 1:

```bash
# TCP tới được không (thay <ip-may1>)
nc -zv <ip-may1> 7000     # peer Org1
nc -zv <ip-may1> 9000     # orderer0
nc -zv <ip-may1> 9100     # orderer1
nc -zv <ip-may1> 9200     # orderer2

# Xem cert TLS server đang trả (kiểm SAN có đúng IP public không)
echo | openssl s_client -connect <ip-may1>:7000 2>/dev/null \
  | openssl x509 -noout -text | grep -A1 'Subject Alternative Name'
```

> Nếu `nc` fail → firewall VPC chưa mở port (xem [vm-setup.md](vm-setup.md)).
> Nếu SAN thiếu IP → cert sai, cần renew node với IP public trong DomainNames.

---

## 8. Raft / orderer

```bash
# Theo dõi bầu leader / consenter trong log orderer
journalctl -u 'fabric-orderer-*' --since "10 min ago" \
  | grep -iE 'raft|leader|elected|consenter'

# Quy tắc: 3 orderer → cần >= 2 sống để commit block (quorum).
# 1/3 sống = mất quorum = invoke (ghi) sẽ fail, query (đọc) vẫn OK.
```

---

## 9. Health-check nhanh (chạy 1 loạt)

```bash
echo "=== Services ===" ; systemctl is-active 'fabric-peer-*' 'fabric-orderer-*' kmasc-cc-cert
echo "=== Ports ===" ; ss -tlnp | grep -E ':(7000|9000|9100|9200|9996|3100)' | awk '{print $4}'
echo "=== ChainLaunch ===" ; curl -sf -o /dev/null -w 'API HTTP %{http_code}\n' -u admin:admin123 http://localhost:3100/api/v1/nodes
echo "=== Disk ===" ; df -h / | tail -1
```

---

## Bảng lỗi ↔ nơi kiểm tra

| Triệu chứng | Kiểm tra |
|---|---|
| Query fail `connection refused :9996` | mục 6 — chaincode service chết |
| Invoke fail `no orderers` | mục 8 — mất Raft quorum |
| Peer/orderer không tự lên sau reboot | mục 1 — service chưa `enable` |
| Máy khác không kết nối được | mục 7 — firewall / SAN cert |
| Query OK nhưng invoke chậm/fail | mục 8 — orderer, và mục 4 — tài nguyên |
| UI :3100 không vào được | mục 5 — ChainLaunch chết (không ảnh hưởng mạng đang chạy) |
