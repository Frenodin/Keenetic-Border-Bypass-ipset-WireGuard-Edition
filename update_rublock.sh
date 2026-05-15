#!/opt/bin/bash

# --- Конфигурация ---
LIST_URL="[https://antifilter.download/list/allyouneed.lst](https://antifilter.download/list/allyouneed.lst)"
TMP_FILE="/opt/tmp/rublock.txt"
RESTORE_FILE="/opt/tmp/rublock.restore"
SET_NAME="rublock"
INTERFACE="nwg0" # Имя интерфейса в ядре Linux (ip link show | grep nwg)

mkdir -p /opt/tmp

# Скачивание списка через туннель (защита от блокировки самого источника)
echo "Downloading list via $INTERFACE..."
curl -L --interface "$INTERFACE" "$LIST_URL" | grep -v ':' > "$TMP_FILE"

if [ ! -s "$TMP_FILE" ]; then
    echo "Ошибка: Файл пуст. Проверьте VPN подключение."
    exit 1
fi

# Формирование дампа для атомарной загрузки в ipset
echo "create $SET_NAME hash:net family inet hashsize 8192 maxelem 131072 -exist" > "$RESTORE_FILE"
echo "flush $SET_NAME" >> "$RESTORE_FILE"
awk -v set="$SET_NAME" '{print "add " set " " $1}' "$TMP_FILE" >> "$RESTORE_FILE"

# Загрузка в ядро
ipset restore < "$RESTORE_FILE"

rm -f "$TMP_FILE" "$RESTORE_FILE"
echo "Список $SET_NAME успешно обновлен."
