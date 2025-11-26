#!/bin/bash
AP_IF="wlxa047d7605b5a"
INTERNET_IF="wlp0s20f3"
GATEWAY_IP="192.168.4.1"
IDU_IP="203.113.45.67"  # IP thật của idu.vn

# --- Flush old rules ---
iptables -F
iptables -t nat -F
iptables -X
iptables -t nat -X
echo 1 > /proc/sys/net/ipv4/ip_forward

# --- ipset for logged-in clients ---
ipset destroy logged_in 2>/dev/null
ipset create logged_in hash:ip

# ----------------------------------------------------
# A. BẢNG NAT (NAT Table)
# ----------------------------------------------------

# MASQUERADE: Cho phép client đã login ra Internet
iptables -t nat -A POSTROUTING -o $INTERNET_IF -m set --match-set logged_in src -j MASQUERADE

# Cho phép idu.vn và DNS ra ngoài (cần thiết cho dnsmasq/idu.vn)
iptables -t nat -A POSTROUTING -o $INTERNET_IF -d $IDU_IP -j MASQUERADE
iptables -t nat -A POSTROUTING -o $INTERNET_IF -p udp --dport 53 -j MASQUERADE

# 💥 REDIRECTION / CAPTIVE PORTAL (DNAT) 💥

# Chuyển hướng traffic HTTP/HTTPS của client CHƯA login đến PORTAL IP (192.168.4.1)
iptables -t nat -A PREROUTING -i $AP_IF -p tcp --dport 80 ! -m set --match-set logged_in src -j DNAT --to-destination $GATEWAY_IP:80
iptables -t nat -A PREROUTING -i $AP_IF -p tcp --dport 443 ! -m set --match-set logged_in src -j DNAT --to-destination $GATEWAY_IP:80 # HTTPS (443) cũng redirect về portal HTTP (80)

# ----------------------------------------------------
# B. BẢNG FILTER (Filter Table)
# ----------------------------------------------------

# 1. --- Allow all traffic for logged-in clients (Ưu tiên cao nhất) ---
iptables -I FORWARD -m set --match-set logged_in src -j ACCEPT
iptables -I FORWARD -m set --match-set logged_in dst -m state --state ESTABLISHED,RELATED -j ACCEPT

# 2. --- Allow traffic to idu.vn for everyone ---
iptables -A FORWARD -d $IDU_IP -j ACCEPT
iptables -A FORWARD -s $IDU_IP -m state --state ESTABLISHED,RELATED -j ACCEPT

# 3. --- Allow DNS query đến Gateway IP (dnsmasq) cho client CHƯA login ---
# Traffic này phải đi qua để dnsmasq có thể trả lời cho idu.vn hoặc cho chính nó.
iptables -A INPUT -i $AP_IF -p udp --dport 53 -d $GATEWAY_IP -j ACCEPT
iptables -A OUTPUT -o $AP_IF -p udp --sport 53 -s $GATEWAY_IP -j ACCEPT

# 4. --- Allow Access to Portal Server (HTTP/HTTPS) (cho client chưa login) ---
iptables -A FORWARD -i $AP_IF -d $GATEWAY_IP -p tcp --dport 80 -j ACCEPT
iptables -A FORWARD -o $AP_IF -s $GATEWAY_IP -p tcp --sport 80 -m state --state ESTABLISHED,RELATED -j ACCEPT

# 5. --- Drop all other unauthenticated traffic ---
# Traffic khác (HTTP, HTTPS, DNS ra ngoài, PING,...) của client chưa login bị DROP
iptables -A FORWARD -i $AP_IF ! -m set --match-set logged_in src -j REJECT

# --- Default policy ---
iptables -P FORWARD DROP

echo "=== iptables & ipset setup done ==="