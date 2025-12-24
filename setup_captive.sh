#!/bin/bash

WL_IF="wlxa047d7605b5a"
AP_IP="192.168.4.1"
INET_IF="wlp0s20f3"
PORTAL_PORT=8080
SUBNET="192.168.4.0/24"
HOSTAPD_CONF="/home/khanh/PBL3_duphong/hostapd.conf"
DNSMASQ_CONF="/home/khanh/PBL3_duphong/dnsmasq.conf"
PORTAL_PY="/home/khanh/PBL3_duphong/portal.py"

ADMIN_MAC="e0:dc:ff:d3:18:63"
WHITELIST_DOMAIN="idu.vn"
FALLBACK_IPS="104.21.51.174 172.67.183.53"

cleanup() {
    sudo pkill hostapd
    sudo pkill dnsmasq
    sudo pkill -f portal.py
    sudo pkill -f "dynamic_update_whitelist"
    sudo iptables -F
    sudo iptables -t nat -F
    sudo ipset destroy logged_in 2>/dev/null
    sudo ipset destroy whitelist 2>/dev/null
}
trap cleanup INT TERM EXIT

# ========== RESET DATABASE ==========
echo "=== Resetting login database ==="
sudo rm -f /home/khanh/PBL3_duphong/logged_in.json
sudo bash -c 'echo "{}" > /home/khanh/PBL3_duphong/logged_in.json'
echo "Database cleared"

# ========== SETUP ACCESS POINT ==========
echo "=== Setting up Access Point ==="
sudo ip link set $WL_IF down
sudo ip addr flush dev $WL_IF
sudo ip addr add $AP_IP/24 dev $WL_IF
sudo ip link set $WL_IF up
sudo sysctl -w net.ipv4.ip_forward=1

# ========== SETUP IPSETS ==========
echo "=== Creating IP sets ==="
sudo ipset destroy logged_in 2>/dev/null
sudo ipset create logged_in hash:ip
sudo ipset destroy whitelist 2>/dev/null
sudo ipset create whitelist hash:ip

# ========== RESOLVE WHITELIST DOMAIN ==========
echo "=== Resolving whitelist domain ==="

resolve_domain() {
    local domain=$1
    local retry_count=0
    local max_retries=3
    local ip_list=""
    
    while [ -z "$ip_list" ] && [ $retry_count -lt $max_retries ]; do
        echo "Resolving IPs for $domain ... (attempt $((retry_count + 1))/$max_retries)"
        ip_list=$(dig +short $domain 2>/dev/null)
        
        if [ -z "$ip_list" ]; then
            if [ $retry_count -lt $((max_retries - 1)) ]; then
                echo "DNS resolution failed, retrying in 2 seconds..."
                sleep 2
            fi
            retry_count=$((retry_count + 1))
        fi
    done
    
    if [ -z "$ip_list" ]; then
        echo "DNS resolution failed, using fallback IPs"
        ip_list=$FALLBACK_IPS
    fi
    
    echo "$ip_list"
}

IP_LIST=$(resolve_domain "$WHITELIST_DOMAIN")

echo "=== Adding IPs to whitelist ==="
for ip in $IP_LIST; do
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Whitelisting IP: $ip"
        sudo ipset add whitelist $ip 2>/dev/null
    fi
done

# ========== FLUSH IPTABLES ==========
echo "=== Flushing iptables ==="
sudo iptables -F
sudo iptables -t nat -F

# ========== NAT & ESTABLISHED CONNECTIONS ==========
sudo iptables -t nat -A POSTROUTING -s $SUBNET -o $INET_IF -j MASQUERADE
sudo iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# ========== ADMIN FULL INTERNET ACCESS (PRIORITY 1) ==========
echo "=== Granting admin full internet access (MAC: $ADMIN_MAC) ==="

# Allow tất cả traffic (vào + ra)
sudo iptables -I FORWARD 1 -m mac --mac-source $ADMIN_MAC -j ACCEPT

# Admin: Bypass NAT redirect & HTTP redirect
sudo iptables -t nat -I PREROUTING 1 -m mac --mac-source $ADMIN_MAC -j RETURN

# ========== CLIENT CHƯA LOGIN - CHẶN NHANH ==========
echo "=== Setting up FAST BLOCK for NOT LOGGED IN ==="

# Redirect HTTP (port 80) về portal (cho user chưa login)
sudo iptables -t nat -A PREROUTING -i $WL_IF -p tcp --dport 80 \
    -m set ! --match-set logged_in src \
    -j REDIRECT --to-port $PORTAL_PORT

# Allow DNS (port 53) cho chưa login
sudo iptables -A FORWARD -i $WL_IF -p udp --dport 53 \
    -m set ! --match-set logged_in src \
    -j ACCEPT

# Chặn TẤT CẢ traffic khác từ chưa login
sudo iptables -A FORWARD -i $WL_IF \
    -m set ! --match-set logged_in src \
    -j REJECT --reject-with icmp-host-unreachable

# ========== CLIENT ĐÃ LOGIN - ALLOW IDU.VN ONLY ==========
echo "=== Setting up ALLOW for LOGGED IN users (idu.vn only) ==="

# Cho phép DNS
sudo iptables -A FORWARD -i $WL_IF -p udp --dport 53 \
    -m set --match-set logged_in src \
    -j ACCEPT

# Cho phép whitelist IPs (idu.vn)
sudo iptables -A FORWARD -i $WL_IF \
    -m set --match-set logged_in src \
    -m set --match-set whitelist dst \
    -j ACCEPT

# Cho phép HTTP có Host header (backup CDN)
sudo iptables -A FORWARD -i $WL_IF -p tcp --dport 80 \
    -m set --match-set logged_in src \
    -m string --string "Host: $WHITELIST_DOMAIN" --algo bm \
    -j ACCEPT

# CHẶN TẤT CẢ TRAFFIC KHÁC của logged_in
sudo iptables -A FORWARD -i $WL_IF \
    -m set --match-set logged_in src \
    -j REJECT --reject-with icmp-host-unreachable

# ========== INPUT RULES ==========
sudo iptables -A INPUT -i $WL_IF -p tcp --dport $PORTAL_PORT -j ACCEPT
sudo iptables -A INPUT -i $WL_IF -p udp --dport 53 -j ACCEPT

# ========== START SERVICES ==========
echo "=== Starting services ==="
sudo hostapd $HOSTAPD_CONF > hostapd.log 2>&1 &
sleep 2

sudo dnsmasq --conf-file=$DNSMASQ_CONF > dnsmasq.log 2>&1 &
sleep 2

sudo python3 $PORTAL_PY > portal.log 2>&1 &
sleep 1

# ========== DYNAMIC WHITELIST UPDATE ==========
dynamic_update_whitelist() {
    while true; do
        sleep 300
        NEW_IPS=$(dig +short $WHITELIST_DOMAIN 2>/dev/null)
        
        if [ -n "$NEW_IPS" ]; then
            for ip in $NEW_IPS; do
                if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    if ! sudo ipset test whitelist $ip 2>/dev/null; then
                        sudo ipset add whitelist $ip 2>/dev/null
                    fi
                fi
            done
        fi
    done
}

dynamic_update_whitelist > whitelist_update.log 2>&1 &

echo ""
echo "========================================="
echo "✓ Captive Portal Running!"
echo "========================================="
echo "Admin MAC: $ADMIN_MAC"
echo "  → FULL INTERNET ACCESS (no login)"
echo "Other users:"
echo "  → Must login to access idu.vn"
echo "========================================="
echo ""

wait
