"""
Lookup danych firmy po NIP z Białej Listy MF.
API: https://wl-api.mf.gov.pl/api/search/nip/{nip}?date=YYYY-MM-DD
Bezpłatne, bez klucza API.
"""
from datetime import date

import httpx


def fetch_nip_data(nip: str) -> dict | None:
    """
    Pobiera dane firmy z Białej Listy MF.
    Zwraca słownik z kluczami: name, address, regon, status_vat, account_numbers
    lub None gdy NIP nieznany lub błąd połączenia.
    """
    nip_clean = nip.replace('-', '').replace(' ', '')
    if len(nip_clean) != 10 or not nip_clean.isdigit():
        return None

    today = date.today().isoformat()
    url = f'https://wl-api.mf.gov.pl/api/search/nip/{nip_clean}?date={today}'

    try:
        with httpx.Client(timeout=5.0) as client:
            resp = client.get(url)
            resp.raise_for_status()
            data = resp.json()
    except (httpx.HTTPError, httpx.TimeoutException, ValueError):
        return None

    subject = data.get('result', {}).get('subject')
    if not subject:
        return None

    address = subject.get('workingAddress') or subject.get('residenceAddress') or ''

    return {
        'name': subject.get('name', ''),
        'address': address,
        'regon': subject.get('regon', ''),
        'status_vat': subject.get('statusVat', ''),
        'account_numbers': subject.get('accountNumbers', []),
    }
