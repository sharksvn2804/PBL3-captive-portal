#!/bin/bash

WL_IF="wlxa047d7605b5a"
AP_IP="192.168.4.1"
INET_IF="wlp0s20f3"
PORTAL_PORT=8080
SUBNET="192.168.4.0/24"
HOSTAPD_CONF="/home/khanh/captive_lab/hostapd.conf"
DNSMASQ_CONF="/home/khanh/captive_lab/dnsmasq.conf"
PORTAL_PY="/home/khanh/captive_lab/portal.py"

# Whitelist IP trực tiếp của idu.vn
WHITELIST_IPS=("172.67.183.53" "104.21.51.174")

cleanup() {
    sudo pkill hostapd
    sudo pkill dnsmasq
    sudo pkill -f portal.py
    sudo iptables -F
    sudo iptables -t nat -F
    sudo ipset destroy logged_in 2>/dev/null
    sudo ipset destroy whitelist 2>/dev/null
}
trap cleanup INT TERM EXIT

# Setup AP
sudo ip link set $WL_IF down
sudo ip addr flush dev $WL_IF
sudo ip addr add $AP_IP/24 dev $WL_IF
sudo ip link set $WL_IF up
sudo sysctl -w net.ipv4.ip_forward=1

# Setup ipsets
sudo ipset destroy logged_in 2>/dev/null
sudo ipset create logged_in hash:ip
sudo ipset destroy whitelist 2>/dev/null
sudo ipset create whitelist hash:ip

# Add IP trực tiếp vào whitelist
for ip in "${WHITELIST_IPS[@]}"; do
    sudo ipset add whitelist $ip
done

# Flush iptables
sudo iptables -F
sudo iptables -t nat -F

# ==== NAT INTERNET cho client đã login ====
sudo iptables -t nat -A POSTROUTING -s $SUBNET -o $INET_IF -j MASQUERADE
sudo iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# ==== CHO PHÉP chỉ ra whitelist site khi đã login ====
sudo iptables -A FORWARD -i $WL_IF -m set --match-set logged_in src \
    -m set --match-set whitelist dst -j ACCEPT

# ==== BLOCK tất cả site khác của client đã login ====
sudo iptables -A FORWARD -i $WL_IF -m set --match-set logged_in src \
    -j REJECT --reject-with icmp-host-prohibited

# ==== Chặn HTTPS cho client chưa login ====
sudo iptables -A FORWARD -i $WL_IF -p tcp --dport 443 \
    -m set ! --match-set logged_in src \
    -j REJECT --reject-with tcp-reset

# ==== Redirect HTTP → PORTAL khi chưa login ====
sudo iptables -t nat -A PREROUTING -i $WL_IF -p tcp --dport 80 \
    -m set ! --match-set logged_in src \
    -j REDIRECT --to-port $PORTAL_PORT

# Mở port portal và DNS
sudo iptables -A INPUT -i $WL_IF -p tcp --dport $PORTAL_PORT -j ACCEPT
sudo iptables -A INPUT -i $WL_IF -p udp --dport 53 -j ACCEPT

# Start services
sudo hostapd $HOSTAPD_CONF > hostapd.log 2>&1 &
sleep 1
sudo dnsmasq --conf-file=$DNSMASQ_CONF > dnsmasq.log 2>&1 &
sleep 1
sudo python3 $PORTAL_PY > portal.log 2>&1 &

echo "Captive Portal Running! Only idu.vn allowed after login."
wait
