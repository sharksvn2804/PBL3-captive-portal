#!/bin/bash
# ======== Cấu hình ========
AP_IF="wlxa047d7605b5a"       
GATEWAY_IP="192.168.4.1"
INTERNET_IF="wlp0s20f3"
IDU_IP="203.113.45.67"          # Thay bằng IP thật của idu.vn
DNSMASQ_CONF="/home/khanh/captive_lab/dnsmasq.conf"
HOSTAPD_CONF="/home/khanh/captive_lab/hostapd.conf"
PORTAL_SCRIPT="/home/khanh/captive_lab/portal.py"

# ======== 1️⃣ Tắt dịch vụ xung đột ========
echo "=== [1/6] Tắt dịch vụ xung đột ==="
sudo systemctl stop NetworkManager
sudo systemctl stop wpa_supplicant
sudo systemctl stop systemd-resolved 2>/dev/null
sudo systemctl disable systemd-resolved 2>/dev/null
sudo nmcli radio wifi off 2>/dev/null

# Fix resolv.conf để dnsmasq hoạt động
sudo rm -f /etc/resolv.conf
sudo touch /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf

# ======== 2️⃣ Cấu hình IP cho AP ========
echo "=== [2/6] Cấu hình IP AP ==="
sudo ip link set $AP_IF down
sudo ip addr flush dev $AP_IF
sudo ip addr add $GATEWAY_IP/24 dev $AP_IF
sudo ip link set $AP_IF up

# ======== 3️⃣ Bật IP forwarding ========
echo "=== [3/6] Bật IP forwarding ==="
sudo sysctl -w net.ipv4.ip_forward=1

# ======== 4️⃣ iptables & ipset ========
echo "=== [4/6] Thiết lập iptables & ipset ==="
# Đảm bảo bạn đã thay thế nội dung file iptables.sh bằng phiên bản mới
sudo bash /home/khanh/captive_lab/iptables.sh

# ======== 5️⃣ Chạy hostapd + dnsmasq + portal ========
echo "=== [5/6] Chạy hostapd + dnsmasq + portal Python ==="
sudo pkill hostapd 2>/dev/null
sudo pkill dnsmasq 2>/dev/null
sudo pkill -f portal.py 2>/dev/null
sleep 1

echo "Khởi động hostapd..."
sudo bash -c "hostapd $HOSTAPD_CONF > hostapd.log 2>&1" &
HOSTAPD_PID=$!
sleep 3

echo "Khởi động dnsmasq..."
sudo bash -c "dnsmasq --conf-file=$DNSMASQ_CONF --no-daemon > dnsmasq.log 2>&1" &
DNSMASQ_PID=$!
sleep 2

echo "Khởi động Portal Flask..."
sudo bash -c "python3 $PORTAL_SCRIPT > portal.log 2>&1" &
PORTAL_PID=$!
sleep 2

echo ""
echo "╔════════════════════════════════════════╗"
echo "║  CAPTIVE PORTAL STARTED SUCCESSFULLY   ║"
echo "╚════════════════════════════════════════╝"
echo "📶 SSID: PBL3_GROUP1_JOBAPPJS"
echo "🌐 Portal URL: http://$GATEWAY_IP"
echo ""
echo "📝 Logs: hostapd.log, dnsmasq.log, portal.log"
echo ""

# ======== 6️⃣ Trap Ctrl+C ========
trap "echo 'Stopping all services...'; sudo kill $HOSTAPD_PID $DNSMASQ_PID $PORTAL_PID; exit" INT TERM

# Giữ script chạy
wait