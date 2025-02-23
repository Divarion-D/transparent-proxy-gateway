#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source $SCRIPT_DIR/../config.sh || {
    echo "Ошибка загрузки конфигурации!";
    exit 1;
}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_DIR/ip-update.log"
    echo "$1"
}

validate_ip() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && return 0 || return 1
}

has_valid_entries() {
    grep -qEv '^[[:blank:]]*($|#)' "$1"
}

# Создаем директории если отсутствуют
mkdir -p "$LOG_DIR" "$(dirname "$CACHE_FILE")" || {
    echo "Ошибка создания директорий"
    exit 1
}

log "Начало обработки"

# Инициализация временных файлов
TMP_CACHE=$(mktemp)
TMP_IPS=$(mktemp)

# Обработка доменов
if [ -f "$DOMAIN_LIST" ] && has_valid_entries "$DOMAIN_LIST"; then
    log "Резолвинг доменов через $DNS_SERVER"
    while read -r domain; do
        # Пропуск пустых строк и комментариев
        [[ -z "$domain" || "$domain" == \#* ]] && continue

        # Выполняем DNS-запрос
        log "Запрос: $domain"
        ips=$(dig +short @$DNS_SERVER "$domain" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')

        if [ -n "$ips" ]; then
            echo "$ips" >> "$TMP_IPS"
            log "Найдены IP: $(echo "$ips" | tr '\n' ' ')"
        else
            log "Не удалось получить IP для: $domain"
        fi
    done < <(grep -v -e '^[[:space:]]*$' -e '^#' "$DOMAIN_LIST")
else
    log "Файл доменов $DOMAIN_LIST не содержит данных для обработки"
fi

# Обработка готовых IP
if [ -f "$IPS_LIST" ] && has_valid_entries "$IPS_LIST"; then
    log "Чтение IP из $IPS_LIST"
    while read -r ip; do
        [[ -z "$ip" || "$ip" == \#* ]] && continue
        
        if validate_ip "$ip"; then
            echo "$ip" >> "$TMP_IPS"
        else
            log "Неверный формат IP: $ip"
        fi
    done < <(grep -v -e '^[[:space:]]*$' -e '^#' "$IPS_LIST")
else
    log "Файл IP $IPS_LIST пропущен"
fi

# Создаем кеш с уникальными IP
if [ -s "$TMP_IPS" ]; then
    log "Генерация кеша с уникальными IP"
    sort -u "$TMP_IPS" > "$TMP_CACHE"
    TOTAL_IPS=$(wc -l < "$TMP_CACHE")
    log "Найдено уникальных IP: $TOTAL_IPS"
    
    # Сохраняем кеш
    mv "$TMP_CACHE" "$CACHE_FILE" || log "Ошибка сохранения кеш-файла"
else
    log "Нет IP для обработки - очищаем кеш"
    > "$CACHE_FILE"
fi

# Работа с ipset
if [ -f "$CACHE_FILE" ] && [ -s "$CACHE_FILE" ]; then
    log "Обновление ipset $IPSET_NAME"
    
    # Создаем/очищаем ipset
    if ! ipset list "$IPSET_NAME" >/dev/null 2>&1; then
        ipset create "$IPSET_NAME" hash:ip timeout 300 || log "Ошибка создания ipset"
    else
        ipset flush "$IPSET_NAME" || log "Ошибка очистки ipset"
    fi
    
    # Добавляем IP из кеша
    added=0
    while read -r ip; do
        if ipset add "$IPSET_NAME" "$ip"; then
            ((added++))
        else
            log "Ошибка добавления IP: $ip"
        fi
    done < "$CACHE_FILE"
    
    log "Успешно добавлено IP: $added/$TOTAL_IPS"
else
    log "Кеш пуст - очищаем ipset"
    ipset flush "$IPSET_NAME" || log "Ошибка очистки ipset"
fi

# Очистка временных файлов
rm -f "$TMP_IPS" "$TMP_CACHE"
log "Обработка завершена"