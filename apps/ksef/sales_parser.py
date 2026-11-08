"""
Parser faktur sprzedażowych pobranych z KSeF (firma jest sprzedawcą, Subject1).

Służy do importu faktur wystawionych poza aplikacją (np. w Aplikacji Podatnika
KSeF albo w innym programie). Wynik odwzorowuje model OutgoingInvoice: pozycje
mają kwoty z XML, a nie przeliczone na nowo, więc sumy zgadzają się z fakturą
w KSeF co do grosza.

Ta sama logika jest przeniesiona do aplikacji iOS (`SalesImport.swift`) —
zmiany trzeba wprowadzać w obu miejscach.
"""
from dataclasses import dataclass, field
from datetime import date
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from typing import Optional

from lxml import etree

from apps.ksef.parser import _detect_ns, _text, FA2Parser

_CENT = Decimal('0.01')

# Kod stawki P_12 → (stawka w modelu, pole VAT sumy P_14_x albo None).
# Stawki historyczne i szczególne są przybliżane do najbliższej obsługiwanej
# w formularzu (22→23, 7→8, ryczałt taxi 4/3→5, odwrotne obciążenie oo→np);
# kwoty pozostają dokładne, bo pochodzą z XML.
_RATE_CODES = {
    '23': ('23', 'P_14_1'), '22': ('23', 'P_14_1'),
    '8': ('8', 'P_14_2'), '7': ('8', 'P_14_2'),
    '5': ('5', 'P_14_3'),
    '4': ('5', 'P_14_4'), '3': ('5', 'P_14_4'),
    '0': ('0', None), '0 KR': ('0', None), '0 WDT': ('0', None), '0 EX': ('0', None),
    'zw': ('zw', None),
    'oo': ('np', None), 'np': ('np', None), 'np I': ('np', None), 'np II': ('np', None),
}

_VAT_PERCENT = {'23': Decimal('23'), '22': Decimal('22'), '8': Decimal('8'), '7': Decimal('7'),
                '5': Decimal('5'), '4': Decimal('4'), '3': Decimal('3')}

# Sumy netto w nagłówku → (stawka w modelu, pole VAT albo None) — do pozycji zbiorczych.
_NET_TOTALS = [
    ('P_13_1', '23', 'P_14_1'), ('P_13_2', '8', 'P_14_2'), ('P_13_3', '5', 'P_14_3'),
    ('P_13_4', '5', 'P_14_4'), ('P_13_5', '23', 'P_14_5'),
    ('P_13_6_1', '0', None), ('P_13_6_2', '0', None), ('P_13_6_3', '0', None),
    ('P_13_7', 'zw', None), ('P_13_8', 'np', None), ('P_13_9', 'np', None),
    ('P_13_10', 'np', None), ('P_13_11', 'np', None),
]

_RATE_LABELS = {'23': '23%', '8': '8%', '5': '5%', '0': '0%', 'zw': 'ZW', 'np': 'NP'}

_EXEMPTION_FIELDS = [('P_19A', 'ustawa'), ('P_19B', 'dyrektywa'), ('P_19C', 'inna')]


@dataclass
class ParsedSaleItem:
    name: str
    unit: str
    quantity: Decimal
    unit_price_net: Decimal
    vat_rate: str
    amount_net: Decimal
    amount_vat: Decimal
    vat_field: Optional[str] = None

    @property
    def amount_gross(self) -> Decimal:
        return self.amount_net + self.amount_vat


@dataclass
class ParsedSale:
    invoice_number: str = ''
    issue_date: str = ''
    delivery_date: Optional[str] = None
    payment_due_date: str = ''
    payment_form: str = 'przelew'
    currency: str = 'PLN'
    bank_account_number: str = ''
    buyer_nip: str = ''
    buyer_name: str = ''
    buyer_address: str = ''
    notes: str = ''
    vat_exemption_type: str = 'ustawa'
    vat_exemption_basis: str = ''
    invoice_type: str = ''
    items: list[ParsedSaleItem] = field(default_factory=list)

    @property
    def amount_gross(self) -> Decimal:
        return sum((i.amount_gross for i in self.items), Decimal('0.00'))


