from decimal import Decimal, ROUND_HALF_UP

from django.db import models, transaction


class Buyer(models.Model):
    company = models.ForeignKey(
        'accounts.Company',
        on_delete=models.CASCADE,
        related_name='buyers',
        null=True,
        verbose_name='Firma',
        db_index=True,
    )
    nip = models.CharField(max_length=10, verbose_name='NIP')
    name = models.CharField(max_length=255, verbose_name='Nazwa')
    address = models.TextField(blank=True, verbose_name='Adres')
    email = models.EmailField(blank=True, verbose_name='E-mail')
    phone = models.CharField(max_length=30, blank=True, verbose_name='Telefon')
    notes = models.TextField(blank=True, verbose_name='Notatki')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['name']
        unique_together = [('company', 'nip')]
        verbose_name = 'Nabywca'
        verbose_name_plural = 'Nabywcy'

    def __str__(self):
        return f'{self.name} ({self.nip})'


class OutgoingInvoice(models.Model):
    STATUS_DRAFT    = 'draft'
    STATUS_QUEUED   = 'queued'
    STATUS_SENDING  = 'sending'
    STATUS_ACCEPTED = 'accepted'
    STATUS_REJECTED = 'rejected'

    STATUS_CHOICES = [
        (STATUS_DRAFT,    'Szkic'),
        (STATUS_QUEUED,   'Oczekuje na wysyłkę'),
        (STATUS_SENDING,  'Wysyłanie'),
        (STATUS_ACCEPTED, 'Zaakceptowana przez KSeF'),
        (STATUS_REJECTED, 'Odrzucona przez KSeF'),
    ]

    STATUS_COLORS = {
        STATUS_DRAFT:    'secondary',
        STATUS_QUEUED:   'info',
        STATUS_SENDING:  'warning',
        STATUS_ACCEPTED: 'success',
        STATUS_REJECTED: 'danger',
    }

    PAYMENT_FORM_TRANSFER = 'przelew'
    PAYMENT_FORM_CASH     = 'gotowka'
    PAYMENT_FORM_CHOICES  = [
        (PAYMENT_FORM_TRANSFER, 'Przelew'),
        (PAYMENT_FORM_CASH,     'Gotówka'),
    ]

    VAT_RATE_23  = '23'
    VAT_RATE_8   = '8'
    VAT_RATE_5   = '5'
    VAT_RATE_0   = '0'
    VAT_RATE_ZW  = 'zw'
    VAT_RATE_NP  = 'np'

    company = models.ForeignKey(
        'accounts.Company',
        on_delete=models.CASCADE,
        related_name='outgoing_invoices',
        verbose_name='Firma',
        db_index=True,
    )
    invoice_number = models.CharField(max_length=64, verbose_name='Numer faktury')
    issue_date = models.DateField(verbose_name='Data wystawienia')
    delivery_date = models.DateField(null=True, blank=True, verbose_name='Data dostawy/wykonania')
    payment_due_date = models.DateField(verbose_name='Termin płatności')
    payment_form = models.CharField(
        max_length=20,
        choices=PAYMENT_FORM_CHOICES,
        default=PAYMENT_FORM_TRANSFER,
        verbose_name='Forma płatności',
    )
    currency = models.CharField(max_length=3, default='PLN', verbose_name='Waluta')

    buyer = models.ForeignKey(
        Buyer,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='invoices',
        verbose_name='Nabywca',
    )
    buyer_nip = models.CharField(max_length=10, verbose_name='NIP nabywcy')
    buyer_name = models.CharField(max_length=255, verbose_name='Nazwa nabywcy')
    buyer_address = models.TextField(verbose_name='Adres nabywcy')

    notes = models.TextField(blank=True, verbose_name='Uwagi')

    status = models.CharField(
        max_length=20,
        choices=STATUS_CHOICES,
        default=STATUS_DRAFT,
        db_index=True,
        verbose_name='Status',
    )
    ksef_submission_reference = models.CharField(
        max_length=255, blank=True,
        verbose_name='Referencja wysyłki KSeF',
    )
    ksef_reference_number = models.CharField(
        max_length=64, blank=True,
        verbose_name='Numer referencyjny KSeF',
    )
    generated_xml = models.TextField(blank=True, verbose_name='Wygenerowany XML')
    upo_xml = models.TextField(blank=True, verbose_name='UPO XML')
    error_message = models.TextField(blank=True, verbose_name='Błąd')

    created_by = models.ForeignKey(
        'accounts.CustomUser',
        on_delete=models.SET_NULL,
        null=True,
        related_name='created_outgoing_invoices',
        verbose_name='Utworzona przez',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Faktura wychodząca'
        verbose_name_plural = 'Faktury wychodzące'
        ordering = ['-created_at']
        constraints = [
            models.UniqueConstraint(
                fields=['company', 'invoice_number'],
                name='unique_outgoing_invoice_number_per_company',
            )
        ]

    def __str__(self):
        return f"{self.invoice_number} → {self.buyer_name}"

    def get_status_color(self):
        return self.STATUS_COLORS.get(self.status, 'secondary')

    @property
    def amount_net(self) -> Decimal:
        return sum((item.amount_net for item in self.items.all()), Decimal('0.00'))

    @property
    def amount_vat(self) -> Decimal:
        return sum((item.amount_vat for item in self.items.all()), Decimal('0.00'))

    @property
    def amount_gross(self) -> Decimal:
        return sum((item.amount_gross for item in self.items.all()), Decimal('0.00'))

    def can_be_edited(self) -> bool:
        return self.status == self.STATUS_DRAFT

    def can_be_queued(self) -> bool:
        return self.status in (self.STATUS_DRAFT, self.STATUS_REJECTED)

    @classmethod
    def generate_number(cls, company) -> str:
        from django.utils import timezone
        year = timezone.now().year
        with transaction.atomic():
            last = (
                cls.objects
                .select_for_update()
                .filter(company=company, invoice_number__startswith=f'FV/{year}/')
                .order_by('-invoice_number')
                .first()
            )
            if last:
                try:
                    seq = int(last.invoice_number.rsplit('/', 1)[-1]) + 1
                except ValueError:
                    seq = 1
            else:
                seq = 1
            return f'FV/{year}/{seq:04d}'


class InvoiceItem(models.Model):
    VAT_RATE_CHOICES = [
        ('23', '23%'),
        ('8',  '8%'),
        ('5',  '5%'),
        ('0',  '0%'),
        ('zw', 'ZW (zwolniony)'),
        ('np', 'NP (nie podlega)'),
    ]

    invoice = models.ForeignKey(
        OutgoingInvoice,
        on_delete=models.CASCADE,
        related_name='items',
        verbose_name='Faktura',
    )
    lp = models.PositiveSmallIntegerField(verbose_name='Lp.')
    name = models.CharField(max_length=255, verbose_name='Nazwa towaru/usługi')
    unit = models.CharField(max_length=30, default='szt.', verbose_name='Jednostka')
    quantity = models.DecimalField(max_digits=10, decimal_places=3, verbose_name='Ilość')
    unit_price_net = models.DecimalField(max_digits=15, decimal_places=2, verbose_name='Cena jedn. netto')
    vat_rate = models.CharField(
        max_length=5,
        choices=VAT_RATE_CHOICES,
        default='23',
        verbose_name='Stawka VAT',
    )
    amount_net = models.DecimalField(max_digits=15, decimal_places=2, verbose_name='Wartość netto')
    amount_vat = models.DecimalField(max_digits=15, decimal_places=2, verbose_name='Kwota VAT')
    amount_gross = models.DecimalField(max_digits=15, decimal_places=2, verbose_name='Wartość brutto')

    class Meta:
        verbose_name = 'Pozycja faktury'
        verbose_name_plural = 'Pozycje faktury'
        ordering = ['lp']

    def __str__(self):
        return f"{self.lp}. {self.name}"

    def calculate_amounts(self):
        net = (self.quantity * self.unit_price_net).quantize(Decimal('0.01'), ROUND_HALF_UP)
        if self.vat_rate in ('zw', 'np', '0'):
            vat = Decimal('0.00')
        else:
            rate = Decimal(self.vat_rate) / 100
            vat = (net * rate).quantize(Decimal('0.01'), ROUND_HALF_UP)
        self.amount_net = net
        self.amount_vat = vat
        self.amount_gross = net + vat

    def save(self, *args, **kwargs):
        self.calculate_amounts()
        super().save(*args, **kwargs)
