"""
Generator pliku Elixir-0 (.pli).
Format: separatorem jest , (przecinek), kodowanie CP1250.
Pola tekstowe w cudzysłowach. Bez nagłówka.
Specyfikacja: /Users/bartoszkolek/KSeF/format_danych.pdf strony 13-17.
"""
from decimal import Decimal
from datetime import date

from apps.invoices.models import Invoice
from .base import BasePaymentGenerator


def _cents(amount: Decimal) -> str:
    """Kwota w groszach jako integer — dwie ostatnie cyfry to grosze."""
    return str(int(round(amount * 100)))


def _q(text: str) -> str:
    """Opakowuje tekst w cudzysłowy, usuwa znaki specjalne."""
    clean = text.replace('"', '').replace(',', '')
    return f'"{clean}"'


class ElixirGenerator(BasePaymentGenerator):
    ENCODING = 'cp1250'
    EXTENSION = 'pli'

    def _invoice_lines(self, inv: Invoice, line_number: int) -> list[str]:
        today = date.today().strftime('%Y%m%d')

        if inv.is_split_payment:
            return [self._build_split_line(inv, today)]
        return [self._build_standard_line(inv, today)]

    def _build_standard_line(self, inv: Invoice, today: str) -> str:
        """
        Format Elixir-0 (17 pól):
        0,data,kwota,oddzWN,oddzMA,rachWN,rachMA,nazwaNadawcy,nazwaOdbiorcy,,, tytul,,,,, nip
        """
        sender_name = self._clean_text(f'{self.company_name} {self.company_address}', 140)
        receiver_name = self._clean_text(f'{inv.seller_name} {inv.seller_address}', 140)
        title = self._clean_text(f'Faktura {inv.invoice_number}', 140)

        fields = [
            '',                             # opcjonalne — nieużywane
            today,                          # data
            _cents(inv.amount_gross),       # kwota w groszach
            '',                             # nr oddziału Wn (opcjonalne)
            '',                             # nr oddziału Ma (opcjonalne)
            f'"{self.debit_account}"',      # rachunek Wn (NRB 34 cyfry)
            f'"{inv.bank_account_number}"', # rachunek Ma
            _q(sender_name),               # nazwa/adres nadawcy
            _q(receiver_name),             # nazwa/adres odbiorcy
            '',                             # opcjonalne
            '',                             # opcjonalne
            _q(title),                      # tytuł
            '',                             # opcjonalne
            '',                             # opcjonalne
            '',                             # opcjonalne
            '',                             # opcjonalne
            f'"{inv.seller_nip}"' if inv.seller_nip else '""',  # NIP do Białej Listy
        ]
        return ','.join(fields)

    def _build_split_line(self, inv: Invoice, today: str) -> str:
        """Elixir-0 split payment — tytuł w formacie /VAT/.../IDC/.../INV/.../TXT/..."""
        from .base import format_amount
        vat_amount = inv.vat_amount_split if inv.vat_amount_split else inv.amount_vat
        invoice_nr = self._clean_text(inv.invoice_number, 35)
        free_text = self._clean_text(f'Faktura {inv.invoice_number}', 33)

        split_title = (
            f'/VAT/{format_amount(vat_amount)}'
            f'/IDC/{inv.seller_nip}'
            f'/INV/{invoice_nr}'
            f'/TXT/{free_text}'
        )

        sender_name = self._clean_text(f'{self.company_name} {self.company_address}', 140)
        receiver_name = self._clean_text(f'{inv.seller_name} {inv.seller_address}', 140)

        fields = [
            '',
            today,
            _cents(inv.amount_gross),
            '', '',
            f'"{self.debit_account}"',
            f'"{inv.bank_account_number}"',
            _q(sender_name),
            _q(receiver_name),
            '', '',
            _q(split_title[:140]),
            '', '', '', '',
            f'"{inv.seller_nip}"',
        ]
        return ','.join(fields)
