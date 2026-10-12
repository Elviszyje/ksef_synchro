from decimal import Decimal

from django.test import SimpleTestCase

from apps.ksef.parser import FA2Parser

XML = '''<?xml version="1.0" encoding="UTF-8"?>
<Faktura xmlns="http://crd.gov.pl/wzor/2025/06/25/13775/">
  <Podmiot1><DaneIdentyfikacyjne><NIP>6260181591</NIP><Nazwa>Sprzedawca</Nazwa></DaneIdentyfikacyjne></Podmiot1>
  <Fa><KodWaluty>PLN</KodWaluty><P_1>2026-10-01</P_1><P_2>FV/1</P_2>
    <P_13_1>100.00</P_13_1><P_14_1>23.00</P_14_1>
    <P_13_6_1>50.00</P_13_6_1>
    <P_13_7>10.00</P_13_7>
    <P_13_8>20.00</P_13_8>
    <P_13_10>30.00</P_13_10>
    <P_15>233.00</P_15>
  </Fa>
</Faktura>'''


class ParserTotalsTests(SimpleTestCase):
    def test_net_includes_all_rate_fields(self):
        """Wcześniej sumowane były tylko P_13_1–P_13_7: gubiło to 0%, NP i odwrotne obciążenie."""
        parsed = FA2Parser().parse(XML.encode(), 'REF')
        self.assertEqual(parsed.amount_net, Decimal('210.00'))
        self.assertEqual(parsed.amount_vat, Decimal('23.00'))
        self.assertEqual(parsed.amount_gross, Decimal('233.00'))
