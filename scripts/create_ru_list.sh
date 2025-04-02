#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh" || {
    echo "Ошибка загрузки конфигурации!";
    exit 1;
}

OUTPUT_FILE="$USER_LIST_DIR/ru_list.txt"
TMP_FILE=$(mktemp)

# Функция для обработки ошибок
handle_error() {
    echo "Ошибка: $1"
    rm -f "$TMP_FILE"
    exit 1
}

# Очищаем файл с доменами
> "$OUTPUT_FILE"

# Обрабатываем первый API (ips)
echo "Получаем данные из API /ips..."
curl -sS "https://reestr.rublacklist.net/api/v3/ips/" | \
tr -d '[]"' | \
tr ',' '\n' | \
sed 's/\\//g; s/^ *//; s/ *$//' | \
grep -v '^$' | \
grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$' >> "$OUTPUT_FILE" || handle_error "Не удалось обработать первый API"

# Обрабатываем второй API (dpi)
echo "Получаем данные из API /dpi..."
curl -sS "https://reestr.rublacklist.net/api/v3/dpi/" -o "$TMP_FILE" || handle_error "Ошибка запроса ко второму API"

if [ -x "$(command -v jq)" ]; then
    jq -r '.[].domains[]' "$TMP_FILE" >> "$OUTPUT_FILE" || handle_error "Ошибка парсинга JSON"
else
    echo "Предупреждение: jq не установлен, используем базовую обработку"
    grep -oP '"domains": \[\s*\K[^\]]+' "$TMP_FILE" | \
    sed 's/"//g; s/,//g; s/ //g' | \
    tr ' ' '\n' >> "$OUTPUT_FILE"
fi

# Финализация обработки
rm -f "$TMP_FILE"

# Удаляем дубликаты и сортируем
sort -u "$OUTPUT_FILE" -o "$OUTPUT_FILE"

echo "Общее количество уникальных доменов: $(wc -l < "$OUTPUT_FILE")"
echo "Результаты сохранены в: $OUTPUT_FILE"