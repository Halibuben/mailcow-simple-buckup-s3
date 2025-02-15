# mailcow-simple-buckup-s3
Простий скрипт який використовує вбудований метод бекапування mailcow, архівує і передає в S3

0 5 * * * /bin/bash /opt/mailcow-dockerized/mailcow-backup.sh >> /var/log/mailcow-buckup/mailcow-backup-cron.log 2>&1
