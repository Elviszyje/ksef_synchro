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
    'http://crd.gov.pl/wzor/2024/06/19/12648/',  # FA(3) — wersja robocza
    'http://crd.gov.pl/wzor/2025/06/25/13775/',  # FA(3) — wersja produkcyjna
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


_PAYMENT_FORMS = {
    '1': 'gotówka',
    '2': 'karta',
    '3': 'bon/voucher',
    '4': 'czek',
    '5': 'kredyt',
    '6': 'przelew',
    '7': 'płatność mobilna',
}


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

    invoice_type: str = ''
    description: str = ''

    is_split_payment: bool = False
    vat_amount_split: Optional[Decimal] = None

    bank_account_number: str = ''
    payment_title: str = ''

    is_paid: bool = False
    payment_date: Optional[str] = None
    payment_form: str = ''

    raw_xml: str = ''


def parse_line_items(raw_xml: str) -> list[dict]:
    """
    Zwraca listę pozycji faktury (FaWiersz) z raw_xml.
    Każda pozycja: nr, name, unit, qty, unit_price, net_value, vat_rate.
    """
    if not raw_xml:
        return []
    try:
        root = etree.fromstring(raw_xml.encode('utf-8', errors='replace'))
    except etree.XMLSyntaxError:
        return []

    NS = _detect_ns(root)
    items = []
    for wiersz in root.findall('.//fa:FaWiersz', NS):
        items.append({
            'nr':         _text(wiersz, 'fa:NrWierszaFa', NS),
            'name':       _text(wiersz, 'fa:P_7', NS),
            'unit':       _text(wiersz, 'fa:P_8A', NS),
            'qty':        _text(wiersz, 'fa:P_8B', NS),
            'unit_price': _text(wiersz, 'fa:P_9A', NS),
            'net_value':  _text(wiersz, 'fa:P_11', NS),
            'vat_rate':   _text(wiersz, 'fa:P_12', NS),
        })
    return items


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
            result.seller_nip = (
                _text(podmiot1, 'fa:DaneIdentyfikacyjne/fa:NIP', NS)
                or _text(podmiot1, './/fa:NIP', NS)
            )
            # FA(2): PelnaNazwa; FA(3): Nazwa — oba warianty
            result.seller_name = (
                _text(podmiot1, 'fa:DaneIdentyfikacyjne/fa:PelnaNazwa', NS)
                or _text(podmiot1, 'fa:DaneIdentyfikacyjne/fa:Nazwa', NS)
                or _text(podmiot1, './/fa:PelnaNazwa', NS)
                or _text(podmiot1, './/fa:Nazwa', NS)
                or ' '.join(filter(None, [
                    _text(podmiot1, './/fa:Imie', NS),
                    _text(podmiot1, './/fa:Nazwisko', NS),
                ]))
            )
            if not result.seller_name:
                logger.warning('KSeF: brak nazwy sprzedawcy (NIP=%s ref=%s); podmiot1 XML: %s',
                               result.seller_nip, ksef_reference_number,
                               etree.tostring(podmiot1, encoding='unicode')[:500])
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

        # Rodzaj faktury (VAT, KOR, ZAL, ...)
        result.invoice_type = _text(root, './/fa:RodzajFaktury', NS)

        # Opis — unikalne wartości P_7 z wierszy faktury
        p7_values: list[str] = []
        seen: set[str] = set()
        for wiersz in root.findall('.//fa:FaWiersz', NS):
            val = _text(wiersz, 'fa:P_7', NS)
            if val and val not in seen:
                seen.add(val)
                p7_values.append(val)
        result.description = '; '.join(p7_values)

        # Split payment
        mpp = _text(root, './/fa:Platnosc/fa:MechanizmPodzielonejPlatnosci', NS)
        result.is_split_payment = mpp == 'T'

        # Dane zapłaty
        result.is_paid = _text(root, './/fa:Platnosc/fa:Zaplacono', NS) == '1'
        result.payment_date = _text(root, './/fa:Platnosc/fa:DataZaplaty', NS) or None
        form_code = _text(root, './/fa:Platnosc/fa:FormaPlatnosci', NS)
        result.payment_form = _PAYMENT_FORMS.get(form_code, form_code)

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
        # P_15 = łączna kwota należności (brutto)
        # P_13_X = suma netto dla stawki X (1=23%, 2=8%, 3=5%, 4=0%, 5=zw, 6=oo, 7=np)
        # P_14_X = suma VAT dla stawki X (nie istnieje dla zw/oo/np)
        gross = _decimal(root, './/fa:Fa/fa:P_15', NS)

        net = Decimal('0')
        vat = Decimal('0')
        for i in range(1, 8):
            net += _decimal(root, f'.//fa:Fa/fa:P_13_{i}', NS)
            vat += _decimal(root, f'.//fa:Fa/fa:P_14_{i}', NS)

        if net == 0:
            # Fallback: sumuj wartości netto z wierszy faktury
            for wiersz in root.findall('.//fa:FaWiersz', NS):
                net += _decimal(wiersz, 'fa:P_11', NS)
            # P_12 to kod stawki ("23", "zw", ...) — VAT obliczamy jako gross-net
            if net and gross:
                vat = gross - net

        if not gross and net:
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
