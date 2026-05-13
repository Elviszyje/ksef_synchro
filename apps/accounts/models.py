from django.contrib.auth.models import AbstractUser
from django.db import models


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
