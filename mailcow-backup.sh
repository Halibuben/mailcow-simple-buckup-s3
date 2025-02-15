#!/bin/bash

# Налаштування змінних
BACKUP_DIR="/var/backups/mailcow"                # Каталог для збереження резервних копій Mailcow
S3_REMOTE="s3-backup:maicow-backet-buckup"       # Ім'я віддаленого S3 сховища в rclone
DATE=$(date +%F-%H-%M-%S)                        # Поточна дата у форматі YYYY-MM-DD-HH-MM-SS
ARCHIVE_NAME="mailcow-$DATE.tar.gz"              # Ім'я архіву
LOG_FILE="/var/log/mailcow-backup.log"           # Лог-файл для запису подій

# Перевірка наявності rclone
if ! command -v rclone &> /dev/null; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Помилка: rclone не встановлений!" | tee -a "$LOG_FILE"
    exit 1
fi
# Перевірка вільного місця на диску
FREE_SPACE=$(df "$BACKUP_DIR" | awk 'NR==2 {print $4}')
if [[ $FREE_SPACE -lt 10485760 ]]; then  # 10GB у блоках 1K
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Помилка: Недостатньо місця на диску!" | tee -a "$LOG_FILE"
    exit 1
fi

# Створення каталогу для резервних копій (якщо його немає)
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Створення каталогу для резервних копій..." | tee -a "$LOG_FILE"
mkdir -p "$BACKUP_DIR"

# Запуск резервного копіювання
export MAILCOW_BACKUP_LOCATION="$BACKUP_DIR"
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Запуск резервного копіювання..." | tee -a "$LOG_FILE"
/opt/mailcow-dockerized/helper-scripts/backup_and_restore.sh backup all

# Отримання останньої створеної папки з бекапом
LAST_BACKUP=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "mailcow-*" -printf "%T@ %p\n" | sort -nr | awk 'NR==1{print $2}')

# Перевірка, чи бекап створився успішно
if [[ -z "$LAST_BACKUP" ]]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Помилка: Не знайдено створеного бекапу!" | tee -a "$LOG_FILE"
    exit 1
fi

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Бекап збережено в $LAST_BACKUP" | tee -a "$LOG_FILE"

# Архівування створеної папки
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Архівування бекапу..." | tee -a "$LOG_FILE"
tar -czf "$BACKUP_DIR/$ARCHIVE_NAME" -C "$BACKUP_DIR" "$(basename "$LAST_BACKUP")"

# Перевірка, чи архів створився
if [[ ! -f "$BACKUP_DIR/$ARCHIVE_NAME" ]]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Помилка: Архів не створився!" | tee -a "$LOG_FILE"
    exit 1
fi

# Видалення оригінальної папки після успішного архівування
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Видалення оригінальної папки після архівування..." | tee -a "$LOG_FILE"
rm -rf "$LAST_BACKUP"

# Відправка архіву у S3 за допомогою Rclone
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Відправка архіву в S3..." | tee -a "$LOG_FILE"
rclone copy "$BACKUP_DIR/$ARCHIVE_NAME" "$S3_REMOTE"

# Перевірка, чи архів успішно збережений у S3
if rclone ls "$S3_REMOTE" | grep -q "$ARCHIVE_NAME"; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Архів успішно збережений у S3, видалення локальних файлів..." | tee -a "$LOG_FILE"
    rm -rf "$BACKUP_DIR/$ARCHIVE_NAME"
else
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Помилка: Бекап не знайдено в S3! Локальні файли НЕ видалено." | tee -a "$LOG_FILE"
    exit 1
fi

# Видалення старих бекапів у S3 (залишаємо тільки останні 7)
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Видалення старих бекапів у S3..." | tee -a "$LOG_FILE"
rclone delete --min-age 8d "$S3_REMOTE"

# Очищення старих локальних бекапів (залишаємо 7 останніх)
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Видалення старих локальних бекапів..." | tee -a "$LOG_FILE"
find "$BACKUP_DIR" -type f -name "mailcow-*.tar.gz" -mtime +7 -delete

# Записуємо лог про успішне завершення резервного копіювання
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Бекап $ARCHIVE_NAME успішно створено, завантажено в S3 та видалено локально." | tee -a "$LOG_FILE"
