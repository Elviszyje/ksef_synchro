import csv
import io
from decimal import Decimal

from django.test import SimpleTestCase

from apps.invoices.models import Invoice
from apps.payments.generators.elixir import ElixirGenerator


class ElixirSplitPaymentTests(SimpleTestCase):
    def setUp(self):
        self.generator = ElixirGenerator('61109010140000071219812874', 'Moja Firma', 'ul. Testowa 10')

    def _invoice(self, **kwargs):
        defaults = dict(invoice_number='01/10/2026', seller_name='Budmax, S.A.', seller_nip='9194821999',
                        seller_address='Katowice', amount_gross=Decimal('24600.00'), amount_vat=Decimal('4600.00'),
                        is_split_payment=True, bank_account_number='02168000004268465632122330')
        return Invoice(**{**defaults, **kwargs})

    def _fields(self, inv):
        line = self.generator.generate([inv]).decode('cp1250')
        return next(csv.reader(io.StringIO(line)))

    def test_vat_amount_keeps_decimal_comma(self):
        """Specyfikacja Elixir-0 (format_danych.pdf s. 15–17): /VAT/23,09/ — z przecinkiem."""
        fields = self._fields(self._invoice())
        self.assertEqual(len(fields), 17)
        self.assertTrue(fields[11].startswith('/VAT/4600,00/IDC/9194821999/INV/01/10/2026/TXT/'), fields[11])

    def test_commas_outside_vat_amount_are_still_removed(self):
        fields = self._fields(self._invoice(invoice_number='A,B/1', vat_amount_split=Decimal('0.01')))
        self.assertEqual(len(fields), 17)
        self.assertTrue(fields[11].startswith('/VAT/0,01/'), fields[11])
        self.assertNotIn(',', fields[11].removeprefix('/VAT/0,01'))

    def test_standard_transfer_unchanged(self):
        fields = self._fields(self._invoice(is_split_payment=False))
        self.assertEqual(fields[11], 'Faktura 01/10/2026')
        self.assertEqual(fields[2], '2460000')
