from datetime import date
from decimal import Decimal

from django.test import SimpleTestCase

from apps.bank_statements.parsers import erste_csv, millennium, velobank_csv
from apps.bank_statements.parsers.detect import decode_statement, detect_and_parse, is_pdf

HEADER = ['Numer rachunku/karty', 'Data transakcji', 'Data rozliczenia', 'Rodzaj transakcji', 'Na konto/Z konta',
          'Odbiorca/Zleceniodawca', 'Opis', 'Obciążenia', 'Uznania', 'Saldo', 'Waluta']
ROWS = [
    ['PL61 1160 2202 0000 0001 2345 6789', '2026-11-04', '2026-11-05', 'OPŁATA', '67 11 6022 0200 0000 0000 0000 01',
     'Bank Millennium SA', 'OPŁ. MIES. KARTA ZA 10/2026', '-7.00', '', '10574.68', 'PLN'],
    ['PL61 1160 2202 0000 0001 2345 6789', '2026-10-29', '2026-10-29', 'PRZELEW PRZYCHODZĄCY',
     '27 11 4020 0400 0000 3456 7890 12', 'KLIENT SP. Z O.O. UL.POLNA 5', 'FV/2026/0001', '', '4920.00', '10581.68', 'PLN'],
    ['PL61 1160 2202 0000 0001 2345 6789', '2026-10-15', '2026-10-15', 'OPERACJE SO NA KREDYTACH', '', '',
     '', '-1234.45', '', '5661.68', 'PLN'],
]


def _csv() -> bytes:
    lines = [','.join(f'"{c}"' for c in row) for row in [HEADER] + ROWS]
    return ('﻿' + '\r\n'.join(lines) + '\r\n').encode('utf-8')


def _html(currency: bool = True) -> bytes:
    """Jak eksport HTML/XLS: komórki wielowierszowe, <br>, &nbsp;; w XLS pusta waluta."""
    def td(index: int, value: str) -> str:
        if index == 10 and not currency:
            value = '\r\n          '
        elif not value:
            value = '&nbsp;'
        else:
            value = value.replace(' SP. Z O.O. ', ' SP. Z O.O.\r\n')
        return f'<td align="right">{value}<br></td>'
    body = ''.join('<tr>' + ''.join(td(i, c) for i, c in enumerate(row)) + '</tr>\r\n' for row in ROWS)
    head = '<tr>' + ''.join(f'<td class="header">{c}</td>' for c in HEADER) + '</tr>'
    return ('﻿<html><head><style>br {mso-data-placement:same-cell;}</style></head><body>'
            f'<table border="1"><thead>{head}</thead><tbody>{body}</tbody></table></body></html>').encode('utf-8')


class MillenniumParserTests(SimpleTestCase):
    def parse(self, data: bytes):
        content = decode_statement(data)
        self.assertTrue(millennium.detect(content))
        self.assertFalse(erste_csv.detect(content))
        self.assertFalse(velobank_csv.detect(content))
        return detect_and_parse(content)

    def test_csv(self):
        stmt = self.parse(_csv())
        self.assertEqual(stmt.bank_key, 'millennium')
        self.assertEqual(stmt.account_number, '61116022020000000123456789')
        self.assertEqual(stmt.statement_date, date(2026, 11, 4))
        fee, income, loan = stmt.transactions
        self.assertEqual((fee.amount, fee.is_credit, fee.value_date), (Decimal('7.00'), False, date(2026, 11, 5)))
        self.assertEqual((income.amount, income.is_credit), (Decimal('4920.00'), True))
        self.assertEqual(income.counterparty, 'KLIENT SP. Z O.O. UL.POLNA 5')
        self.assertEqual(income.description, 'FV/2026/0001')
        self.assertEqual(income.reference, '27114020040000003456789012')
        self.assertEqual(loan.description, 'OPERACJE SO NA KREDYTACH')  # pusty opis → rodzaj transakcji

    def test_html_and_xls_give_the_same_result_as_csv(self):
        expected = self.parse(_csv())
        self.assertEqual(self.parse(_html()), expected)
        self.assertEqual(self.parse(_html(currency=False)), expected)  # XLS: pusta waluta → PLN

    def test_pdf_is_rejected(self):
        self.assertTrue(is_pdf(b'%PDF-1.4\n...'))
        self.assertFalse(is_pdf(_csv()))

    def test_other_formats_are_not_millennium(self):
        erste = '"Nr rachunku";"Data transakcji";"Data ksiegowania";"Opis transakcji";"Kwota";"Waluta"\r\n'
        self.assertFalse(millennium.detect(erste))
        self.assertFalse(millennium.detect(':20:STARTUMS\r\n:25:/PL61109010140000071219812874\r\n'))
