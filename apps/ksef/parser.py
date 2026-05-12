"""
Parser XML FA — obsługuje FA(2) i FA(3) (auto-detect namespace).
"""
import logging
from dataclasses import dataclass, field
from decimal import Decimal, InvalidOperation
from typing import Optional

from lxml import etree

logger = logging.getLogger(__name__)

# Znane namespace'y schematu FA
_KNOWN_NS = [
    'http://crd.gov.pl/wzor/2023/06/29/12648/',  # FA(2)
    'http://crd.gov.pl/wzor/2024/06/19/12648/',  # FA(3) potencjalny
]


def _detect_ns(root) -> dict:
    """Wykrywa namespace 'fa' z głównego elementu XML."""
    tag = root.tag
    if tag.startswith('{'):
        ns_uri = tag[1:tag.index('}')]
        return {'fa': ns_uri}
    # Fallback: spróbuj zadeklarowanych namespace'ów
    for ns_uri in _KNOWN_NS:
        if ns_uri in (root.nsmap.values() if hasattr(root, 'nsmap') else []):
            return {'fa': ns_uri}
    return {'fa': _KNOWN_NS[0]}


def _text(el, path: str, ns: dict) -> str:
    node = el.find(path, ns)
    return (node.text or '').strip() if node is not None else ''


def _decimal(el, path: str, ns: dict) -> Decimal:
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
    Parsuje XML faktury KSeF — obsługuje FA(2) i FA(3) przez auto-detect namespace.
    """

    def parse(self, xml_bytes: bytes, ksef_reference_number: str = '') -> ParsedInvoice:
        result = ParsedInvoice(ksef_reference_number=ksef_reference_number)
        result.raw_xml = xml_bytes.decode('utf-8', errors='replace')

        try:
            root = etree.fromstring(xml_bytes)
        except etree.XMLSyntaxError as e:
            logger.error('XML parse error for %s: %s', ksef_reference_number, e)
            return result

        NS = _detect_ns(root)

        # Numer faktury
        result.invoice_number = _text(root, './/fa:Fa/fa:P_2', NS) or _text(root, './/fa:Naglowek/fa:NumerFaktury', NS)

        # Daty
        result.issue_date = _text(root, './/fa:Fa/fa:P_1', NS) or _text(root, './/fa:Naglowek/fa:DataWystawienia', NS)
        result.payment_due_date = self._extract_payment_due(root, NS)

        # Sprzedawca (Podmiot1)
        podmiot1 = root.find('.//fa:Podmiot1', NS)
        if podmiot1 is not None:
            result.seller_nip = _text(podmiot1, 'fa:DaneIdentyfikacyjne/fa:NIP', NS)
            result.seller_name = (
                _text(podmiot1, 'fa:DaneIdentyfikacyjne/fa:PelnaNazwa', NS)
                or ' '.join(filter(None, [
                    _text(podmiot1, 'fa:DaneIdentyfikacyjne/fa:Imie', NS),
                    _text(podmiot1, 'fa:DaneIdentyfikacyjne/fa:Nazwisko', NS),
                ]))
            )
            result.seller_address = self._extract_address(podmiot1, NS)

        # Nabywca (Podmiot2)
        podmiot2 = root.find('.//fa:Podmiot2', NS)
        if podmiot2 is not None:
            result.buyer_nip = _text(podmiot2, 'fa:DaneIdentyfikacyjne/fa:NIP', NS)

        # Kwoty
        result.amount_net, result.amount_vat, result.amount_gross = self._extract_amounts(root, NS)

        # Waluta
        result.currency = (
            _text(root, './/fa:Fa/fa:KodWaluty', NS)
            or _text(root, './/fa:Naglowek/fa:KodWaluty', NS)
            or 'PLN'
        )

        # Split payment
        mpp = _text(root, './/fa:Platnosc/fa:MechanizmPodzielonejPlatnosci', NS)
        result.is_split_payment = mpp == 'T'

        # Numer rachunku bankowego sprzedawcy
        result.bank_account_number = self._extract_bank_account(root, NS)

        # Tytuł płatności
        result.payment_title = f'Faktura {result.invoice_number}'

        return result

    def _extract_payment_due(self, root, NS) -> Optional[str]:
        due = _text(root, './/fa:Platnosc/fa:TerminPlatnosci/fa:Termin', NS)
        if due:
            return due
        return _text(root, './/fa:Platnosc/fa:DataZaplaty', NS) or None

    def _extract_address(self, podmiot, NS) -> str:
        ulica = _text(podmiot, 'fa:Adres/fa:AdresL1', NS)
        miejscowosc = _text(podmiot, 'fa:Adres/fa:AdresL2', NS)
        parts = [p for p in [ulica, miejscowosc] if p]
        return ', '.join(parts)[:60]

    def _extract_amounts(self, root, NS) -> tuple[Decimal, Decimal, Decimal]:
        net = _decimal(root, './/fa:Fa/fa:P_15', NS)
        gross = _decimal(root, './/fa:Fa/fa:P_9', NS)
        vat = gross - net if gross and net else Decimal('0')

        if net == 0:
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

    def _extract_bank_account(self, root, NS) -> str:
        # FA(2)/FA(3): rachunek bankowy w sekcji Platnosc lub Podmiot1.
        # Pole to NrRB (nie NumerRachunku) w węźle NrKonta lub RachunekBankowy.
        for path in [
            './/fa:Platnosc/fa:NrKonta/fa:NrRB',
            './/fa:Platnosc/fa:RachunekBankowy/fa:NrRB',
            './/fa:Platnosc/fa:RachunekBankowy/fa:NumerRachunku',
            './/fa:Podmiot1/fa:NrKonta/fa:NrRB',
            './/fa:Podmiot1/fa:RachunekBankowy/fa:NrRB',
            './/fa:Podmiot1/fa:RachunekBankowy/fa:NumerRachunku',
        ]:
            raw = _text(root, path, NS)
            if not raw:
                continue
            acc = raw.replace(' ', '').upper()
            if acc.startswith('PL'):
                acc = acc[2:]
            if len(acc) == 26 and acc.isdigit():
                return acc
        return ''
