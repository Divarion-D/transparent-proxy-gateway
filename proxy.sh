#!/bin/bash
# Полный скрипт прозрачного шлюза с SOCKS-прокси

source config.sh || {
    echo "Ошибка загрузки конфигурации!"
    exit 1
}

init_dirs() {
    mkdir -p "$LOG_DIR" "$USER_LIST_DIR" "$SCRIPTS_DIR" "$REDSOCKS_LOG_DIR" "$ROUTING_DIR"
    touch "$USER_LIST_DIR/domains.txt" "$USER_LIST_DIR/ips.txt"
}

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

show_help() {
    echo "Использование: $0 [опция]"
    echo "Опции:"
    echo "  --install               Полная установка системы"
    echo "  --uninstall             Полное удаление шлюза"
    echo "  --wan                   Настройка/изменение WAN подключения"
    echo "  --update-ips            Принудительное обновление IP-адресов"
    echo "  --restart-redsocks      Перезапуск readsocks"
    echo "  --reconfigure_firewall  Переконфигурация фаервола"
    echo "  --reconfigure_dhcp      Переконфигурация DHCP Server"
    echo "  --help                  Показать эту справку"
    exit 0
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_message "Ошибка: Требуются права root!"
        exit 1
    fi
}

install_dependencies() {
    log_message "Установка зависимостей..."
    apt update -y 2>&1 | tee -a "$LOG_FILE"
    apt install -y ipset redsocks network-manager isc-dhcp-server net-tools iproute2 iptables-persistent curl jq 2>&1 | tee -a "$LOG_FILE"
}

select_interfaces() {
    INTERFACES=($(ip link show | awk -F': ' '/^[0-9]+: (e|w)/ && !/lo|docker|veth/ {print $2}'))

    if [ ${#INTERFACES[@]} -lt 2 ]; then
        log_message "Недостаточно сетевых интерфейсов! Найдено: ${#INTERFACES[@]}"
        ip link show | tee -a "$LOG_FILE"
        exit 1
    fi

    log_message "Доступные сетевые интерфейсы:"
    for i in "${!INTERFACES[@]}"; do
        echo "$((i + 1)). ${INTERFACES[$i]}"
    done

    read -p "Выберите номер интерфейса для WAN: " WAN_NUM
    WAN_IFACE=${INTERFACES[$((WAN_NUM - 1))]}

    read -p "Выберите номер интерфейса для LAN: " LAN_NUM
    LAN_IFACE=${INTERFACES[$((LAN_NUM - 1))]}

    if [ "$LAN_IFACE" == "$WAN_IFACE" ]; then
        log_message "Ошибка: LAN и WAN интерфейсы должны быть разными!"
        exit 1
    fi

    log_message "Выбрано: LAN = $LAN_IFACE, WAN = $WAN_IFACE"
}

configure_netplan() {
    log_message "Настройка Netplan..."
    cat >/etc/netplan/01-gateway.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $LAN_IFACE:
      dhcp4: false
      dhcp6: false
      addresses:
        - 10.0.0.1/24
    $WAN_IFACE:
      dhcp4: true
      dhcp6: false
EOF

    chmod 600 /etc/netplan/01-gateway.yaml
    netplan apply 2>&1 | tee -a "$LOG_FILE"
}

configure_dhcp() {
    log_message "Настройка DHCP-сервера..."
    cat >/etc/dhcp/dhcpd.conf <<EOF
default-lease-time 600;
max-lease-time 7200;

subnet 10.0.0.0 netmask 255.255.255.0 {
    range 10.0.0.50 10.0.0.250;
    option routers 10.0.0.1;
    option domain-name-servers $DNS_SERVER_LAN;
}
EOF

    echo "INTERFACESv4=\"$LAN_IFACE\"" >/etc/default/isc-dhcp-server

    systemctl restart isc-dhcp-server
    systemctl enable isc-dhcp-server 2>&1 | tee -a "$LOG_FILE"
}

configure_redsocks() {
    log_message "Настройка RedSocks..."
    cat >"$REDSOCKS_CONFIG" <<EOF
base {
    log_info = on;
    log = "file:$REDSOCKS_LOG_DIR/redsocks.log";
    daemon = off;
    redirector = iptables;
}

redsocks {
    local_ip = 0.0.0.0;
    local_port = 12345;
    ip = proxy_ip;
    port = proxy_port;
    # login = proxy_login;
    # password = proxy_password;
    type = socks5;
}
EOF

    cat >/etc/systemd/system/redsocks.service <<EOF
[Unit]
Description=RedSocks transparent proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/redsocks -c $REDSOCKS_CONFIG
Restart=always
RestartSec=30
StandardOutput=append:$REDSOCKS_LOG_DIR/redsocks-service.log
StandardError=append:$REDSOCKS_LOG_DIR/redsocks-error.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable redsocks --now 2>&1 | tee -a "$LOG_FILE"
}

configure_wan() {
    log_message "Настройка WAN подключения..."

    echo "Выберите тип подключения:"
    select WAN_TYPE in "DHCP" "Static-IP" "PPPoE" "L2TP"; do
        case $WAN_TYPE in
        "DHCP")
            log_message "Используется DHCP..."
            nmcli con show | grep -q "WAN" && nmcli con mod WAN ipv4.method auto || nmcli con add type ethernet con-name WAN ifname $WAN_IFACE ipv4.method auto
            break
            ;;
        "Static-IP")
            read -p "IP/Маска (например 192.168.1.100/24): " STATIC_IP
            read -p "Шлюз: " GATEWAY
            read -p "DNS серверы (разделенные запятой): " DNS_SERVERS

            nmcli con add type ethernet con-name WAN ifname $WAN_IFACE \
                ipv4.addresses "$STATIC_IP" \
                ipv4.gateway "$GATEWAY" \
                ipv4.dns "$DNS_SERVERS" \
                ipv4.method manual
            break
            ;;
        "PPPoE")
            apt install -y pppoeconf >>"$LOG_FILE" 2>&1
            read -p "Логин PPPoE: " PPPOE_USER
            read -s -p "Пароль PPPoE: " PPPOE_PASS

            nmcli con add type pppoe con-name WAN ifname $WAN_IFACE \
                username "$PPPOE_USER" \
                password "$PPPOE_PASS"
            break
            ;;
        "L2TP")
            apt install -y network-manager-l2tp >>"$LOG_FILE" 2>&1
            read -p "Сервер L2TP: " L2TP_SERVER
            read -p "Пользователь: " L2TP_USER
            read -s -p "Пароль: " L2TP_PASS
            read -p "PSK ключ: " L2TP_PSK

            nmcli con add type vpn \
                con-name WAN \
                ifname $WAN_IFACE \
                vpn-type l2tp \
                vpn.data \
                "gateway=$L2TP_SERVER, user=$L2TP_USER, password-flags=1, ipsec-psk=$L2TP_PSK"
            break
            ;;
        *) echo "Неверный выбор" ;;
        esac
    done

    nmcli con mod WAN connection.autoconnect yes
    nmcli con up WAN 2>&1 | tee -a "$LOG_FILE"

    if ! ping -c 3 -I $WAN_IFACE 8.8.8.8 &>>"$LOG_FILE"; then
        log_message "Ошибка подключения!"
        exit 1
    fi
}

