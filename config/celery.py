import os
from celery import Celery
from celery.schedules import crontab

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.production')

app = Celery('ksef_invoices')
app.config_from_object('django.conf:settings', namespace='CELERY')
app.autodiscover_tasks()

app.conf.beat_schedule = {
    'sync-ksef-invoices': {
        'task': 'apps.ksef.tasks.sync_ksef_invoices',
        'schedule': crontab(minute=0),
    },
    'refresh-ksef-token': {
        'task': 'apps.ksef.tasks.refresh_ksef_token',
        'schedule': crontab(minute='*/55'),
    },
    'send-morning-digest': {
        'task': 'apps.ksef.tasks.send_morning_digest',
        'schedule': crontab(minute=0),
    },
}
