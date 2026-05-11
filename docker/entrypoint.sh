#!/bin/sh
set -e

echo "Waiting for database..."
until python -c "
import psycopg
import os
try:
    conn = psycopg.connect(
        dbname=os.environ.get('POSTGRES_DB','ksef_invoices'),
        user=os.environ.get('POSTGRES_USER','ksef'),
        password=os.environ.get('POSTGRES_PASSWORD',''),
        host=os.environ.get('POSTGRES_HOST','db'),
        port=os.environ.get('POSTGRES_PORT','5432'),
    )
    conn.close()
    print('Database ready')
except Exception as e:
    print(f'DB not ready: {e}')
    exit(1)
" 2>/dev/null; do
    echo "Database unavailable, waiting..."
    sleep 2
done

python manage.py migrate --noinput

if [ -n "$DJANGO_SUPERUSER_USERNAME" ] && [ -n "$DJANGO_SUPERUSER_PASSWORD" ]; then
  python manage.py shell -c "
from apps.accounts.models import CustomUser
if not CustomUser.objects.filter(username='${DJANGO_SUPERUSER_USERNAME}').exists():
    CustomUser.objects.create_superuser(
        '${DJANGO_SUPERUSER_USERNAME}',
        '${DJANGO_SUPERUSER_EMAIL:-}',
        '${DJANGO_SUPERUSER_PASSWORD}',
    )
    print('Superuser created: ${DJANGO_SUPERUSER_USERNAME}')
else:
    print('Superuser already exists: ${DJANGO_SUPERUSER_USERNAME}')
"
fi

exec "$@"
