"""
Generator XML FA(3) dla faktur wychodzących.

Produkuje XML zgodny ze schematem http://crd.gov.pl/wzor/2025/06/25/13775/
(od 1.02.2026 KSeF przyjmuje wyłącznie FA(3)). Zgodność jest sprawdzana
w testach walidacją XSD (apps/ksef/tests/test_generator.py).
"""
import logging
from collections import defaultdict
from datetime import datetime, timezone
from decimal import Decimal, ROUND_HALF_UP

from lxml import etree

logger = logging.getLogger(__name__)

FA3_NS = 'http://crd.gov.pl/wzor/2025/06/25/13775/'

# Kody form płatności (TFormaPlatnosci)
_PAYMENT_FORM_CODES = {
    'gotowka': '1',
    'przelew': '6',
}

# Stawka z formularza → (pole netto, pole VAT albo None, wartość P_12 w wierszu)
# P_13_1: 23%, P_13_2: 8%, P_13_3: 5%, P_13_6_1: 0% krajowe,
# P_13_7: zwolnione, P_13_8: niepodlegające (dostawy poza krajem).
_VAT_RATES = {
    '23': ('P_13_1', 'P_14_1', '23'),
    '8':  ('P_13_2', 'P_14_2', '8'),
    '5':  ('P_13_3', 'P_14_3', '5'),
    '0':  ('P_13_6_1', None, '0 KR'),
    'zw': ('P_13_7', None, 'zw'),
    'np': ('P_13_8', None, 'np I'),
}

# Rodzaj podstawy zwolnienia → pole FA(3)
_EXEMPTION_FIELDS = {
    'ustawa': 'P_19A',     # przepis ustawy albo aktu wydanego na jej podstawie
    'dyrektywa': 'P_19B',  # przepis dyrektywy 2006/112/WE
    'inna': 'P_19C',       # inna podstawa prawna
}

# Kolejność pól sum w sekwencji Fa (wymagana przez XSD).
_TOTALS_ORDER = ['P_13_1', 'P_14_1', 'P_13_2', 'P_14_2', 'P_13_3', 'P_14_3', 'P_13_6_1', 'P_13_7', 'P_13_8']


def _el(parent, tag: str, text: str | None = None, **attribs) -> etree._Element:
    """Tworzy element XML z opcjonalnym tekstem i atrybutami."""
    child = etree.SubElement(parent, f'{{{FA3_NS}}}{tag}', **attribs)
    if text is not None:
        child.text = str(text)
    return child


def _fmt_decimal(value: Decimal, places: int = 2) -> str:
    quantized = value.quantize(Decimal(10) ** -places, rounding=ROUND_HALF_UP)
    return str(quantized)


def _fmt_quantity(value: Decimal) -> str:
    """Ilość bez zbędnych zer: 2.000 → 2, 1.500 → 1.5."""
    text = _fmt_decimal(value, places=3)
    return text.rstrip('0').rstrip('.') if '.' in text else text


class FA3GeneratorError(Exception):
    pass


