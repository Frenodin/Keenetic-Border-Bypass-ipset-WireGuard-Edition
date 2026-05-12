# Keenetic Border Bypass ipset WireGuard Edition
Реализация селективной маршрутизации заблокированных ресурсов на роутерах Keenetic с использованием среды Entware, ipset, iptables и раздельного туннелирования.

```markdown
# Keenetic Border Bypass: Гибридная маршрутизация (ipset + WireGuard)

Данный репозиторий содержит набор скриптов для настройки селективной маршрутизации на роутерах Keenetic (с установленным Entware). Решение позволяет автоматически направлять заблокированный трафик через VPN-туннель (WireGuard), сохраняя высокую производительность и гибкость настройки.

## 🚀 Основные возможности
* **Автоматизация:** Списки заблокированных IP обновляются по расписанию.
* **Производительность:** Использование `ipset` (хеш-таблицы в ядре Linux) обеспечивает мгновенный поиск IP даже в огромных списках.
* **Гибридность:** Совместимость со штатными маршрутами Keenetic и DNS-маршрутизацией (снупингом) для сложных CDN (Discord, Twitter).
* **Живучесть:** Автоматическое восстановление правил после перезагрузки роутера или переподключения VPN.

---

## 🛠 Подготовка
Для работы системы необходимо:
1.  **Entware** на USB-накопителе.
2.  **WireGuard туннель**, настроенный в веб-интерфейсе (например, под названием `CH`).
3.  Установленные пакеты:
    ```bash
    opkg update
    opkg install ipset iptables curl bash cron
    ```

---

## 📂 Описание скриптов

### 1. Обновление списков IP (`/opt/bin/update_rublock.sh`)
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

```

### 2. Маркировка пакетов (`/opt/etc/ndm/netfilter.d/100-rublock-mark.sh`)

Хук Netfilter, который срабатывает при обновлении сетевого экрана KeenOS. Он "метит" нужные пакеты.

```bash
#!/bin/sh

# Игнорируем IPv6
[ "$type" == "ip6tables" ] && exit 0

SET_NAME="rublock"
FWMARK="0x7117"
INTERFACE="nwg0"

# Гарантируем создание сета (предотвращает ошибки iptables)
ipset create $SET_NAME hash:net family inet hashsize 8192 maxelem 131072 -exist

# Маркировка трафика из локальной сети к заблокированным IP
iptables -w -t mangle -C PREROUTING -m set --match-set $SET_NAME dst -j MARK --set-mark $FWMARK 2>/dev/null || \
iptables -w -t mangle -A PREROUTING -m set --match-set $SET_NAME dst -j MARK --set-mark $FWMARK

# Включаем NAT (Masquerade) для этого трафика на выходе из VPN
iptables -w -t nat -C POSTROUTING -o "$INTERFACE" -m mark --mark $FWMARK -j MASQUERADE 2>/dev/null || \
iptables -w -t nat -A POSTROUTING -o "$INTERFACE" -m mark --mark $FWMARK -j MASQUERADE

```

### 3. Управление маршрутами (`/opt/etc/ndm/ifstatechanged.d/100-rublock-route.sh`)

Хук события интерфейса. Создает отдельную таблицу маршрутизации при поднятии VPN.

```bash
#!/bin/sh

# Wireguard0 — системное имя в Keenetic (проверьте в JSON конфиге или по логам)
[ "$system_name" == "Wireguard0" ] || exit 0

FWMARK="0x7117"
TABLE_ID="111"
INTERFACE="nwg0" # Системное имя в ядре Linux

if [ "$change" == "link" ] && [ "$link" == "up" ]; then
    # Направляем пакеты с меткой 0x7117 в таблицу 111
    ip rule add fwmark $FWMARK table $TABLE_ID 2>/dev/null
    
    # Дефолтный маршрут в таблице 111 идет строго в VPN
    ip route flush table $TABLE_ID
    ip route add default dev "$INTERFACE" table $TABLE_ID
    ip route flush cache
elif [ "$change" == "link" ] && [ "$link" == "down" ]; then
    # Очистка при отключении туннеля
    ip rule del fwmark $FWMARK table $TABLE_ID 2>/dev/null
    ip route flush table $TABLE_ID
fi

```

---

## 📝 Инструкция по установке

1. **Создайте файлы** на роутере через SSH, вставив соответствующий код выше.
2. **Выдайте права на исполнение:**
```bash
chmod +x /opt/bin/update_rublock.sh
chmod +x /opt/etc/ndm/netfilter.d/100-rublock-mark.sh
chmod +x /opt/etc/ndm/ifstatechanged.d/100-rublock-route.sh

```


3. **Запустите первичную загрузку списка:**
```bash
/opt/bin/update_rublock.sh

```


4. **Настройте расписание обновлений:**
Добавьте строку в `/opt/etc/crontab`:
```text
0 4 * * * root /opt/bin/update_rublock.sh

```


И перезапустите cron: `/opt/etc/init.d/S10cron restart`.
5. **Перезагрузите WireGuard интерфейс** в веб-интерфейсе роутера.

---

## 🔍 Диагностика

* **Проверка наполнения списка:** `ipset list rublock | head -n 20`
* **Проверка маркировки (счетчики должны расти):** `iptables -t mangle -L PREROUTING -v -n | grep rublock`
* **Проверка таблицы маршрутизации:** `ip rule show | grep 7117`

## 💡 Важные дополнения

Для работы сервисов с динамическими IP (Discord, Twitter, Instagram) рекомендуется комбинировать данные скрипты со штатной функцией Keenetic **"Маршруты DNS"**:

1. Перейдите в **Сетевые правила** -> **Маршрутизация** -> **Маршруты DNS**.
2. Добавьте домены (например, `discord.com`, `twitter.com`) и укажите интерфейс вашего VPN.

```
