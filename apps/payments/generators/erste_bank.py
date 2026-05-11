"""
Generator pliku płatności Erste Bank Polska (.txt).
Format: separatorem jest | (pipe), kodowanie Windows-1250.
Nagłówek: 4120414|1
Typ 1 — przelew zwykły (obcy)
Typ 6 — split payment (mechanizm podzielonej płatności)
Specyfikacja: /Users/bartoszkolek/KSeF/format_danych.pdf
"""
from apps.invoices.models import Invoice
from .base import BasePaymentGenerator, format_amount

SEP = '|'
FILE_VERSION = '4120414'
PACK_TYPE_NORMAL = '1'

TRANS_TYPE_ELIXIR = '1'
TRANS_TYPE_SORBNET = '6'
TRANS_TYPE_EXPRESS = '8'


class ErsteBankGenerator(BasePaymentGenerator):
    ENCODING = 'windows-1250'
    EXTENSION = 'txt'

    def _header_lines(self) -> list[str]:
        return [f'{FILE_VERSION}{SEP}{PACK_TYPE_NORMAL}']

    def _invoice_lines(self, inv: Invoice, line_number: int) -> list[str]:
        if inv.is_split_payment:
            return [self._build_split_payment_line(inv)]
        return [self._build_standard_line(inv)]

    def _build_standard_line(self, inv: Invoice) -> str:
        """
        Format typ 1 (przelew obcy):
        1|RachWN|RachMA|NazwaOdbiorcy|Adres|Kwota|TypTrans|Tytułem|DataRealizacji|[NIP]|
        """
        name = self._clean_text(inv.seller_name, 80)
        address = self._clean_text(inv.seller_address or f'NIP {inv.seller_nip}', 60)
        title = self._clean_text(f'Faktura {inv.invoice_number}', 140)
        account_ma = inv.bank_account_number

        fields = [
            '1',
            self.debit_account,
            account_ma,
            name,
            address,
            format_amount(inv.amount_gross),
            TRANS_TYPE_ELIXIR,
            title,
            '',                     # data realizacji — pusta = natychmiast
            inv.seller_nip or '',   # NIP do weryfikacji Białej Listy
            '',                     # trailing separator wymaga pustego pola
        ]
        return SEP.join(fields)

    def _build_split_payment_line(self, inv: Invoice) -> str:
        """
        Format typ 6 (split payment):
        6|RachWN|RachMA|NazwaOdbircy|Adres|KwotaBrutto|TypTrans|/VAT/.../IDC/.../INV/.../TXT/...|DataRealizacji|
        """
        vat_amount = inv.vat_amount_split if inv.vat_amount_split else inv.amount_vat
        invoice_nr = self._clean_text(inv.invoice_number, 35)
        free_text = self._clean_text(f'Faktura {inv.invoice_number}', 33)

        title = (
            f'/VAT/{format_amount(vat_amount)}'
            f'/IDC/{inv.seller_nip}'
            f'/INV/{invoice_nr}'
            f'/TXT/{free_text}'
        )

        name = self._clean_text(inv.seller_name, 80)
        address = self._clean_text(inv.seller_address or f'NIP {inv.seller_nip}', 60)

        fields = [
            '6',
            self.debit_account,
            inv.bank_account_number,
            name,
            address,
            format_amount(inv.amount_gross),
            TRANS_TYPE_ELIXIR,
            title[:140],
            '',     # data realizacji
            '',     # trailing separator
        ]
        return SEP.join(fields)