class FA3Generator:
    """Generuje XML FA(3) z modelu OutgoingInvoice."""

    def generate(self, invoice, company, config, items=None, now: datetime | None = None) -> bytes:
        """
        Zwraca UTF-8 zakodowany XML FA(3).
        invoice  — apps.outgoing.models.OutgoingInvoice
        company  — apps.accounts.models.Company
        config   — apps.ksef.models.KSeFConfig (NIP sprzedawcy)
        items    — pozycje; domyślnie invoice.items posortowane po lp
        now      — czas wytworzenia (DataWytworzeniaFa); domyślnie teraz
        """
        items = list(items if items is not None else invoice.items.order_by('lp'))
        if not items:
            raise FA3GeneratorError('Faktura nie ma żadnych pozycji.')
        if invoice.payment_form == 'przelew' and not company.bank_account:
            raise FA3GeneratorError('Brak numeru konta bankowego firmy. Uzupełnij dane firmy.')
        unsupported = sorted({i.vat_rate for i in items} - set(_VAT_RATES))
        if unsupported:
            raise FA3GeneratorError(f'Nieobsługiwana stawka VAT: {", ".join(unsupported)}.')
        has_exempt = any(i.vat_rate == 'zw' for i in items)
        exemption_basis = (getattr(invoice, 'vat_exemption_basis', '') or '').strip()
        if has_exempt and not exemption_basis:
            # FA(3) wymaga podstawy prawnej zwolnienia (P_19A/B/C) przy stawce ZW.
            raise FA3GeneratorError('Faktura ze stawką ZW wymaga podania podstawy prawnej zwolnienia z VAT.')

        root = etree.Element(f'{{{FA3_NS}}}Faktura', nsmap={None: FA3_NS})
        self._build_naglowek(root, now or datetime.now(timezone.utc))
        self._build_podmiot1(root, company, config)
        self._build_podmiot2(root, invoice)
        self._build_fa(root, invoice, company, items, exemption_basis if has_exempt else '')
        return etree.tostring(root, xml_declaration=True, encoding='UTF-8', pretty_print=True)

    # ------------------------------------------------------------------ #
    # Sekcje główne                                                        #
    # ------------------------------------------------------------------ #

    def _build_naglowek(self, root, now: datetime):
        nagl = _el(root, 'Naglowek')
        _el(nagl, 'KodFormularza', 'FA', kodSystemowy='FA (3)', wersjaSchemy='1-0E')
        _el(nagl, 'WariantFormularza', '3')
        _el(nagl, 'DataWytworzeniaFa', now.astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))
        _el(nagl, 'SystemInfo', 'KSeF Invoices')

    def _build_podmiot1(self, root, company, config):
        """Sprzedawca — firma wystawiająca fakturę."""
        p1 = _el(root, 'Podmiot1')
        dane = _el(p1, 'DaneIdentyfikacyjne')
        _el(dane, 'NIP', config.nip)
        _el(dane, 'Nazwa', company.name)
        self._build_adres(p1, company.address)

    def _build_podmiot2(self, root, invoice):
        """Nabywca."""
        p2 = _el(root, 'Podmiot2')
        dane = _el(p2, 'DaneIdentyfikacyjne')
        _el(dane, 'NIP', invoice.buyer_nip)
        _el(dane, 'Nazwa', invoice.buyer_name)
        if invoice.buyer_address.strip():
            self._build_adres(p2, invoice.buyer_address)
        # JST / GV: 2 = faktura nie dotyczy jednostki podrzędnej JST ani członka grupy VAT
        _el(p2, 'JST', '2')
        _el(p2, 'GV', '2')

    def _build_adres(self, parent, address: str):
        l1, l2 = self._split_address(address)
        adres = _el(parent, 'Adres')
        _el(adres, 'KodKraju', 'PL')
        _el(adres, 'AdresL1', l1 or '-')
        if l2:
            _el(adres, 'AdresL2', l2)

    def _build_fa(self, root, invoice, company, items, exemption_basis: str = ''):
        fa = _el(root, 'Fa')
        _el(fa, 'KodWaluty', invoice.currency)
        _el(fa, 'P_1', invoice.issue_date.strftime('%Y-%m-%d'))
        _el(fa, 'P_2', invoice.invoice_number)
        if invoice.delivery_date:
            _el(fa, 'P_6', invoice.delivery_date.strftime('%Y-%m-%d'))

        self._build_vat_totals(fa, items)
        gross_total = sum((i.amount_gross for i in items), Decimal('0.00'))
        _el(fa, 'P_15', _fmt_decimal(gross_total))

        self._build_adnotacje(fa, invoice, exemption_basis)
        _el(fa, 'RodzajFaktury', 'VAT')

        for item in items:
            self._build_fa_wiersz(fa, item)

        self._build_platnosc(fa, invoice, company)

    def _build_vat_totals(self, fa, items):
        """Sumy netto/VAT per stawka; para P_13_x/P_14_x występuje razem."""
        totals: dict[str, Decimal] = defaultdict(Decimal)
        for item in items:
            net_field, vat_field, _ = _VAT_RATES[item.vat_rate]
            totals[net_field] += item.amount_net
            if vat_field:
                totals[vat_field] += item.amount_vat
        for field in _TOTALS_ORDER:
            if field in totals:
                _el(fa, field, _fmt_decimal(totals[field]))

    def _build_adnotacje(self, fa, invoice, exemption_basis: str):
        """
        Adnotacje są obowiązkowe. Faktura z formularza nie stosuje metody kasowej,
        samofakturowania, odwrotnego obciążenia, MPP, nowych środków transportu,
        procedury uproszczonej ani marży. Zwolnienie (P_19) — gdy są pozycje ZW.
        """
        adn = _el(fa, 'Adnotacje')
        for field in ('P_16', 'P_17', 'P_18', 'P_18A'):
            _el(adn, field, '2')
        zwolnienie = _el(adn, 'Zwolnienie')
        if exemption_basis:
            _el(zwolnienie, 'P_19', '1')
            basis_field = _EXEMPTION_FIELDS.get(getattr(invoice, 'vat_exemption_type', ''), 'P_19A')
            _el(zwolnienie, basis_field, exemption_basis[:256])
        else:
            _el(zwolnienie, 'P_19N', '1')
        _el(_el(adn, 'NoweSrodkiTransportu'), 'P_22N', '1')
        _el(adn, 'P_23', '2')
        _el(_el(adn, 'PMarzy'), 'P_PMarzyN', '1')

    def _build_fa_wiersz(self, fa, item):
        row = _el(fa, 'FaWiersz')
        _el(row, 'NrWierszaFa', str(item.lp))
        _el(row, 'P_7', item.name)
        _el(row, 'P_8A', item.unit)
        _el(row, 'P_8B', _fmt_quantity(item.quantity))      # ilość
        _el(row, 'P_9A', _fmt_decimal(item.unit_price_net))  # cena jednostkowa netto
        _el(row, 'P_11', _fmt_decimal(item.amount_net))      # wartość netto
        _el(row, 'P_12', _VAT_RATES[item.vat_rate][2])

    def _build_platnosc(self, fa, invoice, company):
        platnosc = _el(fa, 'Platnosc')
        termin = _el(platnosc, 'TerminPlatnosci')
        _el(termin, 'Termin', invoice.payment_due_date.strftime('%Y-%m-%d'))
        _el(platnosc, 'FormaPlatnosci', _PAYMENT_FORM_CODES.get(invoice.payment_form, '6'))
        if invoice.payment_form == 'przelew' and company.bank_account:
            rachunek = _el(platnosc, 'RachunekBankowy')
            _el(rachunek, 'NrRB', company.bank_account.replace(' ', ''))

    # ------------------------------------------------------------------ #
    # Pomocnicze                                                           #
    # ------------------------------------------------------------------ #

    @staticmethod
    def _split_address(address: str) -> tuple[str, str]:
        """Dzieli adres na AdresL1 i AdresL2 (max 2 linie)."""
        lines = [ln.strip() for ln in address.splitlines() if ln.strip()]
        if len(lines) >= 2:
            return lines[0], lines[1]
        if lines:
            return lines[0], ''
        return '', ''
