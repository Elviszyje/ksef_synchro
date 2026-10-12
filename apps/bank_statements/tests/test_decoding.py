from django.test import SimpleTestCase

from apps.bank_statements.parsers.detect import decode_statement, detect_and_parse

CSV = (
    '"Nr rachunku";"Data transakcji";"Data ksiegowania";"Opis transakcji";"Kwota";"Waluta"\r\n'
    '"1";"12.10.2026";"12.10.2026";"Opłata za usługę żółtą";"-1,00";"PLN"\r\n'
)


class StatementDecodingTests(SimpleTestCase):
    def test_windows_1250_keeps_polish_characters(self):
        """Wcześniej ISO-8859-1 było przed Windows-1250 i zamieniało "ł" w "³"."""
        text = decode_statement(CSV.encode('windows-1250'))
        self.assertEqual(detect_and_parse(text).transactions[0].description, 'Opłata za usługę żółtą')

    def test_utf8_with_bom(self):
        self.assertEqual(decode_statement(b'\xef\xbb\xbf' + CSV.encode('utf-8')), CSV)

    def test_bytes_undefined_in_cp1250_fall_back_to_latin1(self):
        self.assertEqual(decode_statement(b'\x81abc'), '\x81abc')