def _round(value: Decimal) -> Decimal:
    return value.quantize(_CENT, rounding=ROUND_HALF_UP)


def _optional_decimal(el, path: str, ns: dict) -> Optional[Decimal]:
    raw = _text(el, path, ns).replace(',', '.').replace(' ', '')
    if not raw:
        return None
    try:
        return Decimal(raw)
    except InvalidOperation:
        return None


def _iso_date(text: str) -> Optional[str]:
    try:
        return date.fromisoformat(text[:10]).isoformat()
    except ValueError:
        return None


def parse_sales_invoice(xml_bytes: bytes) -> Optional[ParsedSale]:
    """Zwraca dane faktury albo None, gdy XML jest nieczytelny lub nie ma numeru faktury."""
    try:
        root = etree.fromstring(xml_bytes)
    except etree.XMLSyntaxError:
        return None
    ns = _detect_ns(root)
    fa = root.find('.//fa:Fa', ns)
    if fa is None:
        return None

    sale = ParsedSale()
    sale.invoice_number = _text(fa, 'fa:P_2', ns)[:64]
    sale.issue_date = _iso_date(_text(fa, 'fa:P_1', ns))
    if not sale.invoice_number or not sale.issue_date:
        return None
    sale.delivery_date = _iso_date(_text(fa, 'fa:P_6', ns))
    sale.payment_due_date = _iso_date(_text(fa, './/fa:Platnosc/fa:TerminPlatnosci/fa:Termin', ns)) or sale.issue_date
    sale.payment_form = 'gotowka' if _text(fa, './/fa:Platnosc/fa:FormaPlatnosci', ns) == '1' else 'przelew'
    sale.currency = (_text(fa, 'fa:KodWaluty', ns) or 'PLN')[:3].upper()
    sale.bank_account_number = FA2Parser()._extract_bank_account(root, ns)
    sale.invoice_type = _text(fa, 'fa:RodzajFaktury', ns)

    buyer = root.find('.//fa:Podmiot2', ns)
    if buyer is not None:
        sale.buyer_nip = _text(buyer, 'fa:DaneIdentyfikacyjne/fa:NIP', ns)
        sale.buyer_name = (_text(buyer, 'fa:DaneIdentyfikacyjne/fa:Nazwa', ns)
                           or sale.buyer_nip or 'Nabywca bez nazwy')
        lines = [_text(buyer, 'fa:Adres/fa:AdresL1', ns), _text(buyer, 'fa:Adres/fa:AdresL2', ns)]
        sale.buyer_address = '\n'.join(line for line in lines if line)

    for field_name, exemption_type in _EXEMPTION_FIELDS:
        basis = _text(fa, f'fa:Adnotacje/fa:Zwolnienie/fa:{field_name}', ns)
        if basis:
            sale.vat_exemption_type, sale.vat_exemption_basis = exemption_type, basis[:256]
            break

    if sale.invoice_type.startswith('KOR'):
        corrected = _text(fa, './/fa:DaneFaKorygowanej/fa:NrFaKorygowanej', ns)
        sale.notes = f'Korekta faktury {corrected}' if corrected else 'Faktura korygująca'

    sale.items = _line_items(fa, ns)
    _reconcile_vat(sale.items, fa, ns)

    expected_gross = _optional_decimal(fa, 'fa:P_15', ns)
    if not sale.items or (expected_gross is not None and sale.amount_gross != _round(expected_gross)):
        # Korekty, faktury zaliczkowe albo pozycje niezgodne z sumami — pozycje zbiorcze z nagłówka.
        sale.items = _summary_items(fa, ns, sale) or sale.items
    if not sale.items and expected_gross is not None:
        sale.items = [ParsedSaleItem(name=f'Faktura {sale.invoice_number}', unit='szt.', quantity=Decimal('1'),
                                     unit_price_net=_round(expected_gross), vat_rate='np',
                                     amount_net=_round(expected_gross), amount_vat=Decimal('0.00'))]
    return sale


