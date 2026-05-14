import logging
from datetime import datetime, timezone, timedelta

from celery import shared_task
from django.utils import timezone as dj_timezone

logger = logging.getLogger(__name__)


@shared_task(bind=True, max_retries=3, default_retry_delay=300, queue='ksef_sync')
def sync_ksef_invoices(self, force=False, date_from_override: str | None = None, company_id: int | None = None):
    """
    Główne zadanie synchronizacji faktur z KSeF.
    force=True pomija guardy sync_enabled, okna czasowego i interwału (ręczne wywołanie).
    date_from_override: ISO date string (YYYY-MM-DD) — wymusza zakres od tej daty.
    company_id: ID firmy do synchronizacji. None = brak izolacji (tryb single-tenant legacy).
    """
    from apps.ksef.models import KSeFConfig, KSeFSyncLog
    from apps.ksef.client import KSeFClient, KSeFAPIError, KSeFAuthError, KSeFRateLimitError
    from apps.ksef.parser import FA2Parser
    from apps.invoices.models import Invoice

    if company_id is not None:
        config = KSeFConfig.objects.filter(company_id=company_id).first()
    else:
        config = KSeFConfig.objects.first()
    if not config:
        logger.warning('KSeF sync: brak konfiguracji')
        return

    if not force:
        if not config.sync_enabled:
            logger.debug('KSeF sync: wyłączony w konfiguracji')
            return

        if config.sync_window_start and config.sync_window_end:
            now_t = dj_timezone.localtime().time()
            s, e = config.sync_window_start, config.sync_window_end
            in_window = (s <= now_t <= e) if s <= e else (now_t >= s or now_t <= e)
            if not in_window:
                logger.debug('KSeF sync: poza oknem %s–%s', s, e)
                return

        if config.last_sync_at:
            elapsed_h = (dj_timezone.now() - config.last_sync_at).total_seconds() / 3600
            if elapsed_h < config.sync_interval_hours:
                logger.debug('KSeF sync: za wcześnie (%.1fh < %dh)', elapsed_h, config.sync_interval_hours)
                return

    log = KSeFSyncLog.objects.create(
        celery_task_id=self.request.id or '',
        company_id=company_id,
    )

    # Sprawdź limit licencji przed startem
    from apps.accounts.models import CompanyLicense
    lic = CompanyLicense.objects.filter(company_id=company_id).first() if company_id else None
    if lic and not lic.can_sync_invoice():
        KSeFSyncLog.objects.filter(pk=log.pk).update(
            status=KSeFSyncLog.STATUS_ERROR,
            error_message=f'Limit licencji ({lic.invoice_limit()} faktur / 30 dni) osiągnięty.',
            finished_at=dj_timezone.now(),
        )
        logger.warning('KSeF sync: limit licencji dla firmy %s', company_id)
        return

    parser = FA2Parser()

    try:
        token = config.get_token()
        if not token:
            raise KSeFAuthError('Brak tokena KSeF w konfiguracji')

        date_to = datetime.now(tz=timezone.utc)
        if date_from_override:
            date_from = datetime.fromisoformat(date_from_override).replace(tzinfo=timezone.utc)
        elif config.last_sync_at:
            date_from = config.last_sync_at.replace(tzinfo=timezone.utc)
        else:
            date_from = date_to - timedelta(days=30)

        fetched = 0
        new_count = 0
        new_refs = []
        cancelled = False

        KSeFSyncLog.objects.filter(pk=log.pk).update(current_stage='Autoryzacja...')

        with KSeFClient(config.base_url, config.nip, token) as client:
            session_token = client.init_session()

            KSeFSyncLog.objects.filter(pk=log.pk).update(current_stage='Sprawdzanie limitów...')
            client.check_quota(session_token)

            KSeFSyncLog.objects.filter(pk=log.pk).update(current_stage='Pobieranie faktur...')

            # None = nie sprawdzano, True = XML działa, False = 404 (skip dla reszty)
            xml_available = None

            try:
                for header in client.iter_purchase_invoices(session_token, date_from, date_to):
                    ksef_ref = header.get('ksefNumber') or header.get('ksefReferenceNumber', '')
                    if not ksef_ref:
                        continue

                    fetched += 1
                    parsed = None

                    if xml_available is not False:
                        xml_bytes = client.get_invoice_xml(session_token, ksef_ref)
                        if xml_bytes is not None:
                            xml_available = True
                            parsed = parser.parse(xml_bytes, ksef_ref)
                        elif xml_available is None:
                            xml_available = False
                            logger.info('KSeF: XML niedostępny (404) — sync tylko z metadanych')

                    if parsed is None:
                        parsed = _parsed_from_metadata(header, buyer_nip_fallback=config.nip)

                    defaults = _parsed_to_invoice_fields(parsed)
                    if company_id is not None:
                        defaults['company_id'] = company_id
                    obj, created = Invoice.objects.get_or_create(
                        ksef_reference_number=ksef_ref,
                        company_id=company_id,
                        defaults=defaults,
                    )
                    if created:
                        new_count += 1
                        new_refs.append(ksef_ref)
                        if lic and not lic.can_sync_invoice():
                            logger.info('KSeF sync: limit licencji osiągnięty po %d nowych fakturach', new_count)
                            cancelled = True
                            break
                    else:
                        _update_invoice_from_api(obj, defaults)

                    # Co 5 faktur: aktualizuj progress i sprawdź czy nie anulowano
                    if fetched % 5 == 0:
                        mode = 'XML' if xml_available else 'metadane'
                        # Używamy filter(status=RUNNING) — nie nadpisujemy jeśli UI już anulowało
                        still_running = KSeFSyncLog.objects.filter(
                            pk=log.pk, status=KSeFSyncLog.STATUS_RUNNING,
                        ).update(
                            invoices_fetched=fetched,
                            invoices_new=new_count,
                            current_stage=f'Pobieranie ({mode}): {fetched} faktur...',
                        )
                        if not still_running or KSeFSyncLog.objects.filter(
                            pk=log.pk, cancel_requested=True,
                        ).exists():
                            logger.info('KSeF sync: zatrzymanie po %d fakturach', fetched)
                            cancelled = True
                            break

            finally:
                client.terminate_session(session_token)

        if cancelled:
            limit_msg = (
                f'Osiągnięto limit licencji ({lic.invoice_limit()} faktur / 30 dni). '
                if lic and lic.invoice_limit() and not lic.can_sync_invoice()
                else ''
            )
            KSeFSyncLog.objects.filter(pk=log.pk, status=KSeFSyncLog.STATUS_RUNNING).update(
                invoices_fetched=fetched,
                invoices_new=new_count,
                status=KSeFSyncLog.STATUS_CANCELLED,
                current_stage='',
                error_message=f'{limit_msg}Anulowano po pobraniu {fetched} faktur ({new_count} nowych)',
                finished_at=dj_timezone.now(),
            )
            if fetched > 0:
                config.last_sync_at = dj_timezone.now()
                config.save(update_fields=['last_sync_at'])
            logger.info('KSeF sync anulowany: %d pobranych, %d nowych', fetched, new_count)
            return

        KSeFSyncLog.objects.filter(pk=log.pk, status=KSeFSyncLog.STATUS_RUNNING).update(
            invoices_fetched=fetched,
            invoices_new=new_count,
            status=KSeFSyncLog.STATUS_SUCCESS,
            current_stage='',
            finished_at=dj_timezone.now(),
        )

        config.last_sync_at = dj_timezone.now()
        config.save(update_fields=['last_sync_at'])

        from core.audit import log_event
        from core.models import AuditLog
        log_event(None, AuditLog.ACTION_KSEF_SYNC,
                  detail={'triggered_by': 'celery', 'fetched': fetched, 'new': new_count})

        if new_refs:
            from .notifications import maybe_notify
            new_invoices = list(Invoice.objects.filter(
                ksef_reference_number__in=new_refs,
                company_id=company_id,
            ))
            maybe_notify(new_invoices, company_id=company_id)

        logger.info('KSeF sync zakończony: %d pobranych, %d nowych', fetched, new_count)

    except KSeFRateLimitError as exc:
        # Rate limit — zapisz częściowy postęp żeby następny sync nie powtarzał
        # już pobranych faktur; nie retryuj (quota wyczerpana na X minut/godzin)
        log.invoices_fetched = fetched
        log.invoices_new = new_count
        log.status = KSeFSyncLog.STATUS_ERROR
        log.error_message = str(exc)
        log.finished_at = dj_timezone.now()
        log.save()
        if fetched > 0:
            config.last_sync_at = dj_timezone.now()
            config.save(update_fields=['last_sync_at'])
            logger.warning('KSeF rate limit: zapisano %d faktur, last_sync_at zaktualizowany', fetched)
        logger.error('KSeF sync przerwany limitem API: %s', exc)

    except (KSeFAuthError, KSeFAPIError, Exception) as exc:
        log.status = KSeFSyncLog.STATUS_ERROR
        log.error_message = str(exc)
        log.finished_at = dj_timezone.now()
        log.save()
        logger.error('KSeF sync błąd: %s', exc)
        raise self.retry(exc=exc)


