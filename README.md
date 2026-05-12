# Keenetic Border Bypass: ipset WireGuard Edition

[![KeenOS](https://img.shields.io/badge/Router-Keenetic-blue)](https://keenetic.link/)
[![Entware](https://img.shields.io/badge/Environment-Entware-orange)](https://pkg.entware.net/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Реализация селективной маршрутизации заблокированных ресурсов на роутерах Keenetic. Решение использует связку **Entware**, **ipset**, **iptables** и раздельное туннелирование через **WireGuard**.


## Основные возможности

* **Автоматизация:** Списки заблокированных IP-адресов обновляются автоматически по расписанию через `cron`.
* **Высокая производительность:** Использование `ipset` хеш-таблицы в ядре Linux гарантирует мгновенный поиск IP даже при списках в 100 000+ записей без нагрузки на CPU.
* **Гибридность:** Полная совместимость со штатными функциями KeenOS DNS-снупинг/маршрутизация доменов для сервисов с динамическими IP Discord, Twitter, Instagram.
* **Живучесть:** Скрипты-хуки автоматически восстанавливают правила после перезагрузки роутера или переподключения VPN-туннеля.


## Подготовка

Для работы системы необходимо наличие:
1.  **Entware** на USB-накопителе установленный по официальной инструкции.
2.  **WireGuard туннель**, настроенный и активный например, с именем `CH`.
3.  Установленные пакеты:
    ```bash
    opkg update
    opkg install ipset iptables curl bash cron
    ```

### 1. Обновление списков IP 
**Путь:** `nano /opt/bin/update_rublock.sh`  
Скачивает агрегированные списки подсетей и атомарно обновляет таблицу в памяти роутера.

```bash
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

```

### 2. Маркировка пакетов

**Путь:** `nano /opt/etc/ndm/netfilter.d/100-rublock-mark.sh`

Хук **Netfilter**, который срабатывает при обновлении сетевого экрана. Он "метит" нужный трафик.

```bash
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

```

### 3. Управление маршрутизацией

**Путь:** `nano /opt/etc/ndm/ifstatechanged.d/100-rublock-route.sh`

Создает выделенную таблицу маршрутизации при поднятии интерфейса.

```bash
#!/bin/sh

# Wireguard0 — системное имя в Keenetic
[ "$system_name" == "Wireguard0" ] || exit 0

FWMARK="0x7117"
TABLE_ID="111"
INTERFACE="nwg0" # Системное имя в ядре

if [ "$change" == "link" ] && [ "$link" == "up" ]; then
    ip rule add fwmark $FWMARK table $TABLE_ID 2>/dev/null
    
    ip route flush table $TABLE_ID
    ip route add default dev "$INTERFACE" table $TABLE_ID
    ip route flush cache
elif [ "$change" == "link" ] && [ "$link" == "down" ]; then
    ip rule del fwmark $FWMARK table $TABLE_ID 2>/dev/null
    ip route flush table $TABLE_ID
fi

```

## Установка

1. **Создайте файлы** через SSH и вставьте соответствующий код.
2. **Выдайте права на исполнение:**
```bash
chmod +x /opt/bin/update_rublock.sh
chmod +x /opt/etc/ndm/netfilter.d/100-rublock-mark.sh
chmod +x /opt/etc/ndm/ifstatechanged.d/100-rublock-route.sh

```


3. **Запустите первичную загрузку:**
```bash
/opt/bin/update_rublock.sh

```


4. **Настройте расписание Cron:**
Добавьте строку в `/opt/etc/crontab`:
```text
0 4 * * * root /opt/bin/update_rublock.sh

```


Перезапустите планировщик: `/opt/etc/init.d/S10cron restart`.

5. **Перезагрузите WireGuard** выключите и включите в меню "Другие подключения".

## Диагностика

* **Наполнение списка:** `ipset list rublock | head -n 20`
* **Работа маркировки:** `iptables -t mangle -L PREROUTING -v -n | grep rublock`
* **Правила маршрутизации:** `ip rule show | grep 7117`

## Важные дополнения

Для обхода блокировок сервисов со сложными CDN Discord, Twitter, Instagram рекомендуется использовать штатную функцию **"Маршруты DNS"** в интерфейсе Keenetic:

1. **Сетевые правила** -> **Маршрутизация** -> **Маршруты DNS**.
2. Добавьте домены например, `discord.com`, `x.com`.
3. Выберите ваш VPN-интерфейс.


---

```
