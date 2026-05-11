"""
KSeF 2.0 API client.
Dokumentacja: https://api-test.ksef.mf.gov.pl/docs/v2
"""
import base64
import logging
from datetime import datetime, timezone
from typing import Iterator

import httpx
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.x509 import load_pem_x509_certificate

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

    Flow autoryzacji tokenem:
      1. POST /api/v2/auth/challenge
      2. Szyfrowanie tokena RSA-OAEP kluczem publicznym KSeF
      3. POST /api/v2/auth/ksef-token  → authenticationToken
      4. POST /api/v2/auth/token/redeem → accessToken JWT (ważny ~15 min)

    Użycie:
      with KSeFClient(base_url, nip, api_token) as client:
          token = client.init_session()
          for inv in client.iter_purchase_invoices(token, date_from, date_to):
              xml = client.get_invoice_xml(token, inv['ksefNumber'])
    """

    def __init__(self, base_url: str, nip: str, api_token: str):
        self.base_url = base_url.rstrip('/')
        self.nip = nip
        self.api_token = api_token
        self._http = httpx.Client(timeout=TIMEOUT, headers={'Accept': 'application/json'})

    def _url(self, path: str) -> str:
        return f'{self.base_url}/api/v2/{path}'

    def _raise_for_status(self, response: httpx.Response):
        if response.status_code >= 400:
            try:
                data = response.json()
                detail = (
                    data.get('detail')
                    or data.get('message')
                    or (data.get('exception', {}).get('exceptionDetailList') or [{}])[0].get('exceptionDescription')
                    or response.text[:500]
                )
            except Exception:
                detail = response.text[:500]
            raise KSeFAPIError(
                f'HTTP {response.status_code}: {detail} [URL: {response.url}]',
                response.status_code,
            )

    def _fetch_public_key(self):
        """Pobiera klucz publiczny KSeF do szyfrowania tokena."""
        resp = self._http.get(self._url('security/public-key-certificates'))
        self._raise_for_status(resp)
        data = resp.json()

        # Odpowiedź to lista lub dict z certyfikatem PEM
        pem = None
        if isinstance(data, list) and data:
            entry = data[0]
            pem = entry.get('certificate') or entry.get('value') or entry.get('cert')
        elif isinstance(data, dict):
            pem = data.get('certificate') or data.get('value') or data.get('cert')

        if not pem:
            raise KSeFAuthError(f'Nie udało się pobrać klucza publicznego KSeF: {data}')

        if isinstance(pem, str) and not pem.startswith('-----'):
            pem = f'-----BEGIN CERTIFICATE-----\n{pem}\n-----END CERTIFICATE-----'
        if isinstance(pem, str):
            pem = pem.encode()

        return load_pem_x509_certificate(pem).public_key()

    def _encrypt_token(self, timestamp_ms: int) -> str:
        """Szyfruje '{api_token}|{timestampMs}' RSA-OAEP SHA-256."""
        public_key = self._fetch_public_key()
        plaintext = f'{self.api_token}|{timestamp_ms}'.encode()
        encrypted = public_key.encrypt(
            plaintext,
            padding.OAEP(
                mgf=padding.MGF1(algorithm=hashes.SHA256()),
                algorithm=hashes.SHA256(),
                label=None,
            ),
        )
        return base64.b64encode(encrypted).decode()

    def init_session(self) -> str:
        """
        Autoryzuje się tokenem API KSeF 2.0.
        Zwraca accessToken JWT ważny ~15 minut.
        """
        # Krok 1: challenge
        resp = self._http.post(
            self._url('auth/challenge'),
            json={'contextIdentifier': {'type': 'onip', 'identifier': self.nip}},
        )
        self._raise_for_status(resp)
        data = resp.json()
        challenge = data.get('challenge')
        timestamp_ms = data.get('timestampMs')
        if not challenge or timestamp_ms is None:
            raise KSeFAuthError(f'Brak challenge/timestampMs w odpowiedzi: {data}')

        # Krok 2: zaszyfruj token RSA-OAEP i wyślij
        encrypted_token = self._encrypt_token(timestamp_ms)
        resp = self._http.post(
            self._url('auth/ksef-token'),
            json={
                'challenge': challenge,
                'context': self.nip,
                'encryptedToken': encrypted_token,
            },
        )
        self._raise_for_status(resp)
        data = resp.json()
        auth_token = data.get('authenticationToken')
        if not auth_token:
            raise KSeFAuthError(f'Brak authenticationToken w odpowiedzi: {data}')

        # Krok 3: wymień na accessToken
        resp = self._http.post(
            self._url('auth/token/redeem'),
            headers={'Authorization': f'Bearer {auth_token}'},
        )
        self._raise_for_status(resp)
        data = resp.json()
        access_token = data.get('accessToken')
        if not access_token:
            raise KSeFAuthError(f'Brak accessToken w odpowiedzi: {data}')

        logger.info('KSeF 2.0 sesja otwarta dla NIP %s', self.nip)
        return access_token

    def terminate_session(self, session_token: str):
        # KSeF 2.0: sesja wygasa automatycznie, zakończenie nie jest wymagane
        logger.debug('KSeF 2.0: terminate_session (brak akcji)')

    def iter_purchase_invoices(
        self,
        session_token: str,
        date_from: datetime,
        date_to: datetime,
        page_size: int = 250,
    ) -> Iterator[dict]:
        """
        Iteruje po fakturach zakupowych (nabywca = nasza firma NIP).
        Każdy element to dict z polami: ksefNumber, seller, buyer, grossAmount, ...
        """
        headers = {'Authorization': f'Bearer {session_token}'}
        page_offset = 0

        while True:
            payload = {
                'dateRange': {
                    'from': date_from.strftime('%Y-%m-%dT%H:%M:%SZ'),
                    'to': date_to.strftime('%Y-%m-%dT%H:%M:%SZ'),
                    'dateType': 'PermanentStorage',
                },
                'buyer': {'nip': self.nip},
                'pageSize': page_size,
                'pageOffset': page_offset,
            }
            resp = self._http.post(
                self._url('invoices/query/metadata'),
                json=payload,
                headers=headers,
            )
            self._raise_for_status(resp)
            data = resp.json()
            invoices = data.get('invoices', [])
            logger.info('KSeF v2 zapytanie offset=%d zwróciło %d faktur', page_offset, len(invoices))

            for inv in invoices:
                yield inv

            if not data.get('hasMore', False) or not invoices:
                break
            page_offset += page_size

    def get_invoice_xml(self, session_token: str, ksef_reference_number: str) -> bytes:
        """Pobiera surowy XML FA faktury."""
        resp = self._http.get(
            self._url(f'invoices/{ksef_reference_number}'),
            headers={
                'Authorization': f'Bearer {session_token}',
                'Accept': 'application/octet-stream',
            },
        )
        self._raise_for_status(resp)
        return resp.content

    def close(self):
        self._http.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()
