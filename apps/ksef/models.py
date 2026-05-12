from datetime import time as dtime

from django.db import models


class KSeFConfig(models.Model):
    ENV_TEST = 'test'
    ENV_PROD = 'prod'
    ENVIRONMENTS = [(ENV_TEST, 'Testowe'), (ENV_PROD, 'Produkcyjne')]

    BASE_URLS = {
        ENV_TEST: 'https://api-test.ksef.mf.gov.pl',
        ENV_PROD: 'https://api.ksef.mf.gov.pl',
    }

    nip = models.CharField(max_length=10, unique=True, verbose_name='NIP firmy')
    environment = models.CharField(
        max_length=4, choices=ENVIRONMENTS, default=ENV_TEST,
        verbose_name='Środowisko',
    )
    # Token przechowywany zaszyfrowany Fernet
    token_encrypted = models.TextField(blank=True, verbose_name='Token API (zaszyfrowany)')
    token_expiry = models.DateTimeField(null=True, blank=True, verbose_name='Ważność tokena')
    sync_enabled = models.BooleanField(default=True, verbose_name='Synchronizacja włączona')
    sync_interval_hours = models.PositiveIntegerField(default=6, verbose_name='Interwał synchronizacji (godz.)')
    sync_window_start = models.TimeField(null=True, blank=True, verbose_name='Okno sync — od')
    sync_window_end = models.TimeField(null=True, blank=True, verbose_name='Okno sync — do')
    last_sync_at = models.DateTimeField(null=True, blank=True, verbose_name='Ostatnia synchronizacja')
    last_sync_reference_number = models.CharField(
        max_length=255, blank=True,
        verbose_name='Ostatni numer referencyjny (kursor)',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Konfiguracja KSeF'
        verbose_name_plural = 'Konfiguracja KSeF'

    def __str__(self):
        return f'KSeF [{self.get_environment_display()}] — NIP {self.nip}'

    @property
    def base_url(self) -> str:
        return self.BASE_URLS.get(self.environment, self.BASE_URLS[self.ENV_TEST])

    @classmethod
    def get_active(cls) -> 'KSeFConfig | None':
        return cls.objects.first()

    def set_token(self, plain_token: str):
        from django.conf import settings
        from cryptography.fernet import Fernet
        key = settings.KSEF_TOKEN_ENCRYPTION_KEY
        if key:
            f = Fernet(key.encode() if isinstance(key, str) else key)
            self.token_encrypted = f.encrypt(plain_token.encode()).decode()
        else:
            self.token_encrypted = plain_token

    def get_token(self) -> str:
        from django.conf import settings
        from cryptography.fernet import Fernet
        key = settings.KSEF_TOKEN_ENCRYPTION_KEY
        if key and self.token_encrypted:
            try:
                f = Fernet(key.encode() if isinstance(key, str) else key)
                return f.decrypt(self.token_encrypted.encode()).decode()
            except Exception:
                pass
        return self.token_encrypted


class KSeFSyncLog(models.Model):
    STATUS_RUNNING = 'running'
    STATUS_SUCCESS = 'success'
    STATUS_ERROR = 'error'
    STATUS_CANCELLED = 'cancelled'
    STATUSES = [
        (STATUS_RUNNING, 'W toku'),
        (STATUS_SUCCESS, 'Sukces'),
        (STATUS_ERROR, 'Błąd'),
        (STATUS_CANCELLED, 'Anulowano'),
    ]

    started_at = models.DateTimeField(auto_now_add=True, verbose_name='Rozpoczęto')
    finished_at = models.DateTimeField(null=True, blank=True, verbose_name='Zakończono')
    status = models.CharField(max_length=10, choices=STATUSES, default=STATUS_RUNNING)
    invoices_fetched = models.IntegerField(default=0, verbose_name='Pobrano faktur')
    invoices_new = models.IntegerField(default=0, verbose_name='Nowych faktur')
    error_message = models.TextField(blank=True, verbose_name='Komunikat błędu')
    celery_task_id = models.CharField(max_length=255, blank=True)
    current_stage = models.CharField(max_length=120, blank=True, verbose_name='Etap')
    cancel_requested = models.BooleanField(default=False, verbose_name='Żądanie anulowania')

    class Meta:
        verbose_name = 'Log synchronizacji KSeF'
        verbose_name_plural = 'Logi synchronizacji KSeF'
        ordering = ['-started_at']
        indexes = [models.Index(fields=['started_at'])]

    def __str__(self):
        return f'Sync {self.started_at:%Y-%m-%d %H:%M} — {self.get_status_display()}'


class NotificationConfig(models.Model):
    enabled = models.BooleanField(default=False, verbose_name='Powiadomienia włączone')
    telegram_bot_token_encrypted = models.TextField(blank=True, verbose_name='Token bota Telegram (zaszyfrowany)')
    telegram_chat_id = models.CharField(max_length=100, blank=True, verbose_name='Chat ID')
    quiet_from = models.TimeField(default=dtime(22, 0), verbose_name='Cisza nocna — od')
    quiet_to = models.TimeField(default=dtime(8, 0), verbose_name='Cisza nocna — do')
    digest_time = models.TimeField(default=dtime(8, 0), verbose_name='Godzina porannego digesty')

    class Meta:
        verbose_name = 'Konfiguracja powiadomień'

    def __str__(self):
        return f'Powiadomienia Telegram ({"włączone" if self.enabled else "wyłączone"})'

    @classmethod
    def get_active(cls):
        return cls.objects.first()

    def set_bot_token(self, plain_token: str):
        from django.conf import settings
        from cryptography.fernet import Fernet
        key = settings.KSEF_TOKEN_ENCRYPTION_KEY
        if key:
            f = Fernet(key.encode() if isinstance(key, str) else key)
            self.telegram_bot_token_encrypted = f.encrypt(plain_token.encode()).decode()
        else:
            self.telegram_bot_token_encrypted = plain_token

    def get_bot_token(self) -> str:
        from django.conf import settings
        from cryptography.fernet import Fernet
        key = settings.KSEF_TOKEN_ENCRYPTION_KEY
        if key and self.telegram_bot_token_encrypted:
            try:
                f = Fernet(key.encode() if isinstance(key, str) else key)
                return f.decrypt(self.telegram_bot_token_encrypted.encode()).decode()
            except Exception:
                pass
        return self.telegram_bot_token_encrypted


class PendingNotification(models.Model):
    created_at = models.DateTimeField(auto_now_add=True, verbose_name='Czas zdarzenia')
    invoice_count = models.IntegerField(verbose_name='Liczba faktur')
    summary = models.TextField(verbose_name='Treść powiadomienia')
    sent = models.BooleanField(default=False, verbose_name='Wysłane')
    sent_at = models.DateTimeField(null=True, blank=True, verbose_name='Czas wysyłki')

    class Meta:
        verbose_name = 'Oczekujące powiadomienie'
        ordering = ['created_at']

    def __str__(self):
        return f'{self.created_at:%Y-%m-%d %H:%M} — {self.invoice_count} faktur'
