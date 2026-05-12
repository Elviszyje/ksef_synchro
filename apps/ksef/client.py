"""
KSeF 2.0 API client.
Dokumentacja: https://api-test.ksef.mf.gov.pl/docs/v2
"""
import base64
import logging
import time
from datetime import datetime, timedelta, timezone
from typing import Iterator

import httpx
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.x509 import load_der_x509_certificate

logger = logging.getLogger(__name__)

TIMEOUT = httpx.Timeout(30.0)


class KSeFAuthError(Exception):
    pass


class KSeFRateLimitError(Exception):
    def __init__(self, wait_seconds: int = 60):
        super().__init__(f'Rate limit KSeF, czekam {wait_seconds}s')
        self.wait_seconds = wait_seconds


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
            full_body = response.text[:2000]
            logger.error('KSeF API %s %s → %s\nBody: %s',
                         response.request.method, response.url,
                         response.status_code, full_body)

            if response.status_code == 429:
                wait = 3600  # domyślnie godzina gdy nie uda się sparsować
                try:
                    import re
                    details = response.json().get('status', {}).get('details', [])
                    for d in details:
                        total = 0
                        for h in re.findall(r'(\d+)\s+godzin', d):
                            total += int(h) * 3600
                        for m in re.findall(r'(\d+)\s+minut', d):
                            total += int(m) * 60
                        for s in re.findall(r'(\d+)\s+sekund', d):
                            total += int(s)
                        if total:
                            wait = total + 5
                            break
                except Exception:
                    pass
                logger.warning('KSeF rate limit — czekam %ds (%dm)', wait, wait // 60)
                raise KSeFRateLimitError(wait)

            try:
                data = response.json()
                detail = (
                    data.get('detail')
                    or data.get('message')
                    or data.get('title')
                    or (data.get('exception', {}).get('exceptionDetailList') or [{}])[0].get('exceptionDescription')
                    or full_body
                )
            except Exception:
                detail = full_body
            raise KSeFAPIError(
                f'HTTP {response.status_code}: {detail} [URL: {response.url}]',
                response.status_code,
            )

    def _fetch_public_key(self):
        """Pobiera klucz publiczny KSeF do szyfrowania tokena (format DER/base64)."""
        resp = self._http.get(self._url('security/public-key-certificates'))
        self._raise_for_status(resp)
        data = resp.json()

        entry = data[0] if isinstance(data, list) and data else data
        cert_b64 = entry.get('certificate')
        if not cert_b64:
            raise KSeFAuthError(f'Brak pola certificate w odpowiedzi: {entry}')

        cert_der = base64.b64decode(cert_b64)
        return load_der_x509_certificate(cert_der).public_key()

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

    def _wait_for_auth(self, reference_number: str, auth_token: str, max_wait: int = 30):
        """
        Odpytuje GET /auth/{referenceNumber} aż status != 100 (pending).
        Status 200 = gotowe do token/redeem.
        """
        for attempt in range(max_wait):
            resp = self._http.get(
                self._url(f'auth/{reference_number}'),
                headers={'Authorization': f'Bearer {auth_token}'},
            )
            self._raise_for_status(resp)
            data = resp.json()
            status_obj = data.get('status') or data.get('processingCode') or data.get('authenticationStatus')
            code = status_obj.get('code') if isinstance(status_obj, dict) else status_obj
            logger.debug('KSeF auth status check %d/%d: code=%s', attempt + 1, max_wait, code)
            if code != 100:
                if code == 200:
                    logger.info('KSeF auth gotowa (status 200) po %d próbach', attempt + 1)
                    return
                raise KSeFAuthError(f'Błąd autoryzacji KSeF, status={code}: {data}')
            time.sleep(1)
        raise KSeFAuthError(f'Timeout autoryzacji KSeF po {max_wait}s (ref: {reference_number})')

    def init_session(self) -> str:
        """
        Autoryzuje się tokenem API KSeF 2.0.
        Zwraca accessToken JWT ważny ~15 minut.
        """
        # Krok 1: challenge — brak requestBody
        resp = self._http.post(self._url('auth/challenge'))
        self._raise_for_status(resp)
        data = resp.json()
        challenge = data.get('challenge')
        timestamp_ms = data.get('timestampMs')
        if not challenge or timestamp_ms is None:
            raise KSeFAuthError(f'Brak challenge/timestampMs w odpowiedzi: {data}')

        # Krok 2: zaszyfruj token RSA-OAEP i wyślij
        encrypted_token = self._encrypt_token(timestamp_ms)
        logger.debug('KSeF ksef-token: challenge=%s nip=%s encrypted_len=%d',
                     challenge, self.nip, len(encrypted_token))
        resp = self._http.post(
            self._url('auth/ksef-token'),
            json={
                'challenge': challenge,
                'contextIdentifier': {'type': 'Nip', 'value': self.nip},
                'encryptedToken': encrypted_token,
            },
        )
        self._raise_for_status(resp)
        data = resp.json()
        reference_number = data.get('referenceNumber')
        auth_token_obj = data.get('authenticationToken')
        # authenticationToken to obiekt {"token": "...", "validUntil": "..."}
        auth_token = (
            auth_token_obj.get('token') if isinstance(auth_token_obj, dict)
            else auth_token_obj
        )
        if not auth_token:
            raise KSeFAuthError(f'Brak authenticationToken w odpowiedzi: {data}')

        # Krok 2b: poczekaj aż autoryzacja przejdzie ze statusu 100 → 200 (async)
        if reference_number:
            self._wait_for_auth(reference_number, auth_token)

        # Krok 3: wymień na accessToken
        resp = self._http.post(
            self._url('auth/token/redeem'),
            headers={'Authorization': f'Bearer {auth_token}'},
        )
        self._raise_for_status(resp)
        data = resp.json()
        # accessToken to obiekt {"token": "...", "validUntil": "..."} lub string
        access_token_obj = data.get('accessToken')
        access_token = (
            access_token_obj.get('token') if isinstance(access_token_obj, dict)
            else access_token_obj
        )
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
        Automatycznie dzieli zakresy > 89 dni na chunki (limit API: 3 miesiące).
        """
        _MAX_CHUNK = timedelta(days=89)
        chunk_from = date_from
        while chunk_from < date_to:
            chunk_to = min(chunk_from + _MAX_CHUNK, date_to)
            yield from self._query_chunk(session_token, chunk_from, chunk_to, page_size)
            chunk_from = chunk_to

    def _query_chunk(
        self,
        session_token: str,
        date_from: datetime,
        date_to: datetime,
        page_size: int,
    ) -> Iterator[dict]:
        headers = {'Authorization': f'Bearer {session_token}'}
        page_offset = 0

        while True:
            payload = {
                'subjectType': 'Subject2',
                'dateRange': {
                    'dateType': 'PermanentStorage',
                    'from': date_from.strftime('%Y-%m-%dT%H:%M:%SZ'),
                    'to': date_to.strftime('%Y-%m-%dT%H:%M:%SZ'),
                },
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
            logger.info('KSeF v2 zapytanie %s–%s offset=%d: %d faktur',
                        date_from.strftime('%Y-%m-%d'), date_to.strftime('%Y-%m-%d'),
                        page_offset, len(invoices))

            for inv in invoices:
                yield inv

            if not data.get('hasMore', False) or not invoices:
                break
            page_offset += page_size

    def check_quota(self, session_token: str) -> int | None:
        """
        Sprawdza pozostały limit zapytań dla bieżącego kontekstu (NIP).
        Zwraca liczbę pozostałych zapytań na godzinę lub None jeśli nie można ustalić.
        Rzuca KSeFRateLimitError gdy limit jest wyczerpany (remaining == 0).
        Fail-open: błąd/404 endpointu nie blokuje synca.
        """
        headers = {'Authorization': f'Bearer {session_token}'}
        for path in ('limits/context', 'limits/subject', 'rate-limits'):
            try:
                resp = self._http.get(self._url(path), headers=headers)
            except Exception as exc:
                logger.warning('KSeF quota check error (%s): %s', path, exc)
                continue
            if resp.status_code == 404:
                logger.debug('KSeF quota endpoint %s: 404, pomijam', path)
                continue
            if resp.status_code == 429:
                raise KSeFRateLimitError()
            if resp.status_code >= 400:
                logger.warning('KSeF quota endpoint %s → HTTP %s', path, resp.status_code)
                continue
            try:
                data = resp.json()
            except Exception:
                continue
            logger.info('KSeF quota (%s): %s', path, data)
            remaining = self._extract_remaining(data)
            if remaining is not None:
                if remaining <= 0:
                    logger.warning('KSeF: limit API wyczerpany (remaining=%s) — sync pominięty', remaining)
                    raise KSeFRateLimitError(wait_seconds=3600)
                logger.info('KSeF: pozostały limit zapytań: %d', remaining)
                return remaining
        logger.debug('KSeF: nie udało się odczytać limitu — kontynuuję (fail-open)')
        return None

    @staticmethod
    def _extract_remaining(data: dict | list) -> int | None:
        """
        Heurystycznie wyciąga minimalną liczbę pozostałych zapytań z odpowiedzi endpointu limitów.
        Obsługuje różne struktury odpowiedzi KSeF 2.0.
        """
        REMAINING_KEYS = ('remaining', 'requestsRemaining', 'availableRequests',
                          'remainingRequests', 'left', 'available')

        def _find(obj, depth=0) -> list[int]:
            if depth > 4:
                return []
            if isinstance(obj, dict):
                found = []
                for key in REMAINING_KEYS:
                    val = obj.get(key)
                    if isinstance(val, int) and val >= 0:
                        found.append(val)
                if found:
                    return found
                for v in obj.values():
                    found.extend(_find(v, depth + 1))
                return found
            if isinstance(obj, list):
                found = []
                for item in obj:
                    found.extend(_find(item, depth + 1))
                return found
            return []

        values = _find(data)
        return min(values) if values else None

    def get_invoice_xml(self, session_token: str, ksef_reference_number: str) -> bytes | None:
        """
        Pobiera surowy XML FA faktury.
        Zwraca None przy 404 (brak uprawnień lub faktura niedostępna).
        Rzuca KSeFRateLimitError przy 429.
        """
        resp = self._http.get(
            self._url(f'invoices/{ksef_reference_number}/content'),
            headers={
                'Authorization': f'Bearer {session_token}',
                'Accept': 'application/octet-stream',
            },
        )
        if resp.status_code == 404:
            return None
        self._raise_for_status(resp)
        return resp.content

    def close(self):
        self._http.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()