configure_firewall() {
    log_message "Создание ipset ${IPSET_NAME}_v4"
    if ! ipset list "$IPSET_NAME" >/dev/null 2>&1; then
        ipset create "$IPSET_NAME" hash:net maxelem $IPSET_MAX_ELEMENTS family inet timeout 0 || log_message "Ошибка создания ipset IPv4"
    fi

    log_message "Создание ipset ${IPSET_NAME}_v6"
    if ! ipset list "${IPSET_NAME}_v6" >/dev/null 2>&1; then
        ipset create "${IPSET_NAME}_v6" hash:net maxelem $IPSET_MAX_ELEMENTS family inet6 timeout 0 || log_message "Ошибка создания ipset IPv6"
    fi

    # Если WAN интерфейс не указан
    if [ -z "$WAN_IFACE" ]; then
        INTERFACES=($(ip link show | awk -F': ' '/^[0-9]+: (e|w)/ && !/lo|docker|veth/ {print $2}'))
        log_message "Доступные сетевые интерфейсы:"
        for i in "${!INTERFACES[@]}"; do
            echo "$((i + 1)). ${INTERFACES[$i]}"
        done

        read -p "Выберите номер интерфейса для WAN: " WAN_NUM
        WAN_IFACE=${INTERFACES[$((WAN_NUM - 1))]}
    fi

    # Проверяем наличие правил в iptables
    log_message "Настройка iptables..."

    # Выключаем службу
    systemctl stop netfilter-persistent

    # Разрешить INPUT для LAN интерфейса (если правила нет)
    if ! iptables -C INPUT -i "$LAN_IFACE" -j ACCEPT 2>/dev/null; then
        iptables -A INPUT -i "$LAN_IFACE" -j ACCEPT
    fi

    # Создать цепочку PROXY_ROUTE, если её нет
    if ! iptables -t nat -L PROXY_ROUTE >/dev/null 2>&1; then
        iptables -t nat -N PROXY_ROUTE
    fi

    # Добавить переход в PROXY_ROUTE из PREROUTING (если нет)
    if ! iptables -t nat -C PREROUTING -j PROXY_ROUTE 2>/dev/null; then
        iptables -t nat -A PREROUTING -j PROXY_ROUTE
    fi

    # Добавить правило перенаправления (с проверкой матчсета и порта)
    if ! iptables -t nat -C PROXY_ROUTE -m set --match-set "$IPSET_NAME" dst -p tcp -j REDIRECT --to-port 12345 2>/dev/null; then
        iptables -t nat -A PROXY_ROUTE -m set --match-set "$IPSET_NAME" dst -p tcp -j REDIRECT --to-port 12345
    fi

    # Добавить MASQUERADE для WAN (если правила нет)
    if ! iptables -t nat -C POSTROUTING -o "$WAN_IFACE" -j MASQUERADE 2>/dev/null; then
        iptables -t nat -A POSTROUTING -o "$WAN_IFACE" -j MASQUERADE
    fi

    # Сохраняем изменения и включаем службу
    netfilter-persistent save 2>&1 | tee -a "$LOG_FILE"
    systemctl enable netfilter-persistent
}

