#!/opt/bin/bash

# Настройки
LIST_URL="https://antifilter.download/list/allyouneed.lst"
TMP_FILE="/opt/tmp/rublock.txt"
RESTORE_FILE="/opt/tmp/rublock.restore"
SET_NAME="rublock"
INTERFACE="nwg0" # Интерфейс ядра для Швейцарии

# Создаем временную директорию, если её нет
mkdir -p /opt/tmp

# Скачиваем список (без -s, чтобы видеть ошибки в логах)
echo "Downloading list via $INTERFACE..."
curl -L --interface "$INTERFACE" "$LIST_URL" | grep -v ':' > "$TMP_FILE"

if [ ! -s "$TMP_FILE" ]; then
    echo "Error: Downloaded file is empty. Check your VPN connection."
    exit 1
fi

# Формируем файл для ipset restore
echo "create $SET_NAME hash:net family inet hashsize 8192 maxelem 131072 -exist" > "$RESTORE_FILE"
echo "flush $SET_NAME" >> "$RESTORE_FILE"
awk -v set="$SET_NAME" '{print "add " set " " $1}' "$TMP_FILE" >> "$RESTORE_FILE"

# Добавляем личные адреса
if [ -f "/opt/etc/my_custom_ips.txt" ]; then
    awk -v set="$SET_NAME" '{print "add " set " " $1}' /opt/etc/my_custom_ips.txt >> "$RESTORE_FILE"
fi

# Применяем атомарно
ipset restore < "$RESTORE_FILE"

echo "Success! ipset $SET_NAME updated."
rm -f "$TMP_FILE" "$RESTORE_FILE"