@shared_task(queue='ksef_sync')
def dispatch_company_syncs():
    """Uruchamia sync_ksef_invoices per firma — wywoływana przez beat co godzinę."""
    from apps.ksef.models import KSeFConfig

    dispatched = 0
    for config in KSeFConfig.objects.filter(sync_enabled=True).select_related('company'):
        company_id = config.company_id
        sync_ksef_invoices.delay(company_id=company_id)
        dispatched += 1
    logger.info('Dispatched KSeF sync dla %d firm', dispatched)


@shared_task(queue='ksef_sync')
def refresh_ksef_token():
    """Loguje alert gdy token KSeF wygasa w ciągu 14 dni — iteruje po wszystkich firmach."""
    from apps.ksef.models import KSeFConfig
    from core.audit import log_event
    from core.models import AuditLog

    for config in KSeFConfig.objects.filter(sync_enabled=True).select_related('company'):
        if not config.token_expiry:
            continue

        remaining = config.token_expiry - dj_timezone.now()
        days = remaining.days
        nip = config.nip

        if remaining.total_seconds() <= 0:
            logger.error('KSeF token WYGASŁ (NIP %s, %s) — synchronizacja nie działa!', nip, config.token_expiry)
            log_event(None, AuditLog.ACTION_KSEF_CONFIG,
                      detail={'alert': 'token_expired', 'nip': nip, 'expired_at': config.token_expiry.isoformat()})
        elif days <= 14:
            logger.warning('KSeF token wygasa za %d dni (NIP %s, %s)', days, nip, config.token_expiry)
            log_event(None, AuditLog.ACTION_KSEF_CONFIG,
                      detail={'alert': 'token_expiring_soon', 'nip': nip, 'days_left': days,
                              'expires_at': config.token_expiry.isoformat()})


