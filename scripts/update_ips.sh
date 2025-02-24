#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh" || {
    echo "Ошибка загрузки конфигурации!";
    exit 1;
}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_DIR/ip-update.log"
}

validate_ip() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && return 0 || return 1
}

has_valid_entries() {
    grep -qEv '^[[:blank:]]*($|#)' "$1"
}

# Создаем директории, если их нет
mkdir -p "$LOG_DIR" "$(dirname "$CACHE_FILE")" || {
    echo "Ошибка создания директорий";
    exit 1;
}

log "Начало обработки"

# Инициализация временных файлов
TMP_CACHE=$(mktemp)
TMP_IPS=$(mktemp)

# Функция обработки файла с доменами и IP
process_file() {
    local file="$1"
    log "Обработка файла: $file"

    while read -r entry; do
        [[ -z "$entry" || "$entry" == \#* ]] && continue
        
        # Проверка, является ли строка IP-адресом или доменом
        if validate_ip "$entry"; then
            echo "$entry" >> "$TMP_IPS"
        else
            log "Резолвинг: $entry"
            ips=$(dig +short @$DNS_SERVER "$entry" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
            if [ -n "$ips" ]; then
                echo "$ips" >> "$TMP_IPS"
                log "Найден IP: $(echo "$ips" | tr '\n' ' ')"
            else
                log "Не удалось резолвить: $entry"
            fi
        fi
    done < <(grep -v -e '^[[:space:]]*$' -e '^#' "$file")
}

# Сканирование всех файлов в ROUTING_DIR, а также DOMAIN_LIST и IPS_LIST
for file in "$ROUTING_DIR"/* "$DOMAIN_LIST" "$IPS_LIST"; do
    [ -f "$file" ] && has_valid_entries "$file" && process_file "$file"
done

# Удаление дубликатов и сохранение в кэш
if [ -s "$TMP_IPS" ]; then
    log "Генерация кеша с уникальными IP"
    sort -u "$TMP_IPS" > "$TMP_CACHE"
    TOTAL_IPS=$(wc -l < "$TMP_CACHE")
    log "Найдено уникальных IP: $TOTAL_IPS"

    mv "$TMP_CACHE" "$CACHE_FILE" || log "Ошибка сохранения кеш-файла"
else
    log "Нет IP для обработки - очищаем кеш"
    > "$CACHE_FILE"
fi

# Обновление ipset и iptables
if [ -s "$CACHE_FILE" ]; then
    log "Обновление ipset $IPSET_NAME"
    
    # Создание/очистка ipset
    if ! ipset list "$IPSET_NAME" >/dev/null 2>&1; then
        ipset create "$IPSET_NAME" hash:ip timeout 0 || log "Ошибка создания ipset"
    else
        ipset flush "$IPSET_NAME" || log "Ошибка очистки ipset"
    fi
    
    # Добавление IP в ipset
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
