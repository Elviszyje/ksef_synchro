"""
Parser XML FA(2) — schemat faktur KSeF 2.0.
Namespace: http://crd.gov.pl/wzor/2023/06/29/12648/
"""
import logging
from dataclasses import dataclass, field
from decimal import Decimal, InvalidOperation
from typing import Optional

from lxml import etree

logger = logging.getLogger(__name__)

FA2_NS = 'http://crd.gov.pl/wzor/2023/06/29/12648/'
NS = {'fa': FA2_NS}


def _tag(local: str) -> str:
    return f'{{{FA2_NS}}}{local}'


def _text(el, path: str, ns: dict = NS) -> str:
    node = el.find(path, ns)
    return (node.text or '').strip() if node is not None else ''


def _decimal(el, path: str, ns: dict = NS) -> Decimal:
    val = _text(el, path, ns).replace(',', '.').replace(' ', '')
    try:
        return Decimal(val)
    except InvalidOperation:
        return Decimal('0')


@dataclass
class ParsedInvoice:
    invoice_number: str = ''
    ksef_reference_number: str = ''
    issue_date: Optional[str] = None
    payment_due_date: Optional[str] = None

    seller_name: str = ''
    seller_nip: str = ''
    seller_address: str = ''

    buyer_nip: str = ''

    amount_net: Decimal = field(default_factory=lambda: Decimal('0'))
    amount_vat: Decimal = field(default_factory=lambda: Decimal('0'))
    amount_gross: Decimal = field(default_factory=lambda: Decimal('0'))
    currency: str = 'PLN'

    is_split_payment: bool = False
    vat_amount_split: Optional[Decimal] = None

    bank_account_number: str = ''
    payment_title: str = ''

    raw_xml: str = ''


class FA2Parser:
    """
    Parsuje XML faktury KSeF FA(2).
    Zwraca ParsedInvoice z wypełnionymi polami.
    """

    def parse(self, xml_bytes: bytes, ksef_reference_number: str = '') -> ParsedInvoice:
        result = ParsedInvoice(ksef_reference_number=ksef_reference_number)
        result.raw_xml = xml_bytes.decode('utf-8', errors='replace')

        try:
            root = etree.fromstring(xml_bytes)
        except etree.XMLSyntaxError as e:
            logger.error('XML parse error for %s: %s', ksef_reference_number, e)
            return result

        # Numer faktury
        result.invoice_number = _text(root, './/fa:Fa/fa:P_2', NS) or _text(root, './/fa:Naglowek/fa:NumerFaktury', NS)

        # Daty
        result.issue_date = _text(root, './/fa:Fa/fa:P_1', NS) or _text(root, './/fa:Naglowek/fa:DataWystawienia', NS)
        result.payment_due_date = self._extract_payment_due(root)

        # Sprzedawca (Podmiot1)
        podmiot1 = root.find('.//fa:Podmiot1', NS)
        if podmiot1 is not None:
            result.seller_nip = _text(podmiot1, 'fa:DaneIdentyfikacyjne/fa:NIP', NS)
            result.seller_name = _text(podmiot1, 'fa:DaneIdentyfikacyjne/fa:PelnaNazwa', NS)
            result.seller_address = self._extract_address(podmiot1)

        # Nabywca (Podmiot2)
        podmiot2 = root.find('.//fa:Podmiot2', NS)
        if podmiot2 is not None:
            result.buyer_nip = _text(podmiot2, 'fa:DaneIdentyfikacyjne/fa:NIP', NS)

        # Kwoty — suma z wierszy lub wartości zbiorczych
        result.amount_net, result.amount_vat, result.amount_gross = self._extract_amounts(root)

        # Waluta
        result.currency = _text(root, './/fa:Fa/fa:P_1M', NS) or 'PLN'

        # Split payment
        mpp = _text(root, './/fa:Platnosc/fa:MechanizmPodzielonejPlatnosci', NS)
        result.is_split_payment = mpp == 'T'

        # Numer rachunku bankowego sprzedawcy
        result.bank_account_number = self._extract_bank_account(root)

        # Tytuł płatności
        result.payment_title = f'Faktura {result.invoice_number}'

        return result

    def _extract_payment_due(self, root) -> Optional[str]:
        # Szukamy terminu płatności
        due = _text(root, './/fa:Platnosc/fa:TerminPlatnosci/fa:Termin', NS)
        if due:
            return due
        # Alternatywne pole
        return _text(root, './/fa:Platnosc/fa:DataZaplaty', NS) or None

    def _extract_address(self, podmiot) -> str:
        ulica = _text(podmiot, 'fa:Adres/fa:AdresL1', NS)
        miejscowosc = _text(podmiot, 'fa:Adres/fa:AdresL2', NS)
        parts = [p for p in [ulica, miejscowosc] if p]
        return ', '.join(parts)[:60]

    def _extract_amounts(self, root) -> tuple[Decimal, Decimal, Decimal]:
        # Próba ze zbiorczych pól FA
        net = _decimal(root, './/fa:Fa/fa:P_15', NS)
        gross = _decimal(root, './/fa:Fa/fa:P_9', NS)
        vat = gross - net if gross and net else Decimal('0')

        if net == 0:
            # Zsumuj wiersze
            net_sum = Decimal('0')
            vat_sum = Decimal('0')
            for wiersz in root.findall('.//fa:Fa/fa:FaWiersz', NS):
                net_sum += _decimal(wiersz, 'fa:P_11', NS)
                vat_sum += _decimal(wiersz, 'fa:P_12', NS)
            if net_sum:
                net = net_sum
                vat = vat_sum
                gross = net + vat

        return net, vat, gross

    def _extract_bank_account(self, root) -> str:
        # Szukamy NRB w danych płatności
        for path in [
            './/fa:Platnosc/fa:RachunekBankowy/fa:NumerRachunku',
            './/fa:Podmiot1/fa:RachunekBankowy/fa:NumerRachunku',
        ]:
            acc = _text(root, path, NS)
            if acc:
                # Normalizuj — usuń spacje, PL prefix
                acc = acc.replace(' ', '').replace('PL', '')
                if len(acc) == 26 and acc.isdigit():
                    return acc
        return ''
