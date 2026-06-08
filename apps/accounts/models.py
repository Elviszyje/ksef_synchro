from datetime import date, timedelta

from django.contrib.auth.models import AbstractUser
from django.db import models
from django.db.models.signals import post_save
from django.dispatch import receiver


class Company(models.Model):
    nip = models.CharField(max_length=10, unique=True, verbose_name='NIP')
    name = models.CharField(max_length=255, verbose_name='Nazwa')
    address = models.TextField(blank=True, verbose_name='Adres')
    bank_account = models.CharField(max_length=34, blank=True, verbose_name='Konto bankowe')
    is_active = models.BooleanField(default=True, verbose_name='Aktywna')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = 'Firma'
        verbose_name_plural = 'Firmy'
        ordering = ['name']

    def __str__(self):
        return f"{self.name} ({self.nip})"


class CompanyBankAccount(models.Model):
    company = models.ForeignKey(
        Company, on_delete=models.CASCADE,
        related_name='bank_accounts',
        verbose_name='Firma',
    )
    account_number = models.CharField(max_length=34, verbose_name='Numer rachunku (NRB)')
    label = models.CharField(max_length=100, blank=True, verbose_name='Etykieta')
    is_default = models.BooleanField(default=False, verbose_name='Domyślny')
    bank_name = models.CharField(max_length=50, blank=True, verbose_name='Bank')
    bank_key = models.CharField(max_length=20, blank=True, verbose_name='Klucz banku')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-is_default', 'label']
        verbose_name = 'Rachunek bankowy'
        verbose_name_plural = 'Rachunki bankowe'

    def __str__(self):
        label = self.label or self.account_number
        return f'{label} ({self.bank_name or "nieznany bank"})'

    def save(self, *args, **kwargs):
        from apps.payments.bank_detection import detect_bank_key, BANK_LABELS
        if self.is_default:
            CompanyBankAccount.objects.filter(
                company=self.company, is_default=True,
            ).exclude(pk=self.pk).update(is_default=False)
        if self.account_number:
            self.account_number = self.account_number.replace(' ', '').replace('-', '')
            self.bank_key = detect_bank_key(self.account_number)
            self.bank_name = BANK_LABELS.get(self.bank_key, '')
        super().save(*args, **kwargs)


class CompanyLicense(models.Model):
    PLAN_FREE = 'free'
    PLAN_STANDARD = 'standard'
    PLAN_ULTRA = 'ultra'
    PLANS = [
        (PLAN_FREE, 'Darmowy'),
        (PLAN_STANDARD, 'Standard'),
        (PLAN_ULTRA, 'Ultra'),
    ]
    PLAN_LIMITS = {
        PLAN_FREE:     {'users': 1, 'invoices': 5,   'outgoing_invoices': 3},
        PLAN_STANDARD: {'users': 2, 'invoices': 100, 'outgoing_invoices': 50},
        PLAN_ULTRA:    {'users': 5, 'invoices': None, 'outgoing_invoices': None},
    }

    company = models.OneToOneField(
        Company, on_delete=models.CASCADE,
        related_name='license', verbose_name='Firma',
    )
    plan = models.CharField(max_length=20, choices=PLANS, default=PLAN_FREE, verbose_name='Plan')
    valid_from = models.DateField(verbose_name='Ważna od')
    valid_until = models.DateField(null=True, blank=True, verbose_name='Ważna do')
    is_active = models.BooleanField(default=True, verbose_name='Aktywna')

    store_platform = models.CharField(max_length=20, blank=True, verbose_name='Platforma sklepu')
    store_purchase_token = models.TextField(blank=True, verbose_name='Token zakupu')
    store_subscription_id = models.CharField(max_length=255, blank=True, verbose_name='ID subskrypcji')
    store_last_verified_at = models.DateTimeField(null=True, blank=True, verbose_name='Ostatnia weryfikacja')

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Licencja'
        verbose_name_plural = 'Licencje'

    def __str__(self):
        return f"{self.company} — {self.get_plan_display()}"

    def user_limit(self) -> int:
        return self.PLAN_LIMITS[self.plan]['users']

    def invoice_limit(self) -> int | None:
        return self.PLAN_LIMITS[self.plan]['invoices']

    def invoices_last_30_days(self) -> int:
        from django.utils import timezone as dj_tz
        from apps.invoices.models import Invoice
        cutoff = dj_tz.now() - timedelta(days=30)
        return Invoice.objects.filter(company=self.company, synced_at__gte=cutoff).count()

    def can_sync_invoice(self) -> bool:
        limit = self.invoice_limit()
        return limit is None or self.invoices_last_30_days() < limit

    def can_add_user(self) -> bool:
        return self.company.users.filter(is_active=True).count() < self.user_limit()

    def outgoing_invoice_limit(self) -> int | None:
        return self.PLAN_LIMITS[self.plan]['outgoing_invoices']

    def outgoing_invoices_this_month(self) -> int:
        from django.utils import timezone as dj_tz
        from apps.outgoing.models import OutgoingInvoice
        now = dj_tz.now()
        return OutgoingInvoice.objects.filter(
            company=self.company,
            status__in=[
                OutgoingInvoice.STATUS_QUEUED,
                OutgoingInvoice.STATUS_SENDING,
                OutgoingInvoice.STATUS_ACCEPTED,
            ],
            created_at__year=now.year,
            created_at__month=now.month,
        ).count()

    def can_send_outgoing_invoice(self) -> bool:
        limit = self.outgoing_invoice_limit()
        return limit is None or self.outgoing_invoices_this_month() < limit


@receiver(post_save, sender=Company)
def create_default_license(sender, instance, created, **kwargs):
    if created:
        CompanyLicense.objects.get_or_create(
            company=instance,
            defaults={'plan': CompanyLicense.PLAN_FREE, 'valid_from': date.today()},
        )


class CustomUser(AbstractUser):
    ROLE_VIEWER = 'viewer'
    ROLE_ACCOUNTANT = 'accountant'
    ROLE_APPROVER = 'approver'
    ROLE_ADMIN = 'admin'
    ROLE_SUPER_ADMIN = 'super_admin'

    ROLES = [
        (ROLE_VIEWER, 'Przeglądający'),
        (ROLE_ACCOUNTANT, 'Księgowy'),
        (ROLE_APPROVER, 'Akceptujący płatności'),
        (ROLE_ADMIN, 'Administrator firmy'),
        (ROLE_SUPER_ADMIN, 'Super administrator'),
    ]

    role = models.CharField(
        max_length=20,
        choices=ROLES,
        default=ROLE_VIEWER,
        verbose_name='Rola',
    )
    company = models.ForeignKey(
        Company,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='users',
        verbose_name='Firma',
    )

    class Meta(AbstractUser.Meta):
        verbose_name = 'Użytkownik'
        verbose_name_plural = 'Użytkownicy'
        indexes = [models.Index(fields=['role'])]

    def get_role_display_short(self) -> str:
        return dict(self.ROLES).get(self.role, self.role)