@shared_task(queue='ksef_sync')
def send_morning_digest():
    """Wysyła poranny digest zakolejkowanych powiadomień — per firma."""
    from apps.ksef.models import NotificationConfig, PendingNotification
    from apps.ksef.notifications import send_telegram, format_digest_message

    now_h = dj_timezone.localtime().hour

    for config in NotificationConfig.objects.filter(enabled=True).select_related('company'):
        if now_h != config.digest_time.hour:
            continue

        pending = list(
            PendingNotification.objects.filter(sent=False, company=config.company).order_by('created_at')
        )
        if not pending:
            continue

        text = format_digest_message(pending)
        ok = send_telegram(config.get_bot_token(), config.telegram_chat_id, text)
        if ok:
            PendingNotification.objects.filter(pk__in=[p.pk for p in pending]).update(
                sent=True, sent_at=dj_timezone.now(),
            )
            logger.info('Digest wysłany (firma %s): %d powiadomień', config.company, len(pending))
        else:
            logger.error('Błąd wysyłki digestu (firma %s)', config.company)


def _parsed_to_invoice_fields(parsed) -> dict:
    from apps.invoices.models import Invoice
    from datetime import date

    def parse_date(s: str | None):
        if not s:
            return None
        try:
            return date.fromisoformat(s[:10])
        except (ValueError, TypeError):
            return None

    return {
        'invoice_number': parsed.invoice_number or parsed.ksef_reference_number,
        'seller_name': parsed.seller_name or parsed.seller_nip or 'Nieznany sprzedawca',
        'seller_nip': parsed.seller_nip,
        'seller_address': parsed.seller_address,
        'buyer_nip': parsed.buyer_nip,
        'amount_net': parsed.amount_net,
        'amount_vat': parsed.amount_vat,
        'amount_gross': parsed.amount_gross,
        'currency': (parsed.currency or 'PLN')[:3].strip().upper(),
        'is_split_payment': parsed.is_split_payment,
        'vat_amount_split': parsed.vat_amount_split,
        'issue_date': parse_date(parsed.issue_date) or __import__('datetime').date.today(),
        'payment_due_date': parse_date(parsed.payment_due_date),
        'bank_account_number': parsed.bank_account_number,
        'payment_title': parsed.payment_title,
        'payment_date': parse_date(parsed.payment_date),
        'payment_form': parsed.payment_form,
        'invoice_type': parsed.invoice_type,
        'description': parsed.description,
        'raw_xml': parsed.raw_xml,
        'status': Invoice.STATUS_PAID if parsed.is_paid else Invoice.STATUS_NEW,
    }


