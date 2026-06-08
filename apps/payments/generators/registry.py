"""
Rejestr generatorów płatności per bank.
Klucz: bank_key z bank_detection.BANK_LABELS
Wartość: (klasa generatora, rozszerzenie pliku, etykieta formatu)
"""
from .erste_bank import ErsteBankGenerator
from .mbank import MBankGenerator
from .elixir import ElixirGenerator

BANK_GENERATORS: dict[str, tuple] = {
    'erste':  (ErsteBankGenerator, 'txt', 'Erste Bank'),
    'mbank':  (MBankGenerator,     'txt', 'mBank'),
    'elixir': (ElixirGenerator,    'pli', 'Elixir-0'),
}

# Banki obsługiwane przez własny format (nie Elixir)
NATIVE_BANK_KEYS = {'erste', 'mbank'}


def get_generator_for_bank(bank_key: str):
    """Zwraca (GeneratorClass, extension, label) dla danego banku. Fallback: Elixir."""
    return BANK_GENERATORS.get(bank_key, BANK_GENERATORS['elixir'])
