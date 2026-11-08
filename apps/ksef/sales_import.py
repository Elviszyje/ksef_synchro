"""
Import faktur sprzedażowych z KSeF (firma jest sprzedawcą, Subject1).

Zasady (te same w aplikacji iOS, `KSeFSalesImporter.swift`):
1. Faktura z tym samym numerem KSeF już jest w bazie → pomijamy.
2. Faktura o tym samym numerze jest wysyłana albo przyjęta przez KSeF z aplikacji
   (status „sending”/„accepted”) → to ta sama faktura, numer KSeF uzupełni odświeżenie statusu.
3. Szkic albo faktura odrzucona/oczekująca ma numer zajęty już w KSeF → dostaje
   kolejny wolny numer (inaczej wysyłka dałaby duplikat numeru).
4. Nabywca z prawidłowym NIP-em trafia do listy nabywców, jeśli jeszcze go nie ma.
"""
import logging
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone

from django.db import transaction

from apps.ksef.sales_parser import ParsedSale, parse_sales_invoice

logger = logging.getLogger(__name__)

# Pierwsza synchronizacja sięga do startu obowiązkowego KSeF, ale nie dalej niż rok wstecz.
KSEF_MANDATORY_START = datetime(2026, 2, 1, tzinfo=timezone.utc)


@dataclass
class SalesImportResult:
    fetched: int = 0
    new: int = 0
    skipped: int = 0
    renumbered: int = 0


def initial_sales_date_from(now: datetime) -> datetime:
    return max(KSEF_MANDATORY_START, now - timedelta(days=365))


def is_known(company_id, ksef_number: str, invoice_number: str) -> bool:
    """Reguły 1 i 2 — sprawdzane przed pobraniem XML (limit KSeF ok. 64 XML/h)."""
    from apps.outgoing.models import OutgoingInvoice
    qs = OutgoingInvoice.objects.filter(company_id=company_id)
    if qs.filter(ksef_reference_number=ksef_number).exists():
        return True
    return bool(invoice_number) and qs.filter(
        invoice_number=invoice_number,
        status__in=[OutgoingInvoice.STATUS_SENDING, OutgoingInvoice.STATUS_ACCEPTED,
                    OutgoingInvoice.STATUS_IMPORTED],
    ).exists()


def save_imported_sale(company, sale: ParsedSale, ksef_number: str, xml: bytes):
    """Zapisuje fakturę ze statusem „imported”. Zwraca (faktura albo None, czy przenumerowano szkic)."""
    from apps.outgoing.models import Buyer, InvoiceItem, OutgoingInvoice

    with transaction.atomic():
        if is_known(company.pk, ksef_number, sale.invoice_number):
            return None, False

        renumbered = False
        conflict = (OutgoingInvoice.objects.select_for_update()
                    .filter(company=company, invoice_number=sale.invoice_number).first())
        if conflict is not None:
            # Reguła 3: tylko faktury, których jeszcze nie ma w KSeF (szkic, kolejka, odrzucona).
            old_number = conflict.invoice_number
            conflict.invoice_number = OutgoingInvoice.generate_number(company)
            conflict.error_message = (
                f'Numer {old_number} jest już użyty w KSeF przez fakturę {ksef_number} — '
                f'nadano nowy numer {conflict.invoice_number}.'
            )
            conflict.save(update_fields=['invoice_number', 'error_message', 'updated_at'])
            renumbered = True
            logger.warning('Import sprzedaży: szkic %s przenumerowany na %s', old_number, conflict.invoice_number)

        buyer = None
        if len(sale.buyer_nip) == 10 and sale.buyer_nip.isdigit():
            buyer, _ = Buyer.objects.get_or_create(
                company=company, nip=sale.buyer_nip,
                defaults={'name': sale.buyer_name[:255], 'address': sale.buyer_address},
            )

        invoice = OutgoingInvoice.objects.create(
            company=company,
            invoice_number=sale.invoice_number[:64],
            issue_date=date.fromisoformat(sale.issue_date[:10]),
            delivery_date=date.fromisoformat(sale.delivery_date[:10]) if sale.delivery_date else None,
            payment_due_date=date.fromisoformat(sale.payment_due_date[:10]),
            payment_form=sale.payment_form,
            currency=sale.currency,
            buyer=buyer,
            buyer_nip=sale.buyer_nip[:10],
            buyer_name=sale.buyer_name[:255],
            buyer_address=sale.buyer_address,
            notes=sale.notes,
            vat_exemption_type=sale.vat_exemption_type,
            vat_exemption_basis=sale.vat_exemption_basis,
            status=OutgoingInvoice.STATUS_IMPORTED,
            ksef_reference_number=ksef_number,
            generated_xml=xml.decode('utf-8', errors='replace'),
        )
        # bulk_create pomija InvoiceItem.save() — kwoty zostają takie jak w XML, bez przeliczania.
        InvoiceItem.objects.bulk_create([
            InvoiceItem(
                invoice=invoice, lp=lp, name=item.name, unit=item.unit, quantity=item.quantity,
                unit_price_net=item.unit_price_net, vat_rate=item.vat_rate,
                amount_net=item.amount_net, amount_vat=item.amount_vat, amount_gross=item.amount_gross,
            )
            for lp, item in enumerate(sale.items, start=1)
        ])
        return invoice, renumbered


def import_sales_invoices(client, session_token: str, company, date_from: datetime,
                          date_to: datetime) -> SalesImportResult:
    """
    Pobiera metadane faktur sprzedażowych i importuje nowe. KSeFRateLimitError
    jest propagowany — wywołujący nie przesuwa wtedy kursora, a kolejny przebieg
    pominie już zaimportowane faktury bez pobierania ich XML.
    """
    result = SalesImportResult()
    for header in client.iter_sales_invoices(session_token, date_from, date_to):
        ksef_number = header.get('ksefNumber') or header.get('ksefReferenceNumber', '')
        if not ksef_number:
            continue
        result.fetched += 1
        invoice_number = header.get('invoiceNumber') or header.get('invoiceNo') or ''
        if is_known(company.pk, ksef_number, invoice_number):
            continue

        xml = client.get_invoice_xml(session_token, ksef_number)
        sale = parse_sales_invoice(xml) if xml else None
        if sale is None:
            # 404 albo nieczytelny XML — bez treści nie odtworzymy pozycji faktury.
            logger.info('Import sprzedaży: pominięto %s (brak lub nieczytelny XML)', ksef_number)
            result.skipped += 1
            continue

        try:
            invoice, renumbered = save_imported_sale(company, sale, ksef_number, xml)
        except Exception:
            # Jedna wadliwa faktura nie może blokować importu pozostałych.
            logger.exception('Import sprzedaży: nie udało się zapisać %s', ksef_number)
            result.skipped += 1
            continue
        if invoice is not None:
            result.new += 1
        result.renumbered += int(renumbered)
    return result
