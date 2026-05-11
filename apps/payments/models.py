from django.conf import settings
from django.db import models


class PaymentFile(models.Model):
    FORMAT_ERSTE = 'erste'
    FORMAT_ELIXIR = 'elixir'
    FORMAT_CHOICES = [
        (FORMAT_ERSTE, 'Erste Bank (.txt)'),
        (FORMAT_ELIXIR, 'Elixir-0 (.pli)'),
    ]

    format = models.CharField(max_length=10, choices=FORMAT_CHOICES, verbose_name='Format pliku')
    file_name = models.CharField(max_length=255, verbose_name='Nazwa pliku')
    file_content = models.BinaryField(verbose_name='Zawartość pliku')
    total_amount = models.DecimalField(max_digits=15, decimal_places=2, verbose_name='Suma brutto')
    invoice_count = models.IntegerField(verbose_name='Liczba faktur')
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL,
        verbose_name='Wygenerowane przez',
    )
    created_at = models.DateTimeField(auto_now_add=True, verbose_name='Data generacji')

    class Meta:
        verbose_name = 'Plik przelewów'
        verbose_name_plural = 'Pliki przelewów'
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.file_name} ({self.invoice_count} fv, {self.total_amount} PLN)'

    def get_content_type(self) -> str:
        return 'text/plain; charset=windows-1250'

    def get_extension(self) -> str:
        return 'txt' if self.format == self.FORMAT_ERSTE else 'pli'


class PaymentFileItem(models.Model):
    payment_file = models.ForeignKey(
        PaymentFile, on_delete=models.CASCADE,
        related_name='items',
        verbose_name='Plik przelewów',
    )
    invoice = models.ForeignKey(
        'invoices.Invoice', on_delete=models.PROTECT,
        related_name='payment_items',
        verbose_name='Faktura',
    )
    amount = models.DecimalField(max_digits=15, decimal_places=2, verbose_name='Kwota')
    line_number = models.PositiveIntegerField(verbose_name='Numer linii w pliku')

    class Meta:
        verbose_name = 'Pozycja pliku przelewów'
        verbose_name_plural = 'Pozycje pliku przelewów'
        unique_together = [('payment_file', 'invoice')]
        ordering = ['line_number']

    def __str__(self):
        return f'{self.payment_file} / {self.invoice}'
