#!/bin/bash

# Проверяем, передан ли файл как аргумент
if [ $# -ne 1 ]; then
    echo "Использование: $0 <html_file>"
    exit 1
fi

HTML_FILE="$1"

# Проверяем, существует ли файл
if [ ! -f "$HTML_FILE" ]; then
    echo "Файл $HTML_FILE не найден!"
    exit 1
fi

# Создаём временный файл
TEMP_FILE=$(mktemp)

# Удаляем строки, содержащие нужную подстроку
grep -vF '<td><a href="/root/gpu_test/tetris_deepseek-r1' "$HTML_FILE" > "$TEMP_FILE"

# Перемещаем временный файл на место оригинального
mv "$TEMP_FILE" "$HTML_FILE"

echo "Обработка завершена. Строки, содержащие подстроку, удалены из $HTML_FILE"