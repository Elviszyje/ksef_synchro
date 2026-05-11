import logging
from datetime import datetime, timezone, timedelta

from celery import shared_task
from django.utils import timezone as dj_timezone

logger = logging.getLogger(__name__)


@shared_task(bind=True, max_retries=3, default_retry_delay=300, queue='ksef_sync')
def sync_ksef_invoices(self, force=False):
    """
    Główne zadanie synchronizacji faktur z KSeF.
    force=True pomija guardy sync_enabled, okna czasowego i interwału (ręczne wywołanie).
    """
    from apps.ksef.models import KSeFConfig, KSeFSyncLog
    from apps.ksef.client import KSeFClient, KSeFAPIError, KSeFAuthError
    from apps.ksef.parser import FA2Parser
    from apps.invoices.models import Invoice

    config = KSeFConfig.get_active()
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

    log = KSeFSyncLog.objects.create(celery_task_id=self.request.id or '')
    parser = FA2Parser()

    try:
        token = config.get_token()
        if not token:
            raise KSeFAuthError('Brak tokena KSeF w konfiguracji')

        date_to = datetime.now(tz=timezone.utc)
        date_from = config.last_sync_at.replace(tzinfo=timezone.utc) if config.last_sync_at else (
            date_to - timedelta(days=90)
        )

        with KSeFClient(config.base_url, config.nip, token) as client:
            session_token = client.init_session()
            fetched = 0
            new_count = 0
            new_refs = []

            try:
                for header in client.iter_purchase_invoices(session_token, date_from, date_to):
                    ksef_ref = header.get('ksefReferenceNumber', '')
                    if not ksef_ref:
                        continue

                    fetched += 1

                    # Pobierz XML faktury
                    try:
                        xml_bytes = client.get_invoice_xml(session_token, ksef_ref)
                        parsed = parser.parse(xml_bytes, ksef_reference_number=ksef_ref)
                    except KSeFAPIError as e:
                        logger.error('Błąd pobierania faktury %s: %s', ksef_ref, e)
                        continue

                    # Zapisz lub pomiń istniejące
                    defaults = _parsed_to_invoice_fields(parsed)
                    _, created = Invoice.objects.get_or_create(
                        ksef_reference_number=ksef_ref,
                        defaults=defaults,
                    )
                    if created:
                        new_count += 1
                        new_refs.append(ksef_ref)

            finally:
                client.terminate_session(session_token)

        log.invoices_fetched = fetched
        log.invoices_new = new_count
        log.status = KSeFSyncLog.STATUS_SUCCESS
        log.finished_at = dj_timezone.now()
        log.save()

        config.last_sync_at = dj_timezone.now()
        config.save(update_fields=['last_sync_at'])

        from core.audit import log_event
        from core.models import AuditLog
        log_event(None, AuditLog.ACTION_KSEF_SYNC,
                  detail={'triggered_by': 'celery', 'fetched': fetched, 'new': new_count})

        if new_refs:
            from .notifications import maybe_notify
            new_invoices = list(Invoice.objects.filter(ksef_reference_number__in=new_refs))
            maybe_notify(new_invoices)

        logger.info('KSeF sync zakończony: %d pobranych, %d nowych', fetched, new_count)

    except (KSeFAuthError, KSeFAPIError, Exception) as exc:
        log.status = KSeFSyncLog.STATUS_ERROR
        log.error_message = str(exc)
        log.finished_at = dj_timezone.now()
        log.save()
        logger.error('KSeF sync błąd: %s', exc)
        raise self.retry(exc=exc)


@shared_task(queue='ksef_sync')
def refresh_ksef_token():
    """Loguje alert gdy token KSeF wygasa w ciągu 14 dni."""
    from apps.ksef.models import KSeFConfig
    from core.audit import log_event
    from core.models import AuditLog

    config = KSeFConfig.get_active()
    if not config or not config.token_expiry:
        return

    remaining = config.token_expiry - dj_timezone.now()
    days = remaining.days

    if remaining.total_seconds() <= 0:
        logger.error('KSeF token WYGASŁ (%s) — synchronizacja nie działa!', config.token_expiry)
        log_event(None, AuditLog.ACTION_KSEF_CONFIG,
                  detail={'alert': 'token_expired', 'expired_at': config.token_expiry.isoformat()})
    elif days <= 14:
        logger.warning('KSeF token wygasa za %d dni (%s)', days, config.token_expiry)
        log_event(None, AuditLog.ACTION_KSEF_CONFIG,
                  detail={'alert': 'token_expiring_soon', 'days_left': days,
                          'expires_at': config.token_expiry.isoformat()})
        # Nowy token wymaga inicjalizacji sesji przez użytkownika (zapis w panelu admina)


@shared_task(queue='ksef_sync')
def send_morning_digest():
    """Wysyła poranny digest zakolejkowanych powiadomień."""
    from apps.ksef.models import NotificationConfig, PendingNotification
    from apps.ksef.notifications import send_telegram, format_digest_message

    config = NotificationConfig.get_active()
    if not config or not config.enabled:
        return

    now_h = dj_timezone.localtime().hour
    if now_h != config.digest_time.hour:
        return

    pending = list(PendingNotification.objects.filter(sent=False).order_by('created_at'))
    if not pending:
        return

    text = format_digest_message(pending)
    ok = send_telegram(config.get_bot_token(), config.telegram_chat_id, text)
    if ok:
        PendingNotification.objects.filter(pk__in=[p.pk for p in pending]).update(
            sent=True, sent_at=dj_timezone.now(),
        )
        logger.info('Digest wysłany: %d powiadomień', len(pending))
    else:
        logger.error('Błąd wysyłki digestu')


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
        'seller_name': parsed.seller_name or 'Nieznany sprzedawca',
        'seller_nip': parsed.seller_nip,
        'seller_address': parsed.seller_address,
        'buyer_nip': parsed.buyer_nip,
        'amount_net': parsed.amount_net,
        'amount_vat': parsed.amount_vat,
        'amount_gross': parsed.amount_gross,
        'currency': parsed.currency or 'PLN',
        'is_split_payment': parsed.is_split_payment,
        'vat_amount_split': parsed.vat_amount_split,
        'issue_date': parse_date(parsed.issue_date) or __import__('datetime').date.today(),
        'payment_due_date': parse_date(parsed.payment_due_date),
        'bank_account_number': parsed.bank_account_number,
        'payment_title': parsed.payment_title,
        'raw_xml': parsed.raw_xml,
        'status': Invoice.STATUS_NEW,
    }
