from datetime import date, datetime, timezone
from decimal import Decimal
from types import SimpleNamespace

from django.test import SimpleTestCase, TestCase

from apps.accounts.models import Company
from apps.ksef.generator import FA3Generator
from apps.ksef.sales_import import import_sales_invoices, initial_sales_date_from
from apps.ksef.sales_parser import parse_sales_invoice
from apps.outgoing.models import Buyer, InvoiceItem, OutgoingInvoice

NS = 'http://crd.gov.pl/wzor/2025/06/25/13775/'


def _item(lp, name, qty, price, rate, unit='szt.'):
    item = InvoiceItem(lp=lp, name=name, unit=unit, quantity=Decimal(qty), unit_price_net=Decimal(price), vat_rate=rate)
    item.calculate_amounts()
    return item


def _generated(number='FV/2026/0007', items=None, **overrides):
    """XML FA(3) z generatora aplikacji — import musi go odczytać bez strat."""
    invoice = SimpleNamespace(**{
        'invoice_number': number, 'issue_date': date(2026, 10, 12), 'delivery_date': date(2026, 10, 10),
        'payment_due_date': date(2026, 10, 26), 'payment_form': 'przelew', 'currency': 'PLN',
        'buyer_nip': '6260181591', 'buyer_name': 'Klient S.A.', 'buyer_address': 'ul. Kupiecka 1\n30-001 Kraków',
        'vat_exemption_type': 'ustawa', 'vat_exemption_basis': '', **overrides,
    })
    company = SimpleNamespace(name='Moja Firma', address='ul. Testowa 10\n00-950 Warszawa',
                              bank_account='61109010140000071219812874')
    items = items or [_item(1, 'Programowanie', '12.5', '200.00', '23', unit='h'), _item(2, 'Książka', '2', '45.50', '5')]
    return FA3Generator().generate(invoice, company, SimpleNamespace(nip='1111111111'), items=items,
                                   now=datetime(2026, 10, 12, tzinfo=timezone.utc))


def _xml(fa_body: str, buyer: str = '<NIP>6260181591</NIP><Nazwa>Klient</Nazwa>') -> bytes:
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<Faktura xmlns="{NS}">
  <Podmiot1><DaneIdentyfikacyjne><NIP>1111111111</NIP><Nazwa>Moja Firma</Nazwa></DaneIdentyfikacyjne></Podmiot1>
  <Podmiot2><DaneIdentyfikacyjne>{buyer}</DaneIdentyfikacyjne></Podmiot2>
  <Fa><KodWaluty>PLN</KodWaluty><P_1>2026-10-01</P_1><P_2>FV/X/1</P_2>{fa_body}</Fa>
