📨 mailcow-simple-backup-s3

Простий скрипт для резервного копіювання Mailcow, що:
✔ Використовує вбудований механізм бекапу
✔ Архівує отримані дані
✔ Передає їх у S3
⏰ Приклад запуску через cron:

0 5 * * * /bin/bash /opt/mailcow-dockerized/mailcow-backup.sh >> /var/log/mailcow-backup/mailcow-backup-cron.log 2>&1

📦 Надійний, простий, без зайвих складнощів.
