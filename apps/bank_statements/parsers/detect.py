"""
Auto-detekcja formatu wyciągu bankowego i dispatch do właściwego parsera.

Parsery CSV są mapowane na bank_key z apps.payments.bank_detection.
Kolejność prób:
1. Parsery odpowiadające preferred_bank_keys (z rachunków firmowych)
2. MT940 (format SWIFT)
3. Pozostałe parsery CSV
"""
from .base import ParsedStatement
from . import velobank_csv, erste_csv

# Rejestr parserów CSV: bank_key → moduł parsera
_CSV_PARSERS: dict[str, object] = {
    'velobank': velobank_csv,
    'erste':    erste_csv,
}


def detect_and_parse(content: str, preferred_bank_keys: list[str] | None = None) -> ParsedStatement:
    """
    Wykrywa format i parsuje wyciąg bankowy.

    Args:
        content: Treść pliku jako string (już zdekodowany z właściwego kodowania).
        preferred_bank_keys: Lista bank_key z rachunków firmowych — te parsery są
                             sprawdzane jako pierwsze.

    Returns:
        ParsedStatement z uzupełnionym bank_key.

    Raises:
        ValueError: jeśli żaden parser nie rozpoznał formatu.
    """
    preferred = preferred_bank_keys or []

    # Buduj kolejkę prób: najpierw preferowane, potem pozostałe, na końcu MT940
    ordered_keys = list(dict.fromkeys(
        [k for k in preferred if k in _CSV_PARSERS]
        + [k for k in _CSV_PARSERS if k not in preferred]
    ))

    # Sprawdź MT940 jako osobny krok (lazy import — unikamy cyklicznych zależności)
    from .mt940 import detect as mt940_detect, parse_to_statement as mt940_parse

    # Jeśli MT940 jest preferowany (firma może mieć dostęp do MT940 przez systemy bankowe)
    if any(k in preferred for k in ('mt940', 'swift')):
        if mt940_detect(content):
            return mt940_parse(content)

    # Próbuj CSV parsery według kolejności
    for key in ordered_keys:
        parser = _CSV_PARSERS[key]
        if parser.detect(content):
            return parser.parse(content)

    # MT940 jako fallback
    if mt940_detect(content):
        return mt940_parse(content)

    raise ValueError(
        'Nie rozpoznano formatu pliku. Obsługiwane formaty: MT940 (SWIFT), '
        'CSV VeloBank, CSV Erste Bank. Sprawdź czy plik pochodzi z obsługiwanego banku.'
    )
