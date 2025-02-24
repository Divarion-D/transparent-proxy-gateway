#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh" || {
    echo "Ошибка загрузки конфигурации!";
    exit 1;
}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_DIR/ip-update.log"
}

validate_ipv4() {
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && return 0
    return 1
}

validate_ipv4_cidr() {
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]{1,2})$ ]] && return 0
    return 1
}

validate_ipv6() {
    [[ "$1" =~ ^([0-9a-fA-F:]+:+)+[0-9a-fA-F]+$ ]] && return 0
    return 1
}

validate_ipv6_cidr() {
    [[ "$1" =~ ^([0-9a-fA-F:]+:+)+[0-9a-fA-F]+/([0-9]{1,3})$ ]] && return 0
    return 1
}

has_valid_entries() {
    grep -qEv '^[[:blank:]]*($|#)' "$1"
}

mkdir -p "$LOG_DIR" "$(dirname "$CACHE_FILE")" || {
    echo "Ошибка создания директорий";
    exit 1;
}

log "Начало обработки"

TMP_CACHE_V4=$(mktemp)
TMP_CACHE_V6=$(mktemp)
TMP_IPS_V4=$(mktemp)
TMP_IPS_V6=$(mktemp)
TMP_CIDR_V4=$(mktemp)
TMP_CIDR_V6=$(mktemp)

process_file() {
    local file="$1"
    log "Обработка файла: $file"

    while read -r entry; do
        [[ -z "$entry" || "$entry" == \#* ]] && continue
        
        if validate_ipv4 "$entry"; then
            echo "$entry" >> "$TMP_IPS_V4"
        elif validate_ipv4_cidr "$entry"; then
            echo "$entry" >> "$TMP_CIDR_V4"
        elif validate_ipv6 "$entry"; then
            echo "$entry" >> "$TMP_IPS_V6"
        elif validate_ipv6_cidr "$entry"; then
            echo "$entry" >> "$TMP_CIDR_V6"
        else
            log "Резолвинг: $entry"
            ips=$(dig +short @$DNS_SERVER "$entry" A 2>/dev/null | grep -E '^[0-9\.]+$')
            ips_v6=$(dig +short @$DNS_SERVER "$entry" AAAA 2>/dev/null | grep -E '^[0-9a-fA-F:]+$')
            
            if [ -n "$ips" ]; then
                echo "$ips" >> "$TMP_IPS_V4"
                log "Найден IPv4: $(echo "$ips" | tr '\n' ' ')"
            fi
            if [ -n "$ips_v6" ]; then
                echo "$ips_v6" >> "$TMP_IPS_V6"
                log "Найден IPv6: $(echo "$ips_v6" | tr '\n' ' ')"
            fi
        fi
    done < <(grep -v -e '^[[:space:]]*$' -e '^#' "$file")
}

for file in "$ROUTING_DIR"/* "$DOMAIN_LIST" "$IPS_LIST"; do
    [ -f "$file" ] && has_valid_entries "$file" && process_file "$file"
done

sort -u "$TMP_IPS_V4" > "$TMP_CACHE_V4"
sort -u "$TMP_CIDR_V4" >> "$TMP_CACHE_V4"
sort -u "$TMP_IPS_V6" > "$TMP_CACHE_V6"
sort -u "$TMP_CIDR_V6" >> "$TMP_CACHE_V6"

mv "$TMP_CACHE_V4" "$CACHE_FILE_V4"
mv "$TMP_CACHE_V6" "$CACHE_FILE_V6"

if [ -s "$CACHE_FILE_V4" ]; then
    log "Обновление ipset $IPSET_NAME"
    if ! ipset list "$IPSET_NAME" >/dev/null 2>&1; then
        ipset create "$IPSET_NAME" hash:net family inet timeout 0 || log "Ошибка создания ipset IPv4"
    else
        ipset flush "$IPSET_NAME" || log "Ошибка очистки ipset IPv4"
    fi
    while read -r ip; do
        ipset add "$IPSET_NAME" "$ip" || log "Ошибка добавления IPv4: $ip"
    done < "$CACHE_FILE_V4"
fi

if [ -s "$CACHE_FILE_V6" ]; then
    log "Обновление ipset ${IPSET_NAME}_v6"
    if ! ipset list "${IPSET_NAME}_v6" >/dev/null 2>&1; then
        ipset create "${IPSET_NAME}_v6" hash:net family inet6 timeout 0 || log "Ошибка создания ipset IPv6"
    else
        ipset flush "${IPSET_NAME}_v6" || log "Ошибка очистки ipset IPv6"
    fi
    while read -r ip; do
        ipset add "${IPSET_NAME}_v6" "$ip" || log "Ошибка добавления IPv6: $ip"
    done < "$CACHE_FILE_V6"
fi

rm -f "$TMP_IPS_V4" "$TMP_IPS_V6" "$TMP_CIDR_V4" "$TMP_CIDR_V6" "$TMP_CACHE_V4" "$TMP_CACHE_V6"
log "Обработка завершена"
