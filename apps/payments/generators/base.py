from abc import ABC, abstractmethod
from decimal import Decimal
from typing import Iterable

from apps.invoices.models import Invoice


def format_amount(amount: Decimal) -> str:
    """Formatuje kwotę jako 'zzzzzzzzzz,gg' (10 cyfr całkowitych, przecinek, 2 grosze)."""
    cents = int(round(amount * 100))
    return f'{cents // 100},{cents % 100:02d}'


class BasePaymentGenerator(ABC):
    ENCODING: str = 'windows-1250'
    EXTENSION: str = 'txt'

    def __init__(self, debit_account: str, company_name: str, company_address: str):
        self.debit_account = debit_account.replace(' ', '')
        self.company_name = company_name[:35]
        self.company_address = company_address[:35]

    def generate(self, invoices: Iterable[Invoice]) -> bytes:
        invoice_list = list(invoices)
        lines: list[str] = []
        lines.extend(self._header_lines())
        for i, inv in enumerate(invoice_list, start=1):
            lines.extend(self._invoice_lines(inv, line_number=i))
        content = '\r\n'.join(lines)
        return content.encode(self.ENCODING, errors='replace')

    def _header_lines(self) -> list[str]:
        return []

    @abstractmethod
    def _invoice_lines(self, inv: Invoice, line_number: int) -> list[str]:
        ...

    @staticmethod
    def _clean_text(text: str, max_len: int, allowed_extra: str = '') -> str:
        """Zastępuje niedozwolone znaki spacją i obcina do max_len."""
        import re
        # Dopuszczone w standardzie Erste: 0-9 A-Z a-z i polskie diakrytyki + wybrane znaki
        result = re.sub(r'[^\w\s\-\.,\:\;\+\=\[\]\{\}\!\@\#\$\%\^\&\*\(\)\/\?' + allowed_extra + r']', ' ', text, flags=re.UNICODE)
        return result[:max_len].strip()
