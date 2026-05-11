from django.apps import AppConfig


class BankStatementsConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'apps.bank_statements'
    verbose_name = 'Wyciągi bankowe'
