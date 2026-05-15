#!/bin/sh

# Проверяем, что событие касается именно нашего туннеля
[ "$system_name" == "Wireguard0" ] || exit 0

FWMARK="0x7117"
TABLE_ID="111"
INTERFACE="nwg0"

if [ "$change" == "link" ] && [ "$link" == "up" ]; then
    # 1. Тотальная очистка старых правил перед созданием новых (защита от дублей)
    while ip rule del fwmark $FWMARK 2>/dev/null; do true; done
    
    # 2. Создаем правило для перенаправления маркированного трафика (с жестким приоритетом)
    ip rule add fwmark $FWMARK table $TABLE_ID priority 1000
    
    # 3. Направляем таблицу в туннель
    ip route flush table $TABLE_ID
    ip route add default dev "$INTERFACE" table $TABLE_ID
    ip route flush cache
    
    logger "Rublock: WireGuard is UP. Routing rules injected."

elif [ "$change" == "link" ] && [ "$link" == "down" ]; then
    # 1. ГАРАНТИРОВАННОЕ УДАЛЕНИЕ ПРАВИЛ при отключении VPN
    # Цикл while удалит все дубликаты правил, если они накопились в ядре
    while ip rule del fwmark $FWMARK 2>/dev/null; do true; done
    
    # 2. Очищаем таблицу маршрутизации туннеля
    ip route flush table $TABLE_ID
    ip route flush cache
    
    logger "Rublock: WireGuard is DOWN. Routing rules cleared. Traffic falls back to ISP."
fi
