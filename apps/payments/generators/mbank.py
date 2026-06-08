"""
Generator pliku płatności mBank VideoTel (.txt).
Format: separator ; (średnik), kodowanie CP1250, bez nagłówka.
Pola: RachWN;RachMA;Kwota;NazwaOdbiorcy;Adres1;Adres2;Tytułem;TypPrzelewu
TypPrzelewu: 0 = standardowy (Elixir), 1 = ekspresowy (Sorbnet)
"""
from apps.invoices.models import Invoice
from .base import BasePaymentGenerator, format_amount

SEP = ';'


class MBankGenerator(BasePaymentGenerator):
    ENCODING = 'cp1250'
    EXTENSION = 'txt'

    def _invoice_lines(self, inv: Invoice, line_number: int) -> list[str]:
        return [self._build_line(inv)]

    def _build_line(self, inv: Invoice) -> str:
        name = self._clean_text(inv.seller_name, 35)
        address = self._clean_text(inv.seller_address or f'NIP {inv.seller_nip}', 35)
        title = self._clean_text(f'Faktura {inv.invoice_number}', 105)
        account_ma = inv.bank_account_number.replace(' ', '')

        fields = [
            self.debit_account,
            account_ma,
            format_amount(inv.amount_gross),
            name,
            address,
            '',         # adres linia 2
            title,
            '0',        # typ przelewu: 0=standardowy
        ]
        return SEP.join(fields)
