"""
Generuje golden files dla aplikacji iOS (KS-eFektywnie).

Kod Django jest wyrocznią: dane wejściowe z <fixtures>/input są przepuszczane
przez oryginalne parsery, generatory i matcher, a wyniki trafiają do
<fixtures>/expected. Testy Swift porównują port z tymi plikami.

Komenda nie dotyka bazy danych (modele są tworzone bez zapisu).

    python manage.py export_ios_fixtures
"""
import json
from dataclasses import asdict
from datetime import date
from decimal import Decimal
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from django.conf import settings
from django.core.management.base import BaseCommand

DEFAULT_DIR = Path(settings.BASE_DIR) / 'ios' / 'Packages' / 'KSeFektywnieKit' / 'Tests' / 'DomainTests' / 'Fixtures'


def _jsonable(value):
    if isinstance(value, Decimal):
        return str(value)
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, dict):
        return {k: _jsonable(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_jsonable(v) for v in value]
    return value


def _write_json(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(_jsonable(data), ensure_ascii=False, indent=2, sort_keys=True) + '\n', encoding='utf-8')


class Command(BaseCommand):
    help = 'Eksportuje golden files dla testów aplikacji iOS.'
    requires_system_checks = []

    def add_arguments(self, parser):
        parser.add_argument('--fixtures-dir', default=str(DEFAULT_DIR))

    def handle(self, *args, **options):
        root = Path(options['fixtures_dir'])
        self.inp = root / 'input'
        self.out = root / 'expected'
        self._fa()
        self._payments()
        self._statements()
        self._matcher()
        self._domain()
        self._outgoing()
        self.stdout.write(self.style.SUCCESS(f'Golden files zapisane w {self.out}'))

    # ── Parser FA ────────────────────────────────────────────────────────
    def _fa(self):
        from apps.ksef.parser import FA2Parser, parse_line_items
        from apps.ksef.tasks import _parsed_from_metadata, _parsed_to_invoice_fields

        for xml_path in sorted((self.inp / 'fa').glob('*.xml')):
            raw = xml_path.read_bytes()
            parsed = FA2Parser().parse(raw, ksef_reference_number=f'REF-{xml_path.stem}')
            data = asdict(parsed)
            data.pop('raw_xml')
            result = {'parsed': data, 'line_items': parse_line_items(parsed.raw_xml)}
            if parsed.issue_date:
                fields = _parsed_to_invoice_fields(parsed)
                fields.pop('raw_xml')
                result['invoice_fields'] = fields
            _write_json(self.out / 'fa' / f'{xml_path.stem}.json', result)

        headers = json.loads((self.inp / 'fa' / 'metadata.json').read_text(encoding='utf-8'))
        results = []
        for header in headers:
            parsed = _parsed_from_metadata(header, buyer_nip_fallback='1132854320')
            data = asdict(parsed)
            data.pop('raw_xml')
            results.append(data)
        _write_json(self.out / 'fa' / 'metadata.json', results)

    # ── Generatory plików przelewów ──────────────────────────────────────
    def _payments(self):
        from apps.invoices.models import Invoice
        from apps.payments.generators import elixir as elixir_module
        from apps.payments.generators.registry import BANK_GENERATORS

        spec = json.loads((self.inp / 'payments' / 'invoices.json').read_text(encoding='utf-8'))
        exec_date = date.fromisoformat(spec['execution_date'])
        company = spec['company']
        invoices = []
        for raw in spec['invoices']:
            inv = Invoice(
                pk=raw['id'],
                invoice_number=raw['invoice_number'],
                seller_name=raw['seller_name'],
                seller_nip=raw['seller_nip'],
                seller_address=raw['seller_address'],
                amount_gross=Decimal(raw['amount_gross']),
                amount_vat=Decimal(raw['amount_vat']),
                vat_amount_split=Decimal(raw['vat_amount_split']) if raw['vat_amount_split'] else None,
                is_split_payment=raw['is_split_payment'],
                bank_account_number=raw['bank_account_number'],
            )
            invoices.append(inv)

        class _FixedDate(date):
            @classmethod
            def today(cls):
                return exec_date

        out_dir = self.out / 'payments'
        out_dir.mkdir(parents=True, exist_ok=True)
        with mock.patch.object(elixir_module, 'date', _FixedDate):
            for key, (generator_cls, ext, _label) in BANK_GENERATORS.items():
                gen = generator_cls(company['debit_account'], company['name'], company['address'])
                (out_dir / f'{key}.{ext}').write_bytes(gen.generate(invoices))

    # ── Wyciągi bankowe ──────────────────────────────────────────────────
    def _statements(self):
        from apps.bank_statements.parsers import erste_csv, mt940, velobank_csv
        from apps.bank_statements.parsers.detect import detect_and_parse

        for path in sorted((self.inp / 'statements').iterdir()):
            content = path.read_bytes().decode('utf-8')
            stmt = detect_and_parse(content)
            _write_json(self.out / 'statements' / f'{path.stem}.json', {
                'detect': {
                    'mt940': mt940.detect(content),
                    'erste': erste_csv.detect(content),
                    'velobank': velobank_csv.detect(content),
                },
                'bank_key': stmt.bank_key,
                'account_number': stmt.account_number,
                'statement_date': stmt.statement_date,
                'transactions': [asdict(tx) for tx in stmt.transactions],
            })

    # ── Matcher ──────────────────────────────────────────────────────────
    def _matcher(self):
        from apps.bank_statements.parsers.mt940 import InvoiceMatcher

        spec = json.loads((self.inp / 'matcher' / 'case.json').read_text(encoding='utf-8'))
        invoices = [
            SimpleNamespace(**{**raw, 'amount_gross': Decimal(raw['amount_gross'])})
            for raw in spec['invoices']
        ]
        txs = [
            SimpleNamespace(**{**raw, 'amount': Decimal(raw['amount'])})
            for raw in spec['transactions']
        ]
        index_of = {id(tx): i for i, tx in enumerate(txs)}
        matches = InvoiceMatcher().match(txs, invoices)
        _write_json(self.out / 'matcher' / 'case.json', [
            {
                'transaction_index': index_of[id(m['transaction'])],
                'invoice_id': m['invoice'].id,
                'match_type': m['match_type'],
                'confidence': m['confidence'],
            }
            for m in matches
        ])

    # ── Faktury sprzedażowe: generator FA(3) i kwoty pozycji ─────────────
    def _outgoing(self):
        from datetime import datetime
        from lxml import etree
        from apps.ksef.generator import FA3Generator
        from apps.outgoing.models import InvoiceItem

        spec = json.loads((self.inp / 'outgoing' / 'invoices.json').read_text(encoding='utf-8'))
        schema = etree.XMLSchema(etree.parse(str(Path(settings.BASE_DIR) / 'apps/ksef/schemas/fa3/schemat.xsd')))
        company = SimpleNamespace(name=spec['seller']['name'], address=spec['seller']['address'],
                                  bank_account=spec['bank_account'])
        config = SimpleNamespace(nip=spec['seller']['nip'])
        now = datetime.fromisoformat(spec['now'])
        amounts = {}
        for case in spec['cases']:
            raw = case['invoice']
            invoice = SimpleNamespace(**{
                **raw,
                'issue_date': date.fromisoformat(raw['issue_date']),
                'payment_due_date': date.fromisoformat(raw['payment_due_date']),
                'delivery_date': date.fromisoformat(raw['delivery_date']) if raw['delivery_date'] else None,
            })
            items = []
            for lp, it in enumerate(case['items'], start=1):
                item = InvoiceItem(lp=lp, name=it['name'], unit=it['unit'], quantity=Decimal(it['quantity']),
                                   unit_price_net=Decimal(it['unit_price_net']), vat_rate=it['vat_rate'])
                item.calculate_amounts()
                items.append(item)
            amounts[case['name']] = [
                {'net': i.amount_net, 'vat': i.amount_vat, 'gross': i.amount_gross} for i in items
            ]
            xml = FA3Generator().generate(invoice, company, config, items=items, now=now)
            if not schema.validate(etree.fromstring(xml)):
                raise RuntimeError(f'FA(3) {case["name"]} niezgodne ze schematem: {schema.error_log}')
            out = self.out / 'outgoing' / f'{case["name"]}.xml'
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(xml)
        _write_json(self.out / 'outgoing' / 'item_amounts.json', amounts)

    # ── Drobna logika domenowa ───────────────────────────────────────────
    def _domain(self):
        from apps.bank_statements.parsers.mt940 import InvoiceMatcher
        from apps.invoices.views import STATUS_TRANSITIONS, STATUS_TRANSITIONS_CORRECTION
        from apps.payments.bank_detection import detect_bank_key, get_file_suffix, BANK_LABELS
        from apps.payments.generators.base import BasePaymentGenerator, format_amount
        from apps.payments.generators.registry import get_generator_for_bank

        _write_json(self.out / 'domain' / 'status_transitions.json', {
            'standard': STATUS_TRANSITIONS,
            'correction': STATUS_TRANSITIONS_CORRECTION,
        })

        accounts = [
            '61109010140000071219812874', '61 1090 1014 0000 0712 1981 2874',
            '12-1020-1026-0000-0402-0123-4567', '98114020040000320276543210',
            '16168010000000000000001234', '11114010100000123456789012',
            'PL61109010140000071219812874', '123', '',
        ]
        detection = []
        for acc in accounts:
            key = detect_bank_key(acc)
            detection.append({
                'account': acc, 'bank_key': key, 'label': BANK_LABELS.get(key, ''),
                'file_suffix': get_file_suffix(key), 'extension': get_generator_for_bank(key)[1],
            })
        _write_json(self.out / 'domain' / 'bank_detection.json', detection)

        texts = [
            ('Zażółć gęślą jaźń', 80), ('Café Müller & Søn ✓ «Quotes»', 80),
            ('  tab\tand\nnewline  ', 80), ('a|b;c"d\'e<f>g~h`i', 80),
            ('Faktura FV/2026/0001', 10), ('ŁÓDŹ ŚRÓDMIEŚCIE', 5), ('', 10),
            ('under_score + plus = equals [x] {y} !@#$%^&*()/?', 140),
        ]
        _write_json(self.out / 'domain' / 'clean_text.json', [
            {'input': t, 'max_len': n, 'output': BasePaymentGenerator._clean_text(t, n)} for t, n in texts
        ])

        amounts = ['0', '0.01', '0.005', '0.015', '1446', '1446.5', '1234567.89', '99.999']
        _write_json(self.out / 'domain' / 'format_amount.json', [
            {'input': a, 'output': format_amount(Decimal(a))} for a in amounts
        ])

        numbers = ['FV/0030/09/2026', 'fv-30-9-2026', '01/10/2026', 'A 001 b', '0000', 'X/0/Y', 'ab12cd']
        _write_json(self.out / 'domain' / 'normalize_invoice_nr.json', [
            {'input': n, 'output': InvoiceMatcher._normalize_invoice_nr(n)} for n in numbers
        ])
