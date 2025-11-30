#!/bin/bash

WL_IF="wlxa047d7605b5a"
AP_IP="192.168.4.1"
INET_IF="wlp0s20f3"
PORTAL_PORT=8080
SUBNET="192.168.4.0/24"
HOSTAPD_CONF="/home/khanh/captive_lab/hostapd.conf"
DNSMASQ_CONF="/home/khanh/captive_lab/dnsmasq.conf"
PORTAL_PY="/home/khanh/captive_lab/portal.py"

# Whitelist domain
WHITELIST_DOMAIN="idu.vn"

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

# ==== AUTO-RESOLVE DOMAIN → IP WHITELIST ====
echo "Resolving IPs for $WHITELIST_DOMAIN ..."
IP_LIST=$(dig +short $WHITELIST_DOMAIN)

for ip in $IP_LIST; do
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Whitelisting IP: $ip"
        sudo ipset add whitelist $ip
    fi
done

# Flush iptables
sudo iptables -F
sudo iptables -t nat -F

# NAT internet
sudo iptables -t nat -A POSTROUTING -s $SUBNET -o $INET_IF -j MASQUERADE

# Allow established
sudo iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# ===== CLIENT ĐÃ LOGIN =====
# Allow whitelist IPs
sudo iptables -A FORWARD -i $WL_IF \
     -m set --match-set logged_in src \
     -m set --match-set whitelist dst \
     -j ACCEPT

# Allow whitelist DOMAIN via HTTP (Host header)
sudo iptables -A FORWARD -i $WL_IF -p tcp --dport 80 \
     -m set --match-set logged_in src \
     -m string --string "$WHITELIST_DOMAIN" --algo bm \
     -j ACCEPT

# Chặn ngay tất cả trang khác (TCP/UDP)
sudo iptables -A FORWARD -i $WL_IF \
     -m set --match-set logged_in src \
     -p tcp -j REJECT --reject-with tcp-reset

sudo iptables -A FORWARD -i $WL_IF \
     -m set --match-set logged_in src \
     -p udp -j REJECT --reject-with icmp-port-unreachable

# ===== CLIENT CHƯA LOGIN =====
# Block HTTPS immediately
sudo iptables -A FORWARD -i $WL_IF -p tcp --dport 443 \
     -m set ! --match-set logged_in src \
     -j REJECT --reject-with tcp-reset

# Redirect HTTP → portal
sudo iptables -t nat -A PREROUTING -i $WL_IF -p tcp --dport 80 \
     -m set ! --match-set logged_in src \
     -j REDIRECT --to-port $PORTAL_PORT

# Open portal + DNS
sudo iptables -A INPUT -i $WL_IF -p tcp --dport $PORTAL_PORT -j ACCEPT
sudo iptables -A INPUT -i $WL_IF -p udp --dport 53 -j ACCEPT

# Start services
sudo hostapd $HOSTAPD_CONF > hostapd.log 2>&1 &
sleep 1
sudo dnsmasq --conf-file=$DNSMASQ_CONF > dnsmasq.log 2>&1 &
sleep 1
sudo python3 $PORTAL_PY > portal.log 2>&1 &

echo "Captive Portal Running!"
echo "Whitelisted domain: $WHITELIST_DOMAIN"
echo "Whitelisted IPs: $IP_LIST"
wait
