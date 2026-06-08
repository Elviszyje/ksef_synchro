"""
Generator XML FA(2) dla faktur wychodzących.
Produkuje XML zgodny ze schematem http://crd.gov.pl/wzor/2023/06/29/12648/
"""
import logging
from collections import defaultdict
from decimal import Decimal, ROUND_HALF_UP

from lxml import etree

logger = logging.getLogger(__name__)

_FA2_NS = 'http://crd.gov.pl/wzor/2023/06/29/12648/'

# Kody form płatności FA(2)
_PAYMENT_FORM_CODES = {
    'gotowka':  '1',
    'przelew':  '6',
}

# Stawki VAT do indeksów P_13/P_14 w FA(2)
_VAT_RATE_INDEX = {
    '23': 1,
    '8':  2,
    '5':  3,
    '0':  4,
}


def _el(parent, tag: str, text: str | None = None, **attribs) -> etree._Element:
    """Tworzy element XML z opcjonalnym tekstem i atrybutami."""
    ns_tag = f'{{{_FA2_NS}}}{tag}'
    child = etree.SubElement(parent, ns_tag, **attribs)
    if text is not None:
        child.text = str(text)
    return child


def _fmt_decimal(value: Decimal, places: int = 2) -> str:
    quantized = value.quantize(Decimal(10) ** -places, rounding=ROUND_HALF_UP)
    return str(quantized)


class FA2GeneratorError(Exception):
    pass


