#!/bin/bash

# Налаштування змінних
BACKUP_DIR="/var/backups/mailcow"                # Каталог для збереження резервних копій Mailcow
S3_REMOTE="s3-backup:maicow-backet-buckup"      # Ім'я віддаленого S3 сховища в rclone
DATE=$(date +%F-%H-%M-%S)                         # Поточна дата у форматі YYYY-MM-DD-HH-MM-SS
ARCHIVE_NAME="mailcow-$DATE.tar.gz"              # Ім'я архіву
LOG_FILE="/var/log/mailcow-backup.log"           # Лог-файл для запису подій
LOCK_FILE="/tmp/mailcow-backup.lock"             # Файл блокування для уникнення одночасного запуску

# Функція логування
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Перевірка, чи вже виконується інший процес бекапу
if [[ -f "$LOCK_FILE" ]]; then
    log "Помилка: Скрипт вже виконується!"
    exit 1
fi
trap 'rm -f "$LOCK_FILE"' EXIT

touch "$LOCK_FILE"

# Перевірка наявності rclone
if ! command -v rclone &> /dev/null; then
    log "Помилка: rclone не встановлений!"
    exit 1
fi

# Перевірка вільного місця на диску
FREE_SPACE=$(df "$BACKUP_DIR" | awk 'NR==2 {print $4}')
if [[ $FREE_SPACE -lt 10485760 ]]; then  # 10GB у блоках 1K
    log "Помилка: Недостатньо місця на диску!"
    exit 1
fi

# Створення каталогу для резервних копій (якщо його немає)
log "Створення каталогу для резервних копій..."
mkdir -p "$BACKUP_DIR"

# Запуск резервного копіювання
export MAILCOW_BACKUP_LOCATION="$BACKUP_DIR"
log "Запуск резервного копіювання..."
/opt/mailcow-dockerized/helper-scripts/backup_and_restore.sh backup all

# Отримання останньої створеної папки з бекапом
LAST_BACKUP=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "mailcow-*" -printf "%T@ %p\n" | sort -nr | awk 'NR==1{print $2}')

# Перевірка, чи бекап створився успішно
if [[ -z "$LAST_BACKUP" ]]; then
    log "Помилка: Не знайдено створеного бекапу!"
    exit 1
fi

log "Бекап збережено в $LAST_BACKUP"

# Архівування створеної папки
log "Архівування бекапу..."
tar -czf "$BACKUP_DIR/$ARCHIVE_NAME" -C "$BACKUP_DIR" "$(basename "$LAST_BACKUP")"

# Перевірка, чи архів створився
if [[ ! -f "$BACKUP_DIR/$ARCHIVE_NAME" ]]; then
    log "Помилка: Архів не створився!"
    exit 1
fi

# Видалення оригінальної папки після успішного архівування
log "Видалення оригінальної папки після архівування..."
rm -rf "$LAST_BACKUP"

# Відправка архіву у S3 за допомогою Rclone
log "Відправка архіву в S3..."
rclone copy "$BACKUP_DIR/$ARCHIVE_NAME" "$S3_REMOTE"

# Перевірка, чи архів успішно збережений у S3
if rclone ls "$S3_REMOTE" | grep -q "$ARCHIVE_NAME"; then
    log "Архів успішно збережений у S3, видалення локальних файлів..."
    rm -rf "$BACKUP_DIR/$ARCHIVE_NAME"
else
    log "Помилка: Бекап не знайдено в S3! Локальні файли НЕ видалено."
    exit 1
fi

# Видалення старих бекапів у S3 (залишаємо тільки останні 7)
log "Видалення старих бекапів у S3..."
rclone delete --min-age 8d "$S3_REMOTE"

# Очищення старих локальних бекапів (залишаємо 7 останніх)
log "Видалення старих локальних бекапів..."
find "$BACKUP_DIR" -type f -name "mailcow-*.tar.gz" -mtime +7 -delete

# Записуємо лог про успішне завершення резервного копіювання
log "Бекап $ARCHIVE_NAME успішно створено, завантажено в S3 та видалено локально."
