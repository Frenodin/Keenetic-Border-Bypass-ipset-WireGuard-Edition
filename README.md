# Keenetic Border Bypass ipset WireGuard Edition
Реализация селективной маршрутизации заблокированных ресурсов на роутерах Keenetic с использованием среды Entware, ipset, iptables и раздельного туннелирования.



Данный репозиторий содержит набор скриптов для настройки селективной маршрутизации на роутерах Keenetic с установленным Entware. Решение позволяет автоматически направлять заблокированный трафик через VPN-туннель WireGuard, сохраняя высокую производительность и гибкость настройки.

## Основные возможности
* **Автоматизация:** Списки заблокированных IP обновляются по расписанию.
* **Производительность:** Использование `ipset` хеш-таблицы в ядре Linux обеспечивает мгновенный поиск IP даже в огромных списках.
* **Гибридность:** Совместимость со штатными маршрутами Keenetic и DNS-маршрутизацией (снупингом) для сложных CDN Discord, Twitter.
* **Живучесть:** Автоматическое восстановление правил после перезагрузки роутера или переподключения VPN.

---

## Подготовка
Для работы системы необходимо:
1.  **Entware** на USB-накопителе.
2.  **WireGuard туннель**, настроенный в веб-интерфейсе например, под названием `CH`.
3.  Установленные пакеты:
    ```bash
    opkg update
    opkg install ipset iptables curl bash cron
    ```

## Описание скриптов

### 1. Обновление списков IP `/opt/bin/update_rublock.sh`
Этот скрипт скачивает агрегированные списки заблокированных подсетей и загружает их в оперативную память.

```bash
#!/opt/bin/bash

# --- Конфигурация ---
LIST_URL="[https://antifilter.download/list/allyouneed.lst](https://antifilter.download/list/allyouneed.lst)"
TMP_FILE="/opt/tmp/rublock.txt"
RESTORE_FILE="/opt/tmp/rublock.restore"
SET_NAME="rublock"
INTERFACE="nwg0" # Имя интерфейса в ядре Linux (проверьте через 'ip link show | grep nwg')

mkdir -p /opt/tmp

# Скачивание списка через туннель (защита от блокировки источника)
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