def _parsed_from_metadata(header: dict, buyer_nip_fallback: str = ''):
    """
    Tworzy ParsedInvoice z metadanych query (gdy XML niedostępny lub nieuprawiony).

    KSeF 2.0 używa struktury subjectBy/subjectTo (nie seller/buyer jak v1).
    Obsługuje oba warianty dla kompatybilności wstecznej.
    Przy zapytaniu Subject2 (nabywca = my) API często nie zwraca buyer info —
    wtedy używa buyer_nip_fallback (NIP z konfiguracji KSeF).
    """
    from decimal import Decimal
    from apps.ksef.parser import ParsedInvoice

    logger.debug('KSeF metadata header: %s', header)

    ref = header.get('ksefNumber') or header.get('ksefReferenceNumber', '')

    # Numer faktury (P_2) — pole 'invoiceNumber' w API v2
    invoice_no = header.get('invoiceNumber') or header.get('invoiceNo') or ''

    # Sprzedawca — KSeF v2: subjectBy; fallback: seller (v1/niestandardowe)
    subj_by = header.get('subjectBy') or header.get('seller') or {}
    ident_by = subj_by.get('identifier') or subj_by.get('subjectIdentifier') or {}
    seller_nip = (
        subj_by.get('nip')
        or ident_by.get('identifier')
        or ident_by.get('value')
        or ''
    )
    seller_name = (
        subj_by.get('subjectName')
        or subj_by.get('name')
        or subj_by.get('fullName')
        or subj_by.get('tradeName')
        or ''
    )
    if not seller_name:
        logger.warning('KSeF metadata: brak nazwy sprzedawcy (ref=%s) subjectBy=%s', ref, subj_by)

    # Nabywca — w trybie Subject2 API może nie zwracać buyer info
    subj_to = header.get('subjectTo') or header.get('buyer') or {}
    ident_to = subj_to.get('identifier') or subj_to.get('subjectIdentifier') or {}
    buyer_nip = (
        subj_to.get('nip')
        or ident_to.get('identifier')
        or ident_to.get('value')
        or buyer_nip_fallback
    )

    # Kwoty — API v2 używa 'gross'/'net'/'vat'; fallback: grossAmount itp.
    gross = header.get('gross') or header.get('grossAmount') or header.get('grossValue') or 0
    net   = header.get('net')   or header.get('netAmount')   or header.get('netValue')   or 0
    vat   = header.get('vat')   or header.get('vatAmount')   or header.get('vatValue')   or 0

    currency = header.get('currency') or header.get('currencyCode') or 'PLN'

    return ParsedInvoice(
        ksef_reference_number=ref,
        invoice_number=invoice_no or ref,
        seller_nip=seller_nip,
        seller_name=seller_name,
        buyer_nip=buyer_nip,
        issue_date=header.get('invoiceIssueDate', ''),
        amount_gross=Decimal(str(gross)),
        amount_net=Decimal(str(net)),
        amount_vat=Decimal(str(vat)),
        currency=currency,
        payment_title=f'Faktura {invoice_no}' if invoice_no else f'Faktura {ref}',
    )


def _update_invoice_from_api(invoice, defaults: dict):
    """
    Aktualizuje istniejącą fakturę danymi z API.
    Zachowuje pola edytowane przez użytkownika: status, notes, updated_by.
    Pola XML (termin płatności, konto, kwoty netto/VAT) — nadpisuje tylko gdy
    nowe dane są niepuste (unikamy wyzerowania wartości pobranych wcześniej z XML).
    """
    from decimal import Decimal
    from apps.invoices.models import Invoice as InvoiceModel

    ALWAYS = ('invoice_number', 'seller_nip', 'buyer_nip',
              'amount_gross', 'currency', 'issue_date', 'payment_title')
    FROM_XML = ('amount_net', 'amount_vat', 'payment_due_date',
                'bank_account_number', 'seller_address', 'raw_xml',
                'is_split_payment', 'vat_amount_split',
                'invoice_type', 'description',
                'payment_date', 'payment_form')

    updates = {f: defaults[f] for f in ALWAYS if f in defaults}

    for f in FROM_XML:
        val = defaults.get(f)
        # Nie nadpisuj zerami/pustymi — oznaczałoby to brak XML, nie rzeczywiste zero
        if val not in (None, '', 0, False, Decimal('0')):
            updates[f] = val

    # seller_name: nadpisuj tylko prawdziwą nazwą (nie placeholderem)
    seller_name = defaults.get('seller_name', '')
    if seller_name and seller_name != 'Nieznany sprzedawca':
        updates['seller_name'] = seller_name

    # Auto-zmiana statusu na oplacona gdy XML potwierdza zapłatę
    if defaults.get('payment_date') and invoice.status != InvoiceModel.STATUS_PAID:
        updates['status'] = InvoiceModel.STATUS_PAID

    if updates:
        InvoiceModel.objects.filter(pk=invoice.pk).update(**updates)