configure_ip_forwarding() {
    log_message "Включение IP Forwarding..."
    sysctl -w net.ipv4.ip_forward=1 2>&1 | tee -a "$LOG_FILE"
    echo "net.ipv4.ip_forward=1" >>/etc/sysctl.conf
}

add_update_script_to_cron() {
    chmod +x "$SCRIPTS_DIR/update_ips.sh"

    # Добавляем задание в cron: запуск при старте системы и каждые 3 часа
    cat >/etc/cron.d/proxy_update <<EOF
# Run in start system
@reboot root $SCRIPTS_DIR/create_ru_list.sh
@reboot root $SCRIPTS_DIR/update_ips.sh

# Run every 3 hours
0 */3 * * * root $SCRIPTS_DIR/create_ru_list.sh
0 */3 * * * root $SCRIPTS_DIR/update_ips.sh
EOF

    # Перезапускаем cron, чтобы изменения применились
    systemctl restart cron
}

install() {
    install_dependencies
    select_interfaces
    configure_netplan
    configure_dhcp
    configure_wan
    configure_redsocks
    add_update_script_to_cron
    update_ips
    configure_firewall
    configure_ip_forwarding
    log_message "Установка завершена! Рекомендуется перезагрузка."
}

uninstall() {
    log_message "Начало удаления системы..."

    # Остановка сервисов
    systemctl stop redsocks isc-dhcp-server 2>/dev/null
    systemctl disable redsocks isc-dhcp-server 2>/dev/null
    systemctl daemon-reload

    # Удаление DHCP сервера
    log_message "Удаление DHCP сервера..."
    apt-get purge -y isc-dhcp-server 2>&1 | tee -a "$LOG_FILE"
    rm -f /etc/dhcp/dhcpd.conf
    rm -f /etc/default/isc-dhcp-server

    # Удаление правил iptables
    iptables -t nat -F PREROUTING
    iptables -t nat -F PROXY_ROUTE
    iptables -t nat -X PROXY_ROUTE 2>/dev/null
    iptables -t nat -D PREROUTING -j PROXY_ROUTE 2>/dev/null
    netfilter-persistent save

    # Удаление ipset
    ipset flush "$IPSET_NAME" 2>/dev/null
    ipset destroy "$IPSET_NAME" 2>/dev/null

    # Удаление конфигов
    rm -rf /etc/netplan/01-gateway.yaml
    rm -f /etc/cron.d/proxy_update
    rm -f /etc/systemd/system/redsocks.service

    # Восстановление сети
    nmcli con del WAN 2>/dev/null
    netplan apply

    log_message "Удаление завершено! Рекомендуется перезагрузка."
}

update_ips() {
    log_message "Запуск обновления IP..."
    "$SCRIPTS_DIR/update_ips.sh"
    log_message "Обновление завершено"
}

restart_redsocks() {
    log_message "Перезапуск RedSocks..."
    systemctl restart redsocks
    log_message "RedSocks перезапущен"
}

main() {
    init_dirs
    case $1 in
    "--install")
        LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
        check_root
        install
        ;;
    "--uninstall")
        LOG_FILE="$LOG_DIR/uninstall-$(date +%Y%m%d-%H%M%S).log"
        check_root
        uninstall
        ;;
    "--wan")
        LOG_FILE="$LOG_DIR/wan-$(date +%Y%m%d-%H%M%S).log"
        check_root
        select_interfaces
        configure_wan
        ;;
    "--update-ips")
        LOG_FILE="$LOG_DIR/update-$(date +%Y%m%d-%H%M%S).log"
        check_root
        update_ips
        ;;
    "--restart-redsocks")
        LOG_FILE="$LOG_DIR/restart-$(date +%Y%m%d-%H%M%S).log"
        check_root
        restart_redsocks
        ;;
    "--reconfigure_firewall")
        LOG_FILE="$LOG_DIR/firewal-$(date +%Y%m%d-%H%M%S).log"
        check_root
        configure_firewall
        ;;
    "--reconfigure_dhcp")
        LOG_FILE="$LOG_DIR/dhcp-$(date +%Y%m%d-%H%M%S).log"
        check_root
        select_interfaces
        configure_dhcp
        ;;
    "--help")
        show_help
        ;;
    *)
        LOG_FILE="$LOG_DIR/default-$(date +%Y%m%d-%H%M%S).log"
        check_root
        show_help
        ;;
    esac
}

main "$@"
