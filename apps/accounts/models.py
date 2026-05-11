from django.contrib.auth.models import AbstractUser
from django.db import models


class CustomUser(AbstractUser):
    ROLE_VIEWER = 'viewer'
    ROLE_ACCOUNTANT = 'accountant'
    ROLE_APPROVER = 'approver'
    ROLE_ADMIN = 'admin'

    ROLES = [
        (ROLE_VIEWER, 'Przeglądający'),
        (ROLE_ACCOUNTANT, 'Księgowy'),
        (ROLE_APPROVER, 'Akceptujący płatności'),
        (ROLE_ADMIN, 'Administrator'),
    ]

    role = models.CharField(
        max_length=20,
        choices=ROLES,
        default=ROLE_VIEWER,
        verbose_name='Rola',
    )

    class Meta(AbstractUser.Meta):
        verbose_name = 'Użytkownik'
        verbose_name_plural = 'Użytkownicy'
        indexes = [models.Index(fields=['role'])]

    def get_role_display_short(self) -> str:
        return dict(self.ROLES).get(self.role, self.role)
