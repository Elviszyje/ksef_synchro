from django.conf import settings
from django.db import models


class AuditLog(models.Model):
    ACTION_INVOICE_STATUS = 'invoice_status'
    ACTION_INVOICE_NOTE = 'invoice_note'
    ACTION_PAYMENT_FILE = 'payment_file'
    ACTION_BANK_UPLOAD = 'bank_upload'
    ACTION_BANK_CONFIRM = 'bank_confirm'
    ACTION_BANK_MATCH = 'bank_match'
    ACTION_KSEF_SYNC = 'ksef_sync'
    ACTION_KSEF_CONFIG = 'ksef_config'
    ACTION_USER_CREATE = 'user_create'
    ACTION_USER_MODIFY = 'user_modify'
    ACTION_USER_DELETE = 'user_delete'
    ACTION_LOGIN = 'login'
    ACTION_LOGOUT = 'logout'

    ACTION_CHOICES = [
        (ACTION_INVOICE_STATUS, 'Zmiana statusu faktury'),
        (ACTION_INVOICE_NOTE, 'Notatka faktury'),
        (ACTION_PAYMENT_FILE, 'Generowanie przelewów'),
        (ACTION_BANK_UPLOAD, 'Import wyciągu bankowego'),
        (ACTION_BANK_CONFIRM, 'Zatwierdzenie wyciągu'),
        (ACTION_BANK_MATCH, 'Dopasowanie transakcji'),
        (ACTION_KSEF_SYNC, 'Synchronizacja KSeF'),
        (ACTION_KSEF_CONFIG, 'Konfiguracja KSeF'),
        (ACTION_USER_CREATE, 'Utworzenie użytkownika'),
        (ACTION_USER_MODIFY, 'Modyfikacja użytkownika'),
        (ACTION_USER_DELETE, 'Usunięcie użytkownika'),
        (ACTION_LOGIN, 'Logowanie'),
        (ACTION_LOGOUT, 'Wylogowanie'),
    ]

    ACTION_COLORS = {
        ACTION_INVOICE_STATUS: 'primary',
        ACTION_INVOICE_NOTE: 'secondary',
        ACTION_PAYMENT_FILE: 'success',
        ACTION_BANK_UPLOAD: 'info',
        ACTION_BANK_CONFIRM: 'success',
        ACTION_BANK_MATCH: 'info',
        ACTION_KSEF_SYNC: 'warning',
        ACTION_KSEF_CONFIG: 'danger',
        ACTION_USER_CREATE: 'success',
        ACTION_USER_MODIFY: 'warning',
        ACTION_USER_DELETE: 'danger',
        ACTION_LOGIN: 'secondary',
        ACTION_LOGOUT: 'secondary',
    }

    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True, blank=True,
        on_delete=models.SET_NULL,
        related_name='audit_logs',
        verbose_name='Użytkownik',
    )
    action = models.CharField(
        max_length=30, choices=ACTION_CHOICES, db_index=True,
        verbose_name='Akcja',
    )
    entity_type = models.CharField(max_length=50, blank=True, verbose_name='Typ obiektu')
    entity_id = models.CharField(max_length=50, blank=True, verbose_name='ID obiektu')
    entity_repr = models.CharField(max_length=255, blank=True, verbose_name='Opis obiektu')
    detail = models.JSONField(default=dict, verbose_name='Szczegóły')
    ip_address = models.GenericIPAddressField(null=True, blank=True, verbose_name='Adres IP')
    timestamp = models.DateTimeField(auto_now_add=True, db_index=True, verbose_name='Czas')

    class Meta:
        verbose_name = 'Log audytu'
        verbose_name_plural = 'Logi audytu'
        ordering = ['-timestamp']
        indexes = [
            models.Index(fields=['action', 'timestamp']),
            models.Index(fields=['actor', 'timestamp']),
        ]

    def __str__(self):
        actor = self.actor.username if self.actor else 'system'
        return f'{self.timestamp:%Y-%m-%d %H:%M} | {self.get_action_display()} | {actor}'

    def get_action_color(self):
        return self.ACTION_COLORS.get(self.action, 'secondary')