</Faktura>'''.encode()


class SalesParserTests(SimpleTestCase):
    def test_round_trip_of_generated_invoice(self):
        sale = parse_sales_invoice(_generated())
        self.assertEqual(sale.invoice_number, 'FV/2026/0007')
        self.assertEqual((sale.issue_date, sale.delivery_date, sale.payment_due_date),
                         ('2026-10-12', '2026-10-10', '2026-10-26'))
        self.assertEqual((sale.buyer_nip, sale.buyer_name), ('6260181591', 'Klient S.A.'))
        self.assertEqual(sale.buyer_address, 'ul. Kupiecka 1\n30-001 Kraków')
        self.assertEqual(sale.bank_account_number, '61109010140000071219812874')
        self.assertEqual(sale.payment_form, 'przelew')
        self.assertEqual([(i.name, i.unit, i.quantity, i.unit_price_net, i.vat_rate) for i in sale.items], [
            ('Programowanie', 'h', Decimal('12.500'), Decimal('200.00'), '23'),
            ('Książka', 'szt.', Decimal('2.000'), Decimal('45.50'), '5'),
        ])
        self.assertEqual(sale.amount_gross, Decimal('3170.55'))  # 2500 + 575 + 91 + 4.55

    def test_exemption_basis_is_read(self):
        xml = _generated(items=[_item(1, 'Szkolenie', '1', '100', 'zw')], vat_exemption_type='dyrektywa',
                         vat_exemption_basis='art. 132 ust. 1 lit. i dyrektywy')
        sale = parse_sales_invoice(xml)
        self.assertEqual((sale.vat_exemption_type, sale.vat_exemption_basis), ('dyrektywa', 'art. 132 ust. 1 lit. i dyrektywy'))
        self.assertEqual(sale.items[0].vat_rate, 'zw')

    def test_vat_is_reconciled_with_invoice_totals(self):
        # 3 × 0,10 zł netto: VAT od pozycji 3 × 0,02 = 0,06, od sumy (0,30 × 23%) = 0,07.
        rows = ''.join(f'<FaWiersz><NrWierszaFa>{n}</NrWierszaFa><P_7>Śruba {n}</P_7><P_8B>1</P_8B>'
                       f'<P_9A>0.10</P_9A><P_11>0.10</P_11><P_12>23</P_12></FaWiersz>' for n in (1, 2, 3))
        sale = parse_sales_invoice(_xml(f'<P_13_1>0.30</P_13_1><P_14_1>0.07</P_14_1><P_15>0.37</P_15>{rows}'))
        self.assertEqual(sum(i.amount_vat for i in sale.items), Decimal('0.07'))
        self.assertEqual(sale.amount_gross, Decimal('0.37'))

    def test_gross_priced_rows(self):
        row = '<FaWiersz><P_7>Kawa</P_7><P_8B>2</P_8B><P_9B>12.30</P_9B><P_11A>24.60</P_11A><P_12>23</P_12></FaWiersz>'
        sale = parse_sales_invoice(_xml(f'<P_13_1>20.00</P_13_1><P_14_1>4.60</P_14_1><P_15>24.60</P_15>{row}'))
        item = sale.items[0]
        self.assertEqual((item.amount_net, item.amount_vat, item.unit_price_net), (Decimal('20.00'), Decimal('4.60'), Decimal('10.00')))

    def test_correction_uses_summary_lines(self):
        rows = ('<FaWiersz><P_7>Usługa</P_7><P_8B>1</P_8B><P_9A>100</P_9A><P_11>100</P_11><P_12>23</P_12>'
                '<StanPrzed>1</StanPrzed></FaWiersz>'
                '<FaWiersz><P_7>Usługa</P_7><P_8B>1</P_8B><P_9A>80</P_9A><P_11>80</P_11><P_12>23</P_12></FaWiersz>')
        body = ('<P_13_1>-20.00</P_13_1><P_14_1>-4.60</P_14_1><P_15>-24.60</P_15><RodzajFaktury>KOR</RodzajFaktury>'
                '<DaneFaKorygowanej><NrFaKorygowanej>FV/X/0</NrFaKorygowanej></DaneFaKorygowanej>' + rows)
        sale = parse_sales_invoice(_xml(body))
        self.assertEqual(sale.notes, 'Korekta faktury FV/X/0')
        self.assertEqual(len(sale.items), 1)
        self.assertEqual(sale.items[0].name, 'Korekta wartości – stawka 23%')
        self.assertEqual(sale.amount_gross, Decimal('-24.60'))

    def test_consumer_without_nip_and_cash(self):
        body = ('<P_13_1>10</P_13_1><P_14_1>2.30</P_14_1><P_15>12.30</P_15>'
                '<FaWiersz><P_7>A</P_7><P_8B>1</P_8B><P_9A>10</P_9A><P_11>10</P_11><P_12>23</P_12></FaWiersz>'
                '<Platnosc><FormaPlatnosci>1</FormaPlatnosci></Platnosc>')
        sale = parse_sales_invoice(_xml(body, buyer='<BrakID>1</BrakID><Nazwa>Jan Kowalski</Nazwa>'))
        self.assertEqual((sale.buyer_nip, sale.buyer_name, sale.payment_form), ('', 'Jan Kowalski', 'gotowka'))
        self.assertEqual(sale.payment_due_date, '2026-10-01')

    def test_unreadable_xml(self):
        self.assertIsNone(parse_sales_invoice(b'<nie-xml'))
        self.assertIsNone(parse_sales_invoice(_xml('').replace(b'<P_2>FV/X/1</P_2>', b'')))

    def test_initial_range(self):
        self.assertEqual(initial_sales_date_from(datetime(2026, 11, 8, tzinfo=timezone.utc)),
                         datetime(2026, 2, 1, tzinfo=timezone.utc))
        self.assertEqual(initial_sales_date_from(datetime(2028, 3, 1, tzinfo=timezone.utc)),
                         datetime(2027, 3, 2, tzinfo=timezone.utc))


class FakeClient:
    def __init__(self, invoices: dict[str, bytes | None]):
        self.invoices = invoices
        self.downloaded = []

    def iter_sales_invoices(self, session_token, date_from, date_to):
        for ksef_number, xml in self.invoices.items():
            number = parse_sales_invoice(xml).invoice_number if xml else ''
            yield {'ksefNumber': ksef_number, 'invoiceNumber': number}

    def get_invoice_xml(self, session_token, ksef_number):
        self.downloaded.append(ksef_number)
        return self.invoices[ksef_number]


class SalesImportTests(TestCase):
    def setUp(self):
        self.company = Company.objects.create(name='Firma', nip='1111111111')
        self.range = (datetime(2026, 10, 1, tzinfo=timezone.utc), datetime(2026, 11, 1, tzinfo=timezone.utc))

    def run_import(self, client):
        return import_sales_invoices(client, 'token', self.company, *self.range)

    def test_imports_read_only_invoice_with_exact_amounts(self):
        result = self.run_import(FakeClient({'K1': _generated()}))
        self.assertEqual((result.fetched, result.new), (1, 1))
        inv = OutgoingInvoice.objects.get(ksef_reference_number='K1')
        self.assertEqual(inv.status, OutgoingInvoice.STATUS_IMPORTED)
        self.assertFalse(inv.can_be_edited())
        self.assertFalse(inv.can_be_queued())
        self.assertEqual(inv.amount_gross, Decimal('3170.55'))
        self.assertIn('FV/2026/0007', inv.generated_xml)
        self.assertEqual(inv.buyer, Buyer.objects.get(company=self.company, nip='6260181591'))

    def test_second_run_skips_without_downloading(self):
        self.run_import(FakeClient({'K1': _generated()}))
        client = FakeClient({'K1': _generated()})
        result = self.run_import(client)
        self.assertEqual((result.fetched, result.new, client.downloaded), (1, 0, []))
        self.assertEqual(OutgoingInvoice.objects.count(), 1)

    def test_invoice_sent_from_app_is_not_duplicated(self):
        OutgoingInvoice.objects.create(
            company=self.company, invoice_number='FV/2026/0007', issue_date=date(2026, 10, 12),
            payment_due_date=date(2026, 10, 26), buyer_nip='6260181591', buyer_name='Klient', buyer_address='',
            status=OutgoingInvoice.STATUS_SENDING,
        )
        client = FakeClient({'K1': _generated()})
        result = self.run_import(client)
        self.assertEqual((result.new, client.downloaded), (0, []))
        self.assertEqual(OutgoingInvoice.objects.count(), 1)

    def test_conflicting_draft_is_renumbered(self):
        draft = OutgoingInvoice.objects.create(
            company=self.company, invoice_number='FV/2026/0007', issue_date=date(2026, 10, 12),
            payment_due_date=date(2026, 10, 26), buyer_nip='6260181591', buyer_name='Klient', buyer_address='',
        )
        result = self.run_import(FakeClient({'K1': _generated()}))
        self.assertEqual((result.new, result.renumbered), (1, 1))
        draft.refresh_from_db()
        self.assertEqual(draft.status, OutgoingInvoice.STATUS_DRAFT)
        self.assertNotEqual(draft.invoice_number, 'FV/2026/0007')
        self.assertIn('FV/2026/0007', draft.error_message)

    def test_missing_xml_is_skipped(self):
        result = self.run_import(FakeClient({'K404': None}))
        self.assertEqual((result.fetched, result.new, result.skipped), (1, 0, 1))
        self.assertFalse(OutgoingInvoice.objects.exists())

    def test_existing_buyer_is_not_overwritten(self):
        Buyer.objects.create(company=self.company, nip='6260181591', name='Moja nazwa klienta')
        self.run_import(FakeClient({'K1': _generated()}))
        self.assertEqual(Buyer.objects.get(company=self.company, nip='6260181591').name, 'Moja nazwa klienta')
