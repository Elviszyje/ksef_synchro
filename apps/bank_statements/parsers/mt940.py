"""
Parser SWIFT MT940.
Obsługiwane tagi: :20: :25: :28C: :60F: :60M: :61: :86: :62F: :62M:
"""
import re
import logging
from dataclasses import dataclass, field
from datetime import date
from decimal import Decimal, InvalidOperation
from typing import Optional

logger = logging.getLogger(__name__)

# Wzorzec wyodrębniania pól MT940
RE_FIELD = re.compile(r':(\d{2}[A-Z]?):(.*?)(?=:\d{2}[A-Z]?:|\Z)', re.DOTALL)

# Tag :61: — linia transakcji
# Format: YYMMDD[MMDD]D/CAmount[N]TrRefNo[/AccOwnerInfo]\nNarrative
RE_61 = re.compile(
    r'^(\d{6})(\d{4})?'          # data waluty (YYMMDD) + data transakcji (MMDD opcjonalnie)
    r'(R?[DC])'                   # D=debit, C=credit, RD=reverse debit, RC=reverse credit
    r'([A-Z]{0,3})'               # waluta (opcjonalnie)
    r'([\d,]+)'                   # kwota
    r'([A-Z]{4})'                 # typ transakcji (np. NTRF)
    r'(.{0,16})'                  # referencja transakcji (max 16 znaków)
    r'(?://(.{0,16}))?'           # referencja konta właściciela (opcjonalnie)
    r'(?:\r?\n(.*))?$',           # opis (może być multiline w :86:)
    re.DOTALL,
)


@dataclass
class MT940Transaction:
    transaction_date: date
    value_date: date
    amount: Decimal
    currency: str
    is_credit: bool
    reference: str
    description: str


@dataclass
class MT940Statement:
    account_number: str = ''
    statement_date: Optional[date] = None
    transactions: list[MT940Transaction] = field(default_factory=list)


def _parse_date6(s: str, ref_year: int = 2000) -> date:
    """Parsuje datę YYMMDD."""
    yy = int(s[0:2])
    mm = int(s[2:4])
    dd = int(s[4:6])
    year = 2000 + yy if yy < 50 else 1900 + yy
    return date(year, mm, dd)


def _parse_amount(s: str) -> Decimal:
    """Zamienia '1234,56' na Decimal('1234.56')."""
    try:
        return Decimal(s.replace(',', '.'))
    except InvalidOperation:
        return Decimal('0')


class MT940Parser:

    def parse(self, content: str) -> MT940Statement:
        # Normalizacja — usuń BOM, zunifikuj CRLF
        content = content.strip('﻿').replace('\r\n', '\n').replace('\r', '\n')

        stmt = MT940Statement()
        fields = self._extract_fields(content)

        for tag, value in fields:
            tag_clean = tag.upper()
            if tag_clean == '25':
                stmt.account_number = value.strip().replace(' ', '').replace('/', '')
            elif tag_clean in ('60F', '60M'):
                stmt.statement_date = self._parse_balance_date(value)
            elif tag_clean == '61':
                tx = self._parse_transaction_61(value, stmt.statement_date)
                if tx:
                    stmt.transactions.append(tx)
            # :86: dołączane do ostatniej transakcji
            elif tag_clean == '86' and stmt.transactions:
                last = stmt.transactions[-1]
                extra = value.strip().replace('\n', ' ')
                last.description = f'{last.description} {extra}'.strip() if last.description else extra

        return stmt

    def _extract_fields(self, content: str) -> list[tuple[str, str]]:
        return [(m.group(1), m.group(2)) for m in RE_FIELD.finditer(content)]

    def _parse_balance_date(self, value: str) -> Optional[date]:
        # Format: C/D YYMMDD ISO-Currency Amount
        # np.: C250511EUR1234,56
        m = re.match(r'[CD](\d{6})', value)
        if m:
            try:
                return _parse_date6(m.group(1))
            except ValueError:
                pass
        return None

    def _parse_transaction_61(self, raw: str, ref_date: Optional[date]) -> Optional[MT940Transaction]:
        raw = raw.strip()
        lines = raw.split('\n')
        first_line = lines[0]

        m = RE_61.match(raw)
        if not m:
            # Spróbuj prostszy wzorzec
            m2 = re.match(r'^(\d{6})(\d{4})?(R?[DC])([A-Z]{0,3})([\d,]+)(.+)', first_line)
            if not m2:
                logger.debug('Nie można sparsować :61: %s', raw[:60])
                return None
            value_date_str = m2.group(1)
            dc = m2.group(3)
            amount_str = m2.group(5)
            reference = m2.group(6)[:35] if m2.group(6) else ''
            description = ' '.join(lines[1:]) if len(lines) > 1 else ''
        else:
            value_date_str = m.group(1)
            dc = m.group(3)
            amount_str = m.group(5)
            reference = (m.group(7) or '').strip()
            description = (m.group(9) or '').strip()

        try:
            value_date = _parse_date6(value_date_str)
        except ValueError:
            value_date = ref_date or date.today()

        amount = _parse_amount(amount_str)
        is_credit = 'C' in dc.upper() and 'D' not in dc.upper()

        return MT940Transaction(
            transaction_date=value_date,
            value_date=value_date,
            amount=amount,
            currency='PLN',
            is_credit=is_credit,
            reference=reference,
            description=description,
        )


