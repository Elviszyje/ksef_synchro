"""
Parser wyciągów CSV eksportowanych z VeloBank (dawniej BNP Paribas Consumer Finance / BGŻOptima).

Format pliku (eksport "Historia rachunku"):
- Separator: przecinek (,)
- Kodowanie: UTF-8 (z BOM lub bez)
- Wiersz 1 (nagłówek wyciągu):
    data_wyciagu, data_waluty, numer_rachunku (ze znakiem ' na początku), nazwa_posiadacza,
    waluta, saldo_otwarcia, saldo_zamkniecia, liczba_transakcji
- Wiersze 2..N (transakcje):
    data_operacji, data_waluty, opis, nadawca_odbiorca, nr_rachunku_kontrahenta, kwota, saldo, lp
- Kwoty: polskie separatory — spacja jako separator tysięcy, przecinek jako dziesiętny
  np. "12 865,31" lub "-2 383,35" (w cudzysłowach)
- Daty: DD-MM-YYYY
"""

import csv
import io
import re
from datetime import date, datetime
from decimal import Decimal, InvalidOperation

from .base import ParsedStatement, ParsedTransaction

_RE_NRB = re.compile(r"^['\s]*(\d[\d\s]{23,}\d)\s*$")
_MIN_TX_COLS = 6


def _parse_date(s: str) -> date:
    s = s.strip()
    for fmt in ('%d-%m-%Y', '%Y-%m-%d', '%d.%m.%Y'):
        try:
            return datetime.strptime(s, fmt).date()
        except ValueError:
            continue
    raise ValueError(f'Nieznany format daty: {s!r}')


def _parse_amount(s: str) -> Decimal:
    """Konwertuje '12 865,31' lub '-2 383,35' (polskie formatowanie) na Decimal."""
    clean = s.strip().strip('"').replace('\xa0', ' ').replace(' ', '').replace(',', '.')
    try:
        return Decimal(clean)
    except InvalidOperation:
        raise ValueError(f'Nieznana kwota: {s!r}')


def detect(content: str) -> bool:
    """Zwraca True jeśli plik wygląda jak eksport CSV VeloBank."""
    try:
        reader = csv.reader(io.StringIO(content.lstrip('﻿')))
        rows = [row for row in reader if any(c.strip() for c in row)]
        if len(rows) < 2:
            return False
        header = rows[0]
        # Wiersz nagłówkowy ma co najmniej 8 pól
        if len(header) < 8:
            return False
        # Pole 2 (index 2) zawiera NRB (cyfry + opcjonalne spacje)
        nrb_raw = header[2].strip().lstrip("'")
        digits = nrb_raw.replace(' ', '')
        if not digits.isdigit() or len(digits) != 26:
            return False
        # Pierwsze pole transakcji (index 0 w rows[1]) to data DD-MM-YYYY
        tx_row = rows[1]
        if len(tx_row) < _MIN_TX_COLS:
            return False
        try:
            _parse_date(tx_row[0])
        except ValueError:
            return False
        return True
    except Exception:
        return False


def parse(content: str) -> ParsedStatement:
    """Parsuje plik CSV VeloBank i zwraca ParsedStatement."""
    content = content.lstrip('﻿')
    reader = csv.reader(io.StringIO(content))
    rows = [row for row in reader if any(c.strip() for c in row)]

    if len(rows) < 1:
        raise ValueError('Pusty plik CSV.')

    # Wiersz nagłówkowy
    header = rows[0]
    stmt = ParsedStatement(bank_key='velobank')

    # Numer rachunku z pola 2 (usuń apostrof)
    if len(header) > 2:
        nrb_raw = header[2].strip().lstrip("'")
        stmt.account_number = nrb_raw.replace(' ', '')

    # Data wyciągu z pola 0 (format YYYY-MM-DD w nagłówku)
    if len(header) > 0 and header[0].strip():
        try:
            stmt.statement_date = _parse_date(header[0].strip())
        except ValueError:
            pass

    # Transakcje
    for row in rows[1:]:
        if len(row) < _MIN_TX_COLS:
            continue
        try:
            tx_date = _parse_date(row[0])
            val_date_str = row[1].strip()
            val_date = _parse_date(val_date_str) if val_date_str else tx_date
            description = row[2].strip()
            counterparty = row[3].strip()
            amount = _parse_amount(row[5])
            # reference: nadawca/odbiorca (wyświetlany osobno w UI)
            # description: tylko tytuł przelewu (używany przez InvoiceMatcher)
            reference = counterparty or (row[4].strip() if len(row) > 4 else '')
            stmt.transactions.append(ParsedTransaction(
                transaction_date=tx_date,
                value_date=val_date,
                amount=abs(amount),
                currency='PLN',
                is_credit=amount >= 0,
                description=description,
                reference=reference,
            ))
        except (ValueError, IndexError):
            continue

    return stmt
