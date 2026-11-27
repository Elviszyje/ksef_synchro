"""Stronicowanie zapytania o metadane faktur KSeF 2.0 (pageOffset/pageSize w query stringu)."""
import json
from datetime import datetime, timezone

import httpx
from django.test import SimpleTestCase

from apps.ksef.client import KSeFClient, _parse_ksef_datetime


def _client(handler) -> KSeFClient:
    client = KSeFClient('https://ksef.test', '1111111111', 'token')
    client._http = httpx.Client(transport=httpx.MockTransport(handler))
    return client


class MetadataPagingTests(SimpleTestCase):
    def test_page_index_in_query_string(self):
        requests = []

        def handler(request: httpx.Request) -> httpx.Response:
            requests.append(request)
            body = json.loads(request.content)
            self.assertNotIn('pageOffset', body)
            page = int(request.url.params['pageOffset'])
            return httpx.Response(200, json={
                'invoices': [{'ksefNumber': f'N-{page}'}], 'hasMore': page < 2, 'isTruncated': False,
            })

        client = _client(handler)
        result = list(client._query_chunk('T', datetime(2026, 1, 1, tzinfo=timezone.utc),
                                          datetime(2026, 2, 1, tzinfo=timezone.utc), 250))
        self.assertEqual([i['ksefNumber'] for i in result], ['N-0', 'N-1', 'N-2'])
        self.assertEqual([r.url.params['pageOffset'] for r in requests], ['0', '1', '2'])
        self.assertTrue(all(r.url.params['pageSize'] == '250' and r.url.params['sortOrder'] == 'Asc'
                            for r in requests))

    def test_repeated_page_stops_loop(self):
        calls = []

        def handler(request):
            calls.append(request)
            return httpx.Response(200, json={'invoices': [{'ksefNumber': 'X'}], 'hasMore': True, 'isTruncated': False})

        result = list(_client(handler)._query_chunk('T', datetime(2026, 1, 1, tzinfo=timezone.utc),
                                                    datetime(2026, 2, 1, tzinfo=timezone.utc), 250))
        self.assertEqual(len(result), 1)
        self.assertEqual(len(calls), 2)

    def test_truncated_moves_range_start(self):
        froms = []

        def handler(request):
            body = json.loads(request.content)
            froms.append(body['dateRange']['from'])
            if len(froms) == 1:
                return httpx.Response(200, json={'hasMore': True, 'isTruncated': True, 'invoices': [
                    {'ksefNumber': 'A', 'permanentStorageDate': '2026-01-05T10:00:00.1234567+00:00'},
                    {'ksefNumber': 'B', 'permanentStorageDate': '2026-01-10T12:00:00.0000001+00:00'},
                ]})
            self.assertEqual(request.url.params['pageOffset'], '0')
            return httpx.Response(200, json={'hasMore': False, 'isTruncated': False, 'invoices': [
                {'ksefNumber': 'B'}, {'ksefNumber': 'C'},
            ]})

        result = list(_client(handler)._query_chunk('T', datetime(2026, 1, 1, tzinfo=timezone.utc),
                                                    datetime(2026, 2, 1, tzinfo=timezone.utc), 250))
        self.assertEqual([i['ksefNumber'] for i in result], ['A', 'B', 'C'])
        self.assertEqual(froms, ['2026-01-01T00:00:00Z', '2026-01-10T12:00:00Z'])

    def test_parse_ksef_datetime(self):
        self.assertEqual(_parse_ksef_datetime('2025-07-11T12:23:56.0154302+00:00'),
                         datetime(2025, 7, 11, 12, 23, 56, 15430, tzinfo=timezone.utc))
        self.assertIsNone(_parse_ksef_datetime(None))


class DecodeEntitiesTests(SimpleTestCase):
    def test_decode(self):
        from apps.ksef.parser import decode_entities
        self.assertEqual(decode_entities('Grupa K&amp;K KAJA KANCLERSKA'), 'Grupa K&K KAJA KANCLERSKA')
        self.assertEqual(decode_entities('A&amp;amp;B'), 'A&B')
        self.assertEqual(decode_entities('&quot;Firma&quot; &#8222;X&#x201D; &lt;sp&gt;'), '"Firma" „X” <sp>')
        self.assertEqual(decode_entities('Kowalski & Syn'), 'Kowalski & Syn')
        self.assertEqual(decode_entities('R&D; &foo; &'), 'R&D; &foo; &')