class FA2Generator:
    """Generuje XML FA(2) z modelu OutgoingInvoice."""

    def generate(self, invoice, company, config) -> bytes:
        """
        Zwraca UTF-8 zakodowany XML FA(2).
        invoice  — apps.outgoing.models.OutgoingInvoice
        company  — apps.accounts.models.Company
        config   — apps.ksef.models.KSeFConfig (dla NIP sprzedawcy)
        """
        items = list(invoice.items.order_by('lp'))
        if not items:
            raise FA2GeneratorError('Faktura nie ma żadnych pozycji.')
        if invoice.payment_form == 'przelew' and not company.bank_account:
            raise FA2GeneratorError('Brak numeru konta bankowego firmy. Uzupełnij dane firmy.')

        root = etree.Element(f'{{{_FA2_NS}}}Faktura', nsmap={None: _FA2_NS})

        self._build_naglowek(root)
        self._build_podmiot1(root, company, config)
        self._build_podmiot2(root, invoice)
        self._build_fa(root, invoice, company, items)

        return etree.tostring(root, xml_declaration=True, encoding='UTF-8', pretty_print=True)

    # ------------------------------------------------------------------ #
    # Sekcje główne                                                        #
    # ------------------------------------------------------------------ #

    def _build_naglowek(self, root):
        nagl = _el(root, 'Naglowek')
        _el(nagl, 'KodFormularza',
            'FA',
            kodSystemowy='FA (2)',
            kodPodatku='VAT',
            rodzajZobowiazania='rozliczeniowe',
            wersjaSchemy='1-0E')
        _el(nagl, 'WariantFormularza', '2')
        _el(nagl, 'SystemInfo', 'KSEFV2')

    def _build_podmiot1(self, root, company, config):
        """Sprzedawca — dane firmy wystawiającej fakturę."""
        p1 = _el(root, 'Podmiot1')
        dane = _el(p1, 'DaneIdentyfikacyjne')
        _el(dane, 'NIP', config.nip)
        _el(dane, 'PelnaNazwa', company.name)
        adres = _el(p1, 'Adres')
        l1, l2 = self._split_address(company.address)
        _el(adres, 'KodKraju', 'PL')
        _el(adres, 'AdresL1', l1)
        if l2:
            _el(adres, 'AdresL2', l2)

    def _build_podmiot2(self, root, invoice):
        """Nabywca."""
        p2 = _el(root, 'Podmiot2')
        dane = _el(p2, 'DaneIdentyfikacyjne')
        _el(dane, 'NIP', invoice.buyer_nip)
        _el(dane, 'PelnaNazwa', invoice.buyer_name)
        adres = _el(p2, 'Adres')
        l1, l2 = self._split_address(invoice.buyer_address)
        _el(adres, 'KodKraju', 'PL')
        _el(adres, 'AdresL1', l1)
        if l2:
            _el(adres, 'AdresL2', l2)

    def _build_fa(self, root, invoice, company, items):
        fa = _el(root, 'Fa')
        _el(fa, 'KodWaluty', invoice.currency)
        _el(fa, 'P_1', invoice.issue_date.strftime('%Y-%m-%d'))
        _el(fa, 'P_2', invoice.invoice_number)
        if invoice.delivery_date:
            _el(fa, 'P_6', invoice.delivery_date.strftime('%Y-%m-%d'))

        # Kwoty per stawka VAT (P_13_X netto, P_14_X VAT)
        self._build_vat_totals(fa, items)

        # P_15 — suma brutto
        gross_total = sum((i.amount_gross for i in items), Decimal('0.00'))
        _el(fa, 'P_15', _fmt_decimal(gross_total))

        # Pozycje faktury
        for item in items:
            self._build_fa_wiersz(fa, item)

        # Płatność
        self._build_platnosc(fa, invoice, company, gross_total)

    def _build_vat_totals(self, fa, items):
        """Agreguje kwoty netto/VAT per stawka i emituje P_13_X / P_14_X."""
        net_by_rate: dict[str, Decimal] = defaultdict(Decimal)
        vat_by_rate: dict[str, Decimal] = defaultdict(Decimal)
        for item in items:
            net_by_rate[item.vat_rate] += item.amount_net
            vat_by_rate[item.vat_rate] += item.amount_vat

        # Stawki z numerycznym indeksem (23→1, 8→2, 5→3, 0→4)
        for rate, idx in sorted(_VAT_RATE_INDEX.items(), key=lambda x: x[1]):
            if rate in net_by_rate:
                _el(fa, f'P_13_{idx}', _fmt_decimal(net_by_rate[rate]))
                if vat_by_rate[rate] != Decimal('0.00'):
                    _el(fa, f'P_14_{idx}', _fmt_decimal(vat_by_rate[rate]))

        # Stawki zwolnione / nie podlegające (ZW → P_13_6, NP → P_13_7)
        zw_np_map = {'zw': '6', 'np': '7'}
        for rate, suffix in zw_np_map.items():
            if rate in net_by_rate:
                _el(fa, f'P_13_{suffix}', _fmt_decimal(net_by_rate[rate]))

    def _build_fa_wiersz(self, fa, item):
        row = _el(fa, 'FaWiersz')
        _el(row, 'NrWierszaFa', str(item.lp))
        _el(row, 'P_7', item.name)
        _el(row, 'P_8A', item.unit)
        _el(row, 'P_9A', _fmt_decimal(item.quantity, places=3).rstrip('0').rstrip('.') or '0')
        _el(row, 'P_10', _fmt_decimal(item.unit_price_net))
        _el(row, 'P_11', _fmt_decimal(item.amount_net))
        # Stawka VAT w FA(2): liczba lub 'zw'/'np'
        vat_code = item.vat_rate if item.vat_rate in ('zw', 'np') else item.vat_rate
        _el(row, 'P_12', vat_code)

    def _build_platnosc(self, fa, invoice, company, gross_total):
        platnosc = _el(fa, 'Platnosc')
        termin = _el(platnosc, 'TerminPlatnosci')
        _el(termin, 'Termin', invoice.payment_due_date.strftime('%Y-%m-%d'))
        form_code = _PAYMENT_FORM_CODES.get(invoice.payment_form, '6')
        _el(platnosc, 'FormaPlatnosci', form_code)
        if invoice.payment_form == 'przelew' and company.bank_account:
            konto = _el(platnosc, 'NrKonta')
            nrb = company.bank_account.replace(' ', '')
            _el(konto, 'NrRB', nrb)
        _el(platnosc, 'Zaplacono', '0')

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