def _line_items(fa, ns) -> list[ParsedSaleItem]:
    items = []
    for row in fa.findall('fa:FaWiersz', ns):
        if _text(row, 'fa:StanPrzed', ns) == '1':
            continue  # stan przed korektą
        code = _text(row, 'fa:P_12', ns)
        rate, vat_field = _RATE_CODES.get(code, ('np', None))
        percent = _VAT_PERCENT.get(code)
        quantity = _optional_decimal(row, 'fa:P_8B', ns)
        if quantity is None:
            quantity = Decimal('1')
        price = _optional_decimal(row, 'fa:P_9A', ns)
        net = _optional_decimal(row, 'fa:P_11', ns)
        gross = _optional_decimal(row, 'fa:P_11A', ns)
        line_vat = _optional_decimal(row, 'fa:P_11Vat', ns)

        if net is None and gross is not None:
            # Faktura liczona od cen brutto (P_9B/P_11A): VAT „w stu”.
            if line_vat is None:
                line_vat = _round(gross * percent / (100 + percent)) if percent else Decimal('0.00')
            net = gross - line_vat
        if net is None:
            net = quantity * (price or Decimal('0'))
        net = _round(net)
        if price is None:
            price = _round(net / quantity) if quantity else net
        vat = line_vat if line_vat is not None else (net * percent / 100 if percent else Decimal('0'))

        items.append(ParsedSaleItem(
            name=(_text(row, 'fa:P_7', ns) or 'Pozycja')[:255],
            unit=(_text(row, 'fa:P_8A', ns) or 'szt.')[:30],
            quantity=quantity.quantize(Decimal('0.001'), rounding=ROUND_HALF_UP),
            unit_price_net=_round(price),
            vat_rate=rate,
            amount_net=net,
            amount_vat=_round(vat),
            vat_field=vat_field,
        ))
    return items


def _reconcile_vat(items: list[ParsedSaleItem], fa, ns) -> None:
    """
    VAT na fakturze liczy się od sumy wartości netto w stawce, więc suma VAT
    z pozycji może różnić się o grosze. Różnicę przypisujemy największej pozycji
    w danej stawce, żeby sumy były równe P_14_x z faktury.
    """
    for vat_field in ('P_14_1', 'P_14_2', 'P_14_3', 'P_14_4'):
        expected = _optional_decimal(fa, f'fa:{vat_field}', ns)
        bucket = [i for i in items if i.vat_field == vat_field]
        if expected is None or not bucket:
            continue
        diff = _round(expected) - sum((i.amount_vat for i in bucket), Decimal('0.00'))
        if diff:
            max(bucket, key=lambda i: abs(i.amount_net)).amount_vat += diff


def _summary_items(fa, ns, sale: ParsedSale) -> list[ParsedSaleItem]:
    prefix = 'Korekta wartości' if sale.invoice_type.startswith('KOR') else 'Wartość'
    items = []
    for net_field, rate, vat_field in _NET_TOTALS:
        net = _optional_decimal(fa, f'fa:{net_field}', ns)
        if not net:
            continue
        vat = (_optional_decimal(fa, f'fa:{vat_field}', ns) or Decimal('0')) if vat_field else Decimal('0')
        items.append(ParsedSaleItem(
            name=f'{prefix} – stawka {_RATE_LABELS[rate]}', unit='szt.', quantity=Decimal('1.000'),
            unit_price_net=_round(net), vat_rate=rate, amount_net=_round(net), amount_vat=_round(vat),
            vat_field=vat_field,
        ))
    return items
