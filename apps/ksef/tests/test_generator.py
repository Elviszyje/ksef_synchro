from datetime import date, datetime, timezone
from decimal import Decimal
from pathlib import Path
from types import SimpleNamespace

from django.test import SimpleTestCase
from lxml import etree

from apps.ksef.generator import FA3_NS, FA3Generator, FA3GeneratorError
from apps.ksef.parser import FA2Parser, parse_line_items
from apps.outgoing.models import InvoiceItem

SCHEMA_PATH = Path(__file__).resolve().parent.parent / 'schemas' / 'fa3' / 'schemat.xsd'
NS = {'fa': FA3_NS}


def _item(lp, name, qty, price, rate, unit='szt.'):
    item = InvoiceItem(lp=lp, name=name, unit=unit, quantity=Decimal(qty), unit_price_net=Decimal(price), vat_rate=rate)
    item.calculate_amounts()
    return item


class FA3GeneratorTests(SimpleTestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.schema = etree.XMLSchema(etree.parse(str(SCHEMA_PATH)))

    def setUp(self):
        self.company = SimpleNamespace(name='Moja Firma Sp. z o.o.', address='ul. Testowa 10\n00-950 Warszawa',
                                       bank_account='61 1090 1014 0000 0712 1981 2874')
        self.config = SimpleNamespace(nip='1111111111')
        self.invoice = SimpleNamespace(
            invoice_number='FV/2026/0001', issue_date=date(2026, 10, 12), delivery_date=date(2026, 10, 10),
            payment_due_date=date(2026, 10, 26), payment_form='przelew', currency='PLN',
            buyer_nip='6260181591', buyer_name='Klient & Syn <S.A.>', buyer_address='ul. Kupiecka 1\n30-001 Kraków',
        )
        self.items = [
            _item(1, 'Usługa programistyczna', '12.5', '200.00', '23', unit='h'),
            _item(2, 'Książka', '2', '45.50', '5'),
            _item(3, 'Catering', '3', '19.99', '8'),
            _item(4, 'Usługa 0%', '1', '100.00', '0'),
            _item(5, 'Usługa poza krajem', '1', '300.00', 'np'),
        ]

    def generate(self, items=None, **overrides):
        invoice = SimpleNamespace(**{**vars(self.invoice), **overrides})
        return FA3Generator().generate(invoice, self.company, self.config, items=items or self.items,
                                       now=datetime(2026, 10, 12, 8, 30, tzinfo=timezone.utc))

    def test_valid_against_fa3_schema(self):
        doc = etree.fromstring(self.generate())
        self.assertTrue(self.schema.validate(doc), self.schema.error_log)

    def test_cash_invoice_without_address_is_valid(self):
        doc = etree.fromstring(self.generate(items=self.items[:1], payment_form='gotowka', buyer_address='', delivery_date=None))
        self.assertTrue(self.schema.validate(doc), self.schema.error_log)
        self.assertIsNone(doc.find('.//fa:RachunekBankowy', NS))

    def test_line_items_use_correct_fields(self):
        doc = etree.fromstring(self.generate())
        row = doc.find('.//fa:FaWiersz', NS)
        self.assertEqual(row.findtext('fa:P_8B', namespaces=NS), '12.5')    # ilość
        self.assertEqual(row.findtext('fa:P_9A', namespaces=NS), '200.00')  # cena jednostkowa netto
        self.assertEqual(row.findtext('fa:P_11', namespaces=NS), '2500.00')
        self.assertIsNone(row.find('fa:P_10', NS))                          # P_10 to rabat — nie używamy
        rates = [r.findtext('fa:P_12', namespaces=NS) for r in doc.findall('.//fa:FaWiersz', NS)]
        self.assertEqual(rates, ['23', '5', '8', '0 KR', 'np I'])

    def test_totals_per_rate(self):
        fa = etree.fromstring(self.generate()).find('fa:Fa', NS)
        totals = {el.tag.split('}')[1]: el.text for el in fa if el.tag.split('}')[1].startswith(('P_13', 'P_14', 'P_15'))}
        self.assertEqual(totals, {
            'P_13_1': '2500.00', 'P_14_1': '575.00',
            'P_13_2': '59.97', 'P_14_2': '4.80',
            'P_13_3': '91.00', 'P_14_3': '4.55',
            'P_13_6_1': '100.00',
            'P_13_8': '300.00',
            'P_15': '3635.32',
        })

    def test_roundtrip_through_parser(self):
        xml = self.generate()
        parsed = FA2Parser().parse(xml, 'REF')
        self.assertEqual(parsed.amount_net, Decimal('3050.97'))
        self.assertEqual(parsed.amount_vat, Decimal('584.35'))
        self.assertEqual(parsed.amount_gross, Decimal('3635.32'))
        self.assertEqual(parsed.seller_name, 'Moja Firma Sp. z o.o.')
        self.assertEqual(parsed.bank_account_number, '61109010140000071219812874')
        self.assertEqual(parsed.payment_due_date, '2026-10-26')
        self.assertEqual(parse_line_items(parsed.raw_xml)[0]['qty'], '12.5')

    def test_header(self):
        nagl = etree.fromstring(self.generate()).find('fa:Naglowek', NS)
        kod = nagl.find('fa:KodFormularza', NS)
        self.assertEqual(kod.get('kodSystemowy'), 'FA (3)')
        self.assertEqual(nagl.findtext('fa:WariantFormularza', namespaces=NS), '3')
        self.assertEqual(nagl.findtext('fa:DataWytworzeniaFa', namespaces=NS), '2026-10-12T08:30:00Z')

    def test_exempt_rate_requires_basis(self):
        with self.assertRaisesMessage(FA3GeneratorError, 'podstawy prawnej zwolnienia'):
            self.generate(items=[_item(1, 'Szkolenie', '1', '100', 'zw')])

    def test_exempt_rate_with_basis(self):
        items = [_item(1, 'Szkolenie', '1', '100', 'zw'), _item(2, 'Materiały', '1', '10', '23')]
        for exemption_type, field in [('ustawa', 'P_19A'), ('dyrektywa', 'P_19B'), ('inna', 'P_19C')]:
            doc = etree.fromstring(self.generate(items=items, vat_exemption_type=exemption_type,
                                                 vat_exemption_basis='art. 43 ust. 1 pkt 29 lit. a ustawy o VAT'))
            self.assertTrue(self.schema.validate(doc), self.schema.error_log)
            zw = doc.find('.//fa:Adnotacje/fa:Zwolnienie', NS)
            self.assertEqual(zw.findtext('fa:P_19', namespaces=NS), '1')
            self.assertEqual(zw.findtext(f'fa:{field}', namespaces=NS), 'art. 43 ust. 1 pkt 29 lit. a ustawy o VAT')
            self.assertEqual(doc.findtext('.//fa:P_13_7', namespaces=NS), '100.00')

    def test_basis_ignored_without_exempt_items(self):
        doc = etree.fromstring(self.generate(vat_exemption_type='ustawa', vat_exemption_basis='art. 113'))
        self.assertTrue(self.schema.validate(doc), self.schema.error_log)
        self.assertEqual(doc.findtext('.//fa:Zwolnienie/fa:P_19N', namespaces=NS), '1')

    def test_transfer_requires_company_account(self):
        self.company.bank_account = ''
        with self.assertRaisesMessage(FA3GeneratorError, 'Brak numeru konta'):
            self.generate()

    def test_no_items(self):
        with self.assertRaises(FA3GeneratorError):
            FA3Generator().generate(self.invoice, self.company, self.config, items=[])
