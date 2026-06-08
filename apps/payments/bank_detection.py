"""
Detekcja banku na podstawie numeru NRB (26 cyfr).
Pozycje 3-6 (0-indexed: 2-5) to pierwsze 4 cyfry numeru rozliczeniowego — kod banku.
Źródło kodów: wykaz NBP / KIR.
"""

_BANK_CODES: dict[str, str] = {
    '1010': 'nbp',
    '1020': 'pko_bp',
    '1030': 'bnp_paribas',
    '1050': 'ing',
    '1060': 'bph',
    '1090': 'erste',
    '1130': 'citi_handlowy',
    '1140': 'mbank',
    '1160': 'millennium',
    '1190': 'deutsche',
    '1240': 'pekao',
    '1320': 'bank_pocztowy',
    '1440': 'erste',
    '1540': 'bos',
    '1590': 'credit_agricole',
    '1680': 'velobank',
    '1750': 'raiffeisen',
    '1870': 'nest',
    '2030': 'bnp_paribas',
    '2130': 'toyota',
    '2490': 'alior',
    '2530': 'hsbc',
    '2690': 'bank_pocztowy',
}

BANK_LABELS: dict[str, str] = {
    'erste':          'Erste Bank',
    'mbank':          'mBank',
    'pko_bp':         'PKO BP',
    'bnp_paribas':    'BNP Paribas',
    'ing':            'ING',
    'bph':            'BPH',
    'citi_handlowy':  'Citi Handlowy',
    'millennium':     'Millennium',
    'deutsche':       'Deutsche Bank',
    'pekao':          'Pekao',
    'bank_pocztowy':  'Bank Pocztowy',
    'bos':            'BOŚ',
    'credit_agricole':'Credit Agricole',
    'velobank':       'VeloBank',
    'raiffeisen':     'Raiffeisen',
    'nest':           'Nest Bank',
    'nbp':            'NBP',
    'toyota':         'Toyota Bank',
    'alior':          'Alior Bank',
    'hsbc':           'HSBC',
    'other':          '',
}

FILE_SUFFIXES: dict[str, str] = {
    'erste':          'Erste_Bank',
    'mbank':          'mBank',
    'pko_bp':         'PKO_BP',
    'bnp_paribas':    'BNP_Paribas',
    'ing':            'ING',
    'millennium':     'Millennium',
    'pekao':          'Pekao',
    'alior':          'Alior',
    'credit_agricole':'Credit_Agricole',
    'velobank':       'VeloBank',
    'other':          'Przelew',
}

# Tablica do detekcji client-side (JS) — eksportujemy jako JSON-friendly dict
BANK_CODES_JS: dict[str, str] = {
    code: BANK_LABELS.get(key, '')
    for code, key in _BANK_CODES.items()
}


def detect_bank_key(account_number: str) -> str:
    """Zwraca klucz banku na podstawie numeru NRB. Ignoruje spacje i myślniki."""
    digits = account_number.replace(' ', '').replace('-', '')
    if len(digits) != 26 or not digits.isdigit():
        return 'other'
    code = digits[2:6]
    return _BANK_CODES.get(code, 'other')


def get_file_suffix(bank_key: str) -> str:
    return FILE_SUFFIXES.get(bank_key, 'Przelew')
