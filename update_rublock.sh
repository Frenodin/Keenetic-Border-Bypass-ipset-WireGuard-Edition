#!/opt/bin/bash

# Настройки
LIST_URL="https://antifilter.download/list/allyouneed.lst"
# Используем RAM-диск KeenOS для снижения I/O на флешку
TMP_FILE="/tmp/rublock.txt"
RESTORE_FILE="/tmp/rublock.restore"
SET_NAME="rublock"
TMP_SET="${SET_NAME}_tmp"
INTERFACE="nwg0"

# Скачиваем список с жесткими таймаутами (10 сек коннект, 60 сек на всю загрузку)
echo "Downloading list via $INTERFACE..."
curl -L --interface "$INTERFACE" --connect-timeout 10 --max-time 60 -s "$LIST_URL" > "$TMP_FILE"

# Проверка: существует ли файл и больше ли он 0 байт
if [ ! -s "$TMP_FILE" ]; then
    logger -t Rublock "Error: Downloaded list is empty or failed. Check VPN $INTERFACE."
    rm -f "$TMP_FILE"
    exit 1
fi

# Убеждаемся, что основной список существует (на случай первого запуска)
echo "create $SET_NAME hash:net family inet hashsize 8192 maxelem 131072 -exist" > "$RESTORE_FILE"

# Создаем временный список и очищаем его (если остался от прошлого сбоя)
echo "create $TMP_SET hash:net family inet hashsize 8192 maxelem 131072 -exist" >> "$RESTORE_FILE"
echo "flush $TMP_SET" >> "$RESTORE_FILE"

# Парсим скачанный файл (отсекая IPv6-адреса, если вдруг проскочат, прямо через awk для скорости)
awk -v set="$TMP_SET" '!/:/ {print "add " set " " $1}' "$TMP_FILE" >> "$RESTORE_FILE"

# Добавляем кастомные IP, если файл есть
if [ -f "/opt/etc/my_custom_ips.txt" ]; then
    awk -v set="$TMP_SET" '!/:/ {print "add " set " " $1}' /opt/etc/my_custom_ips.txt >> "$RESTORE_FILE"
fi

# Атомарно подменяем старый список новым и уничтожаем временный
echo "swap $SET_NAME $TMP_SET" >> "$RESTORE_FILE"
echo "destroy $TMP_SET" >> "$RESTORE_FILE"

# Загружаем правила в ядро
ipset restore < "$RESTORE_FILE"

logger -t Rublock "Success! ipset $SET_NAME updated with Zero-Downtime."

# Очистка RAM
rm -f "$TMP_FILE" "$RESTORE_FILE"