# ─── Matcher ─────────────────────────────────────────────────────────────────

class InvoiceMatcher:
    """
    Dopasowuje transakcje bankowe do faktur.

    Hierarchia pewności:
    1. (high)   kwota brutto + numer faktury w opisie
    2. (high)   kwota brutto + NIP sprzedawcy w opisie
    3. (medium) kwota brutto (jeśli unikalna wśród faktur w statusie sent_for_payment)
    4. (low)    kwota brutto (wszystkie niezapłacone)
    """

    RE_NIP = re.compile(r'(?:NIP\s*:?\s*)?(\d{10})')
    RE_INVOICE_NR = re.compile(
        r'(?:INVOICE|FAKTURA|FVS|FVZ|FV|INV|F-)\s*(?:NR\.?|NO\.?)?\s*[:\s/]?\s*([^\s,;|]{3,35})',
        re.IGNORECASE,
    )

    def match(self, transactions: list[MT940Transaction], invoices_qs) -> list[dict]:
        """
        Zwraca listę dopasowań:
        {transaction, invoice, match_type, confidence}
        """
        results = []
        invoice_list = list(invoices_qs)
        by_amount: dict[Decimal, list] = {}
        for inv in invoice_list:
            key = Decimal(str(inv.amount_gross)).quantize(Decimal('0.01'))
            by_amount.setdefault(key, []).append(inv)

        for tx in transactions:
            if tx.is_credit:
                continue  # faktury kosztowe opłacamy przelewem wychodzącym (debit)

            candidates = by_amount.get(Decimal(str(tx.amount)).quantize(Decimal('0.01')), [])
            if not candidates:
                continue

            matched = self._find_best_match(tx, candidates)
            if matched:
                results.append(matched)

        return results

    def _find_best_match(self, tx: MT940Transaction, candidates: list) -> Optional[dict]:
        from apps.bank_statements.models import TransactionMatch

        desc = tx.description.upper()

        # 1. Kwota + numer faktury
        invoice_nr_match = self.RE_INVOICE_NR.search(tx.description)
        if invoice_nr_match:
            nr = self._normalize_invoice_nr(invoice_nr_match.group(1))
            for inv in candidates:
                if self._normalize_invoice_nr(inv.invoice_number) == nr:
                    return {
                        'transaction': tx,
                        'invoice': inv,
                        'match_type': TransactionMatch.MATCH_INVOICE_NR,
                        'confidence': TransactionMatch.CONFIDENCE_HIGH,
                    }

        # 2. Kwota + NIP
        nip_matches = self.RE_NIP.findall(tx.description)
        for nip in nip_matches:
            for inv in candidates:
                if inv.seller_nip == nip:
                    return {
                        'transaction': tx,
                        'invoice': inv,
                        'match_type': TransactionMatch.MATCH_NIP,
                        'confidence': TransactionMatch.CONFIDENCE_HIGH,
                    }

        # 3. Unikalna kwota
        if len(candidates) == 1:
            return {
                'transaction': tx,
                'invoice': candidates[0],
                'match_type': TransactionMatch.MATCH_AMOUNT,
                'confidence': TransactionMatch.CONFIDENCE_MEDIUM,
            }

        return None

    @staticmethod
    def _normalize_invoice_nr(nr: str) -> str:
        # Rozdziel na segmenty, usuń wiodące zera z każdego segmentu liczbowego,
        # żeby "01/05/2026" == "1/05/2026" i "FV/0030/26" == "FV/030/26"
        segments = re.split(r'[\s\-/]+', nr.strip())
        normalized = []
        for seg in segments:
            seg = seg.upper()
            # jeśli segment jest czysto liczbowy — usuń wiodące zera
            if seg.isdigit():
                seg = str(int(seg)) if seg else seg
            normalized.append(seg)
        return ''.join(normalized)


# ─── Interfejs kompatybilny z detect_and_parse ────────────────────────────────

def detect(content: str) -> bool:
    """Zwraca True jeśli plik zawiera znaczniki SWIFT MT940."""
    return bool(re.search(r':\d{2}[A-Z]?:', content[:500]))


def parse_to_statement(content: str):
    """Parsuje MT940 i zwraca ParsedStatement (kompatybilny z innymi parserami)."""
    from .base import ParsedStatement, ParsedTransaction
    raw = MT940Parser().parse(content)
    stmt = ParsedStatement(
        account_number=raw.account_number,
        statement_date=raw.statement_date,
        bank_key='mt940',
    )
    for tx in raw.transactions:
        stmt.transactions.append(ParsedTransaction(
            transaction_date=tx.transaction_date,
            value_date=tx.value_date,
            amount=tx.amount,
            currency=tx.currency,
            is_credit=tx.is_credit,
            description=tx.description,
            reference=tx.reference,
        ))
    return stmt
