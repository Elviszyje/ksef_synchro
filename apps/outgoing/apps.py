from django.apps import AppConfig


class OutgoingConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'apps.outgoing'
    verbose_name = 'Faktury wychodzące'
