"""
Parser historii transakcji z Banku Millennium (Millenet, „Historia transakcji”).

Bank eksportuje tę samą tabelę w trzech formatach do odczytu maszynowego:
- CSV: separator `,`, wszystkie pola w cudzysłowach, UTF-8 z BOM,
- XLS: w rzeczywistości dokument HTML z tabelą (Excel otwiera go jako arkusz),
  kolumna „Waluta” bywa pusta,
- HTML: ta sama tabela.
Czwarty format, PDF, jest wydrukiem („Dokument nie jest wyciągiem z rachunku
bankowego”) i nie jest obsługiwany.

Kolumny: Numer rachunku/karty, Data transakcji, Data rozliczenia, Rodzaj transakcji,
Na konto/Z konta, Odbiorca/Zleceniodawca, Opis, Obciążenia (ujemne), Uznania, Saldo, Waluta.
Daty YYYY-MM-DD, kwoty z kropką dziesiętną. Pola wielowierszowe (w HTML z <br>
i znakami nowej linii) są sklejane spacjami, tak jak w CSV.

Port w aplikacji iOS: `MillenniumParser` w `CSVStatementParsers.swift`.
"""
import csv
import io
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from typing import Optional

from .base import ParsedStatement, ParsedTransaction

BANK_KEY = 'millennium'

_ACCOUNT = 'numer rachunku/karty'
_TX_DATE = 'data transakcji'
_VALUE_DATE = 'data rozliczenia'
_KIND = 'rodzaj transakcji'
_COUNTER_ACCOUNT = 'na konto/z konta'
_COUNTERPARTY = 'odbiorca/zleceniodawca'
_DESCRIPTION = 'opis'
_DEBIT = 'obciążenia'
_CREDIT = 'uznania'
_CURRENCY = 'waluta'

_REQUIRED = [_ACCOUNT, _TX_DATE, _VALUE_DATE, _COUNTERPARTY, _DESCRIPTION, _DEBIT, _CREDIT]


def _clean(text: str) -> str:
    """Zwija białe znaki (nowe linie, &nbsp;) do pojedynczych spacji."""
    return ' '.join((text or '').replace('\xa0', ' ').split())


def _is_html(text: str) -> bool:
    head = text[:4096].lower()
    return '<table' in head or head.lstrip().startswith('<html')


def _html_rows(text: str) -> list[list[str]]:
    from lxml import html
    try:
        root = html.fromstring(text)
    except Exception:
        return []
    return [[_clean(cell.text_content()) for cell in tr if cell.tag in ('td', 'th')] for tr in root.iter('tr')]


def _rows(content: str) -> list[list[str]]:
    text = content.lstrip('﻿')
    if _is_html(text):
        rows = _html_rows(text)
    else:
        rows = [[_clean(c) for c in row] for row in csv.reader(io.StringIO(text))]
    return [row for row in rows if any(row)]


def _header_index(row: list[str]) -> Optional[dict[str, int]]:
    names = [c.lower() for c in row]
    if not all(name in names for name in _REQUIRED):
        return None
    return {name: i for i, name in enumerate(names)}


def _parse_date(s: str) -> Optional[date]:
    for fmt in ('%Y-%m-%d', '%d-%m-%Y', '%d.%m.%Y'):
        try:
            return datetime.strptime(s.strip(), fmt).date()
        except ValueError:
            continue
    return None


def _parse_amount(s: str) -> Optional[Decimal]:
    clean = s.replace(' ', '').replace(',', '.')
    if not clean:
        return None
    try:
        return Decimal(clean)
    except InvalidOperation:
        return None


def detect(content: str) -> bool:
    try:
        rows = _rows(content)
    except Exception:
        return False
    return len(rows) >= 1 and _header_index(rows[0]) is not None


def parse(content: str) -> ParsedStatement:
    rows = _rows(content)
    if not rows:
        raise ValueError('Pusty plik.')
    columns = _header_index(rows[0])
    if columns is None:
        raise ValueError('Nie rozpoznano nagłówka historii transakcji Banku Millennium.')

    def cell(row: list[str], name: str) -> str:
        i = columns.get(name)
        return row[i] if i is not None and i < len(row) else ''

    stmt = ParsedStatement(bank_key=BANK_KEY)
    for row in rows[1:]:
        tx_date = _parse_date(cell(row, _TX_DATE))
        if tx_date is None:
            continue
        value_date = _parse_date(cell(row, _VALUE_DATE)) or tx_date
        credit = _parse_amount(cell(row, _CREDIT))
        debit = _parse_amount(cell(row, _DEBIT))
        amount = credit if credit is not None else debit
        if amount is None:
            continue
        if not stmt.account_number:
            account = cell(row, _ACCOUNT).replace(' ', '').upper()
            stmt.account_number = account[2:] if account.startswith('PL') else account
        stmt.transactions.append(ParsedTransaction(
            transaction_date=tx_date,
            value_date=value_date,
            amount=abs(amount),
            currency=cell(row, _CURRENCY).upper() or 'PLN',
            is_credit=credit is not None,
            description=cell(row, _DESCRIPTION) or cell(row, _KIND),
            counterparty=cell(row, _COUNTERPARTY),
            reference=cell(row, _COUNTER_ACCOUNT).replace(' ', '')[:35],
        ))
        stmt.statement_date = max(filter(None, [stmt.statement_date, tx_date]))
    return stmt
