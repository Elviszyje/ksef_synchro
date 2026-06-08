"""
Parser wyciągów CSV eksportowanych z Erste Bank (Santander Consumer Bank / George).

Format pliku:
- Separator: średnik (;)
- Kodowanie: Windows-1250 lub UTF-8
- Nagłówek: "Nr rachunku";"Data transakcji";"Data księgowania";"Opis transakcji";"Kwota";"Waluta";"Saldo..."
- Daty: DD.MM.YYYY
- Kwoty: "1 234,56" lub "-1 234,56" (spacja jako separator tysięcy, przecinek dziesiętny)
- Kredyt/debet: znak kwoty
"""

import csv
import io
import re
from datetime import date, datetime
from decimal import Decimal, InvalidOperation

from .base import ParsedStatement, ParsedTransaction

_RE_DATE = re.compile(r'^\d{2}\.\d{2}\.\d{4}$')
_MIN_TX_COLS = 6

# Możliwe nagłówki kolumn (różne wersje eksportu)
_HEADER_VARIANTS = [
    ['nr rachunku', 'data transakcji', 'data ksiegowania', 'opis transakcji', 'kwota', 'waluta'],
    ['numer rachunku', 'data operacji', 'data waluty', 'opis', 'kwota', 'waluta'],
]


def _parse_date(s: str) -> date:
    s = s.strip().strip('"')
    for fmt in ('%d.%m.%Y', '%Y-%m-%d', '%d-%m-%Y'):
        try:
            return datetime.strptime(s, fmt).date()
        except ValueError:
            continue
    raise ValueError(f'Nieznany format daty: {s!r}')


def _parse_amount(s: str) -> Decimal:
    clean = s.strip().strip('"').replace('\xa0', ' ').replace(' ', '').replace(',', '.')
    try:
        return Decimal(clean)
    except InvalidOperation:
        raise ValueError(f'Nieznana kwota: {s!r}')


def _is_erste_header(row: list[str]) -> bool:
    normalized = [c.strip().strip('"').lower() for c in row]
    for variant in _HEADER_VARIANTS:
        if all(v in normalized for v in variant):
            return True
    # Fallback: sprawdź czy pierwsze pole zawiera "rachunek" lub "konto"
    return bool(normalized and ('rachunek' in normalized[0] or 'konto' in normalized[0]))


def detect(content: str) -> bool:
    """Zwraca True jeśli plik wygląda jak eksport CSV Erste Bank."""
    try:
        for sep in (';', ','):
            reader = csv.reader(io.StringIO(content.lstrip('﻿')), delimiter=sep)
            rows = [row for row in reader if any(c.strip() for c in row)]
            if len(rows) < 2:
                continue
            # Pierwszy wiersz powinien być nagłówkiem kolumn
            if not _is_erste_header(rows[0]):
                continue
            # Sprawdź czy drugi wiersz ma datę w formacie DD.MM.YYYY
            tx_row = rows[1]
            if len(tx_row) < _MIN_TX_COLS:
                continue
            # Szukamy daty w wierszach 1 lub 2
            for col in tx_row[1:3]:
                try:
                    _parse_date(col)
                    return True
                except ValueError:
                    continue
        return False
    except Exception:
        return False


def parse(content: str) -> ParsedStatement:
    """Parsuje plik CSV Erste Bank i zwraca ParsedStatement."""
    content = content.lstrip('﻿')
    stmt = ParsedStatement(bank_key='erste')

    # Spróbuj średnik i przecinek
    separator = ';'
    for sep in (';', ','):
        rows = list(csv.reader(io.StringIO(content), delimiter=sep))
        rows = [r for r in rows if any(c.strip() for c in r)]
        if len(rows) >= 2 and _is_erste_header(rows[0]):
            separator = sep
            break

    reader = csv.reader(io.StringIO(content), delimiter=separator)
    rows = [row for row in reader if any(c.strip() for c in row)]
    if not rows:
        raise ValueError('Pusty plik CSV.')

    header_row = rows[0]
    header = [c.strip().strip('"').lower() for c in header_row]

    # Mapowanie kolumn
    def col(name_variants: list[str]) -> int:
        for name in name_variants:
            if name in header:
                return header.index(name)
        return -1

    idx_account  = col(['nr rachunku', 'numer rachunku', 'rachunek'])
    idx_date1    = col(['data transakcji', 'data operacji', 'data'])
    idx_date2    = col(['data ksiegowania', 'data waluty', 'data księgowania'])
    idx_desc     = col(['opis transakcji', 'opis', 'tytul', 'tytuł'])
    idx_amount   = col(['kwota'])
    idx_currency = col(['waluta'])

    if idx_amount == -1:
        raise ValueError('Nie znaleziono kolumny "Kwota" w pliku CSV.')

    # Numer rachunku z nagłówka (może być w danych 2. wiersza)
    if idx_account >= 0 and len(rows) > 1:
        raw_acc = rows[1][idx_account].strip().strip('"') if idx_account < len(rows[1]) else ''
        stmt.account_number = raw_acc.replace(' ', '')

    for row in rows[1:]:
        if len(row) <= idx_amount:
            continue
        try:
            date1_str = row[idx_date1].strip() if idx_date1 >= 0 and idx_date1 < len(row) else ''
            date2_str = row[idx_date2].strip() if idx_date2 >= 0 and idx_date2 < len(row) else ''
            tx_date = _parse_date(date1_str) if date1_str else None
            val_date = _parse_date(date2_str) if date2_str else tx_date
            if not tx_date:
                continue
            val_date = val_date or tx_date
            description = row[idx_desc].strip().strip('"') if idx_desc >= 0 and idx_desc < len(row) else ''
            amount = _parse_amount(row[idx_amount])
            currency = row[idx_currency].strip().strip('"') if idx_currency >= 0 and idx_currency < len(row) else 'PLN'
            stmt.transactions.append(ParsedTransaction(
                transaction_date=tx_date,
                value_date=val_date,
                amount=abs(amount),
                currency=currency or 'PLN',
                is_credit=amount >= 0,
                description=description,
            ))
            if not stmt.statement_date:
                stmt.statement_date = tx_date
        except (ValueError, IndexError):
            continue

    return stmt
