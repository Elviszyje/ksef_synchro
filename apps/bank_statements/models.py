from django.conf import settings
from django.db import models


class BankStatement(models.Model):
    STATUS_PENDING = 'pending'
    STATUS_REVIEWED = 'reviewed'
    STATUS_CONFIRMED = 'confirmed'
    STATUSES = [
        (STATUS_PENDING, 'Oczekuje na przegląd'),
        (STATUS_REVIEWED, 'W przeglądzie'),
        (STATUS_CONFIRMED, 'Zatwierdzony'),
    ]

    company = models.ForeignKey(
        'accounts.Company',
        on_delete=models.CASCADE,
        null=True,
        verbose_name='Firma',
        db_index=True,
    )
    file_name = models.CharField(max_length=255, verbose_name='Nazwa pliku')
    account_number = models.CharField(max_length=34, blank=True, verbose_name='Numer rachunku')
    statement_date = models.DateField(null=True, blank=True, verbose_name='Data wyciągu')
    status = models.CharField(max_length=10, choices=STATUSES, default=STATUS_PENDING)
    file_format = models.CharField(max_length=20, default='mt940', verbose_name='Format pliku')
    raw_content = models.TextField(verbose_name='Surowa treść pliku')
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL,
        related_name='uploaded_statements',
        verbose_name='Wgrany przez',
    )
    uploaded_at = models.DateTimeField(auto_now_add=True, verbose_name='Data wgrania')
    confirmed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
        related_name='confirmed_statements',
        verbose_name='Zatwierdzony przez',
    )
    confirmed_at = models.DateTimeField(null=True, blank=True, verbose_name='Data zatwierdzenia')

    class Meta:
        verbose_name = 'Wyciąg bankowy'
        verbose_name_plural = 'Wyciągi bankowe'
        ordering = ['-uploaded_at']

    def __str__(self):
        return f'{self.file_name} ({self.statement_date or "brak daty"})'


class BankTransaction(models.Model):
    statement = models.ForeignKey(
        BankStatement, on_delete=models.CASCADE,
        related_name='transactions',
        verbose_name='Wyciąg',
    )
    transaction_date = models.DateField(verbose_name='Data transakcji')
    value_date = models.DateField(verbose_name='Data waluty')
    amount = models.DecimalField(max_digits=15, decimal_places=2, verbose_name='Kwota')
    currency = models.CharField(max_length=3, default='PLN', verbose_name='Waluta')
    is_debit = models.BooleanField(verbose_name='Uznanie (D) / Obciążenie (C)')
    description = models.TextField(blank=True, verbose_name='Opis transakcji')
    reference = models.CharField(max_length=35, blank=True, verbose_name='Referencja')
    is_matched = models.BooleanField(default=False, verbose_name='Dopasowana')

    class Meta:
        verbose_name = 'Transakcja bankowa'
        verbose_name_plural = 'Transakcje bankowe'
        indexes = [
            models.Index(fields=['statement', 'transaction_date']),
            models.Index(fields=['amount', 'is_matched']),
        ]

    def __str__(self):
        sign = '+' if self.is_debit else '-'
        return f'{self.transaction_date} {sign}{self.amount} PLN'


class TransactionMatch(models.Model):
    MATCH_AMOUNT = 'amount'
    MATCH_NIP = 'nip'
    MATCH_INVOICE_NR = 'invoice_nr'
    MATCH_MANUAL = 'manual'
    MATCH_TYPES = [
        (MATCH_AMOUNT, 'Kwota'),
        (MATCH_NIP, 'NIP w tytule'),
        (MATCH_INVOICE_NR, 'Numer faktury'),
        (MATCH_MANUAL, 'Ręczne'),
    ]

    CONFIDENCE_HIGH = 'high'
    CONFIDENCE_MEDIUM = 'medium'
    CONFIDENCE_LOW = 'low'
    CONFIDENCES = [
        (CONFIDENCE_HIGH, 'Pewne'),
        (CONFIDENCE_MEDIUM, 'Możliwe'),
        (CONFIDENCE_LOW, 'Niepewne'),
    ]

    transaction = models.ForeignKey(
        BankTransaction, on_delete=models.CASCADE,
        related_name='matches',
        verbose_name='Transakcja',
    )
    invoice = models.ForeignKey(
        'invoices.Invoice', on_delete=models.CASCADE,
        related_name='matches',
        verbose_name='Faktura',
    )
    match_type = models.CharField(max_length=15, choices=MATCH_TYPES)
    confidence = models.CharField(max_length=10, choices=CONFIDENCES)
    is_confirmed = models.BooleanField(default=False, verbose_name='Potwierdzone')
    confirmed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
        verbose_name='Potwierdzone przez',
    )
    confirmed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        verbose_name = 'Dopasowanie transakcji'
        verbose_name_plural = 'Dopasowania transakcji'
        unique_together = [('transaction', 'invoice')]

    def __str__(self):
        return f'{self.transaction} ↔ {self.invoice} [{self.get_confidence_display()}]'
