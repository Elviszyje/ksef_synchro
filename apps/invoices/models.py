from django.conf import settings
from django.db import models
from django.utils import timezone


class Invoice(models.Model):
    company = models.ForeignKey(
        'accounts.Company',
        on_delete=models.CASCADE,
        null=True,
        verbose_name='Firma',
        db_index=True,
    )
    STATUS_NEW = 'nowa'
    STATUS_DISPUTED = 'sporna'
    STATUS_ACCEPTED = 'zaakceptowana'
    STATUS_SENT_FOR_PAYMENT = 'przekazano_do_oplacenia'
    STATUS_PAID = 'oplacona'

    STATUS_CHOICES = [
        (STATUS_NEW, 'Nowa'),
        (STATUS_DISPUTED, 'Sporna'),
        (STATUS_ACCEPTED, 'Zaakceptowana'),
        (STATUS_SENT_FOR_PAYMENT, 'Przekazano do opłacenia'),
        (STATUS_PAID, 'Opłacona'),
    ]

    STATUS_COLORS = {
        STATUS_NEW: 'primary',
        STATUS_DISPUTED: 'danger',
        STATUS_ACCEPTED: 'success',
        STATUS_SENT_FOR_PAYMENT: 'warning',
        STATUS_PAID: 'secondary',
    }

    # Identyfikatory KSeF
    ksef_reference_number = models.CharField(
        max_length=64, db_index=True,
        verbose_name='Numer referencyjny KSeF',
    )
    invoice_number = models.CharField(
        max_length=64, db_index=True,
        verbose_name='Numer faktury',
    )

    # Sprzedawca
    seller_name = models.CharField(max_length=255, verbose_name='Nazwa sprzedawcy')
    seller_nip = models.CharField(max_length=10, db_index=True, verbose_name='NIP sprzedawcy')
    seller_address = models.TextField(blank=True, verbose_name='Adres sprzedawcy')

    # Nabywca
    buyer_nip = models.CharField(max_length=10, verbose_name='NIP nabywcy')

    # Kwoty
    amount_net = models.DecimalField(
        max_digits=15, decimal_places=2, verbose_name='Kwota netto',
    )
    amount_vat = models.DecimalField(
        max_digits=15, decimal_places=2, verbose_name='Kwota VAT',
    )
    amount_gross = models.DecimalField(
        max_digits=15, decimal_places=2, verbose_name='Kwota brutto',
    )
    currency = models.CharField(max_length=3, default='PLN', verbose_name='Waluta')

    # Split payment
    is_split_payment = models.BooleanField(default=False, verbose_name='Mechanizm podzielonej płatności')
    vat_amount_split = models.DecimalField(
        max_digits=15, decimal_places=2, null=True, blank=True,
        verbose_name='Kwota VAT (split payment)',
    )

    # Daty
    issue_date = models.DateField(db_index=True, verbose_name='Data wystawienia')
    payment_due_date = models.DateField(null=True, blank=True, db_index=True, verbose_name='Termin płatności')

    # Dane płatności
    bank_account_number = models.CharField(
        max_length=34, blank=True,
        verbose_name='Numer rachunku bankowego sprzedawcy (NRB)',
    )
    payment_title = models.CharField(
        max_length=255, blank=True,
        verbose_name='Tytuł płatności',
    )
    payment_date = models.DateField(
        null=True, blank=True,
        verbose_name='Data zapłaty (z XML)',
    )
    payment_form = models.CharField(
        max_length=30, blank=True,
        verbose_name='Forma płatności',
    )

    # Status
    status = models.CharField(
        max_length=30, choices=STATUS_CHOICES,
        default=STATUS_NEW, db_index=True,
        verbose_name='Status',
    )

    # Notatki
    notes = models.TextField(blank=True, verbose_name='Notatki')

    # Rodzaj dokumentu i opis
    invoice_type = models.CharField(
        max_length=20, blank=True,
        verbose_name='Rodzaj faktury',  # VAT, KOR, ZAL, ROZ, UPR, ...
    )
    description = models.TextField(blank=True, verbose_name='Opis przedmiotu')

    # Surowe dane XML
    raw_xml = models.TextField(blank=True, verbose_name='Surowy XML FA(2)/FA(3)')

    # Metadane
    synced_at = models.DateTimeField(auto_now_add=True, verbose_name='Data synchronizacji')
    updated_at = models.DateTimeField(auto_now=True, verbose_name='Data aktualizacji')
    updated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name='invoices_updated',
        verbose_name='Zaktualizowane przez',
    )

    class Meta:
        verbose_name = 'Faktura kosztowa'
        verbose_name_plural = 'Faktury kosztowe'
        ordering = ['-issue_date', '-synced_at']
        unique_together = [('ksef_reference_number', 'company')]
        indexes = [
            models.Index(fields=['status', 'issue_date']),
            models.Index(fields=['seller_nip', 'status']),
            models.Index(fields=['payment_due_date', 'status']),
            models.Index(fields=['issue_date']),
        ]

    def __str__(self):
        return f'{self.invoice_number} / {self.seller_name}'

    def get_status_color(self) -> str:
        return self.STATUS_COLORS.get(self.status, 'secondary')

    def is_overdue(self) -> bool:
        if not self.payment_due_date:
            return False
        if self.status in (self.STATUS_PAID, self.STATUS_SENT_FOR_PAYMENT):
            return False
        return self.payment_due_date < timezone.localdate()

    def can_be_selected_for_payment(self) -> bool:
        return self.status == self.STATUS_ACCEPTED and bool(self.bank_account_number)


class InvoiceStatusLog(models.Model):
    invoice = models.ForeignKey(
        Invoice, on_delete=models.CASCADE,
        related_name='status_logs',
        verbose_name='Faktura',
    )
    old_status = models.CharField(max_length=30, verbose_name='Poprzedni status')
    new_status = models.CharField(max_length=30, verbose_name='Nowy status')
    changed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL,
        verbose_name='Zmienione przez',
    )
    changed_at = models.DateTimeField(auto_now_add=True, verbose_name='Data zmiany')
    note = models.TextField(blank=True, verbose_name='Notatka')

    class Meta:
        verbose_name = 'Log statusu faktury'
        verbose_name_plural = 'Logi statusów faktur'
        ordering = ['-changed_at']
        indexes = [models.Index(fields=['invoice', 'changed_at'])]

    def __str__(self):
        return f'{self.invoice} | {self.old_status} → {self.new_status}'
