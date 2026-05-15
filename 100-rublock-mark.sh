#!/bin/sh

# Игнорируем IPv6
[ "$type" == "ip6tables" ] && exit 0

SET_NAME="rublock"
FWMARK="0x7117"
INTERFACE="nwg0"

# Гарантируем наличие сета
ipset create $SET_NAME hash:net family inet hashsize 8192 maxelem 131072 -exist

# Маркировка трафика из локальной сети к заблокированным IP
iptables -w -t mangle -C PREROUTING -m set --match-set $SET_NAME dst -j MARK --set-mark $FWMARK 2>/dev/null || \
iptables -w -t mangle -A PREROUTING -m set --match-set $SET_NAME dst -j MARK --set-mark $FWMARK

# Включаем NAT для этого трафика на выходе из VPN
iptables -w -t nat -C POSTROUTING -o "$INTERFACE" -m mark --mark $FWMARK -j MASQUERADE 2>/dev/null || \
iptables -w -t nat -A POSTROUTING -o "$INTERFACE" -m mark --mark $FWMARK -j MASQUERADE
