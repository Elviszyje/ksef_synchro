"""
KSeF 2.0 API client.
Dokumentacja: https://www.podatki.gov.pl/ksef/dokumentacja-ksef/
Środowisko testowe: https://api-test.ksef.mf.gov.pl
"""
import logging
from datetime import datetime, timezone
from typing import Iterator

import httpx

logger = logging.getLogger(__name__)

TIMEOUT = httpx.Timeout(30.0)


class KSeFAuthError(Exception):
    pass


class KSeFAPIError(Exception):
    def __init__(self, message: str, status_code: int = 0):
        super().__init__(message)
        self.status_code = status_code


class KSeFClient:
    """
    Klient KSeF 2.0.

    Użycie:
        client = KSeFClient(base_url, nip, api_token)
        session_token = client.init_session()
        for invoice_xml in client.iter_purchase_invoices(session_token, date_from, date_to):
            ...
        client.terminate_session(session_token)
    """

    def __init__(self, base_url: str, nip: str, api_token: str):
        self.base_url = base_url.rstrip('/')
        self.nip = nip
        self.api_token = api_token
        self._http = httpx.Client(timeout=TIMEOUT, headers={'Accept': 'application/json'})

    def _url(self, path: str) -> str:
        return f'{self.base_url}/api/online/{path}'

    def _raise_for_status(self, response: httpx.Response):
        if response.status_code >= 400:
            try:
                detail = response.json().get('exception', {}).get('exceptionDetailList', [{}])[0].get('exceptionDescription', response.text)
            except Exception:
                detail = response.text[:500]
            raise KSeFAPIError(f'HTTP {response.status_code}: {detail}', response.status_code)

    def init_session(self) -> str:
        """
        Inicjuje sesję KSeF tokenem API.
        Zwraca sessionToken ważny 3600s.
        """
        payload = {
            'contextIdentifier': {
                'type': 'onip',
                'identifier': self.nip,
            }
        }
        headers = {'SessionToken': self.api_token}
        resp = self._http.post(
            self._url('Session/InitToken'),
            json=payload,
            headers=headers,
        )
        self._raise_for_status(resp)
        data = resp.json()
        session_token = data.get('sessionToken', {}).get('token')
        if not session_token:
            raise KSeFAuthError(f'Brak sessionToken w odpowiedzi: {data}')
        logger.info('KSeF session initiated for NIP %s', self.nip)
        return session_token

    def terminate_session(self, session_token: str):
        resp = self._http.get(
            self._url('Session/Terminate'),
            headers={'SessionToken': session_token},
        )
        logger.info('KSeF session terminated, status=%s', resp.status_code)

    def iter_purchase_invoices(
        self,
        session_token: str,
        date_from: datetime,
        date_to: datetime,
        page_size: int = 100,
    ) -> Iterator[dict]:
        """
        Iteruje po fakturach zakupowych (kosztowych) dla danego zakresu dat.
        Każdy element to dict z polami: KsefReferenceNumber, InvoiceHash, ...
        """
        headers = {'SessionToken': session_token}
        query_payload = {
            'queryCriteria': {
                'subjectType': 'subject2',
                'type': 'incremental',
                'acquisitionTimestampThresholdFrom': date_from.strftime('%Y-%m-%dT%H:%M:%S.000Z'),
                'acquisitionTimestampThresholdTo': date_to.strftime('%Y-%m-%dT%H:%M:%S.000Z'),
            }
        }

        # Etap 1: wyślij zapytanie
        resp = self._http.post(
            self._url('Invoice/QuerySync'),
            json=query_payload,
            headers=headers,
        )
        self._raise_for_status(resp)
        data = resp.json()
        invoice_headers = data.get('invoiceHeaderList', [])

        logger.info('KSeF query returned %d invoice headers', len(invoice_headers))
        for header in invoice_headers:
            yield header

        # Obsługa paginacji
        while data.get('hasMore', False):
            reference = data.get('lastInvoiceHashValue', '')
            resp = self._http.get(
                self._url('Invoice/QuerySync/Next'),
                headers={**headers, 'pageSize': str(page_size), 'lastInvoiceHashValue': reference},
            )
            self._raise_for_status(resp)
            data = resp.json()
            for header in data.get('invoiceHeaderList', []):
                yield header

    def get_invoice_xml(self, session_token: str, ksef_reference_number: str) -> bytes:
        """Pobiera surowy XML FA(2) faktury."""
        resp = self._http.get(
            self._url(f'Invoice/Get/{ksef_reference_number}'),
            headers={'SessionToken': session_token, 'Accept': 'application/octet-stream'},
        )
        self._raise_for_status(resp)
        return resp.content

    def close(self):
        self._http.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()
