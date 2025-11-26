#!/bin/bash
# ======== STOP CAPTIVE PORTAL ========
AP_IF="wlxa047d7605b5a"
LOGIN_FILE="/home/khanh/captive_lab/logged_in.json"

echo "=== Stopping Captive Portal ==="

# 1️⃣ Kill tất cả tiến trình captive
sudo pkill hostapd 2>/dev/null || true
sudo pkill dnsmasq 2>/dev/null || true
sudo pkill -f portal.py 2>/dev/null || true

# 2️⃣ Flush iptables và ipset
echo "Flushing iptables..."
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -X
sudo iptables -t nat -X
sudo iptables -P FORWARD ACCEPT

echo "Destroying ipset..."
sudo ipset destroy logged_in 2>/dev/null || true

# 3️⃣ Bring down AP interface
echo "Bringing down AP interface $AP_IF..."
sudo ip link set $AP_IF down || true
sudo ip addr flush dev $AP_IF || true

# 4️⃣ Restore system services
echo "Restoring network services..."
sudo systemctl start NetworkManager
sudo systemctl start wpa_supplicant
sudo systemctl enable systemd-resolved
sudo systemctl restart systemd-resolved
sudo systemctl start systemd-resolved 2>/dev/null || true

# Fix resolv.conf
sudo rm -f /etc/resolv.conf
sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf

# 5️⃣ Reset login DB
echo "Resetting login database..."
sudo rm -f $LOGIN_FILE
echo '{}' | sudo tee $LOGIN_FILE > /dev/null

echo "✅ Captive portal stopped and environment restored."
