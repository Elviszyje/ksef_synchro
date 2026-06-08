from dataclasses import dataclass, field
from decimal import Decimal
from datetime import date
from typing import Optional


@dataclass
class ParsedTransaction:
    transaction_date: date
    value_date: date
    amount: Decimal
    currency: str
    is_credit: bool
    description: str
    reference: str = ''


@dataclass
class ParsedStatement:
    account_number: str = ''
    statement_date: Optional[date] = None
    transactions: list = field(default_factory=list)  # list[ParsedTransaction]
    bank_key: str = 'other'
