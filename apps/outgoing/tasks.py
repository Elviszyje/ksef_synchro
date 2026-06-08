import logging

from celery import shared_task
from django.db import transaction
from django.utils import timezone as dj_timezone

logger = logging.getLogger(__name__)


@shared_task(bind=True, max_retries=3, default_retry_delay=60, queue='ksef_sync')
def send_queued_outgoing_invoices(self, company_id: int | None = None):
    """
    Pobiera faktury wychodzące ze statusem 'queued' i wysyła je do KSeF.
    Uruchamiany co 5 minut przez Celery Beat.
    """
    from apps.outgoing.models import OutgoingInvoice
    from apps.accounts.models import CompanyLicense
    from apps.ksef.models import KSeFConfig
    from apps.ksef.client import KSeFClient, KSeFAuthError, KSeFAPIError, KSeFRateLimitError
    from apps.ksef.generator import FA2Generator, FA2GeneratorError

    qs = OutgoingInvoice.objects.filter(status=OutgoingInvoice.STATUS_QUEUED)
    if company_id is not None:
        qs = qs.filter(company_id=company_id)

    with transaction.atomic():
        invoices = list(qs.select_for_update(skip_locked=True).select_related('company', 'items'))
        if not invoices:
            return

    generator = FA2Generator()

    # Grupuj per firma (każda firma ma osobny token KSeF)
    by_company: dict[int, list] = {}
    for inv in invoices:
        by_company.setdefault(inv.company_id, []).append(inv)

    for cid, company_invoices in by_company.items():
        config = KSeFConfig.objects.filter(company_id=cid).first()
        if not config:
            logger.warning('send_outgoing: brak KSeFConfig dla firmy %s', cid)
            for inv in company_invoices:
                inv.status = OutgoingInvoice.STATUS_REJECTED
                inv.error_message = 'Brak konfiguracji KSeF dla tej firmy.'
                inv.save(update_fields=['status', 'error_message', 'updated_at'])
            continue

        lic = CompanyLicense.objects.filter(company_id=cid).first()
        company = company_invoices[0].company

        try:
            api_token = config.get_token()
            if not api_token:
                raise KSeFAuthError('Brak tokena KSeF w konfiguracji')
            with KSeFClient(config.base_url, config.nip, api_token) as client:
                session_token = client.init_session()
                client.check_quota(session_token)

                for inv in company_invoices:
                    if lic and not lic.can_send_outgoing_invoice():
                        logger.warning('send_outgoing: limit licencji dla firmy %s', cid)
                        inv.status = OutgoingInvoice.STATUS_REJECTED
                        inv.error_message = (
                            f'Limit licencji ({lic.outgoing_invoice_limit()} faktur/miesiąc) osiągnięty.'
                        )
                        inv.save(update_fields=['status', 'error_message', 'updated_at'])
                        continue

                    try:
                        xml_bytes = generator.generate(inv, company, config)
                        inv.generated_xml = xml_bytes.decode('utf-8')

                        submission_ref = client.send_invoice(session_token, xml_bytes)
                        inv.ksef_submission_reference = submission_ref
                        inv.status = OutgoingInvoice.STATUS_SENDING
                        inv.error_message = ''
                        inv.save(update_fields=[
                            'generated_xml', 'ksef_submission_reference',
                            'status', 'error_message', 'updated_at',
                        ])
                        logger.info('Faktura %s wysłana do KSeF, ref=%s', inv.invoice_number, submission_ref)

                    except FA2GeneratorError as exc:
                        logger.error('Błąd generowania XML dla %s: %s', inv.invoice_number, exc)
                        inv.status = OutgoingInvoice.STATUS_REJECTED
                        inv.error_message = f'Błąd generowania XML: {exc}'
                        inv.save(update_fields=['status', 'error_message', 'updated_at'])

                    except KSeFRateLimitError as exc:
                        logger.warning('Rate limit przy wysyłce faktury %s, czekam %ds', inv.invoice_number, exc.wait_seconds)
                        inv.status = OutgoingInvoice.STATUS_QUEUED
                        inv.error_message = f'Przekroczono limit API KSeF, ponowna próba za {exc.wait_seconds}s'
                        inv.save(update_fields=['status', 'error_message', 'updated_at'])
                        break

                    except KSeFAPIError as exc:
                        logger.error('Błąd KSeF API dla %s: %s', inv.invoice_number, exc)
                        inv.status = OutgoingInvoice.STATUS_REJECTED
                        inv.error_message = str(exc)
                        inv.save(update_fields=['status', 'error_message', 'updated_at'])

        except (KSeFAuthError, KSeFAPIError) as exc:
            logger.error('send_outgoing: błąd autoryzacji/API dla firmy %s: %s', cid, exc)
            for inv in company_invoices:
                if inv.status == OutgoingInvoice.STATUS_QUEUED:
                    inv.error_message = f'Błąd KSeF: {exc}'
                    inv.save(update_fields=['error_message', 'updated_at'])
            raise self.retry(exc=exc)

        except Exception as exc:
            logger.exception('send_outgoing: nieoczekiwany błąd dla firmy %s', cid)
            raise self.retry(exc=exc)


@shared_task(bind=True, max_retries=5, default_retry_delay=60, queue='ksef_sync')
def poll_outgoing_invoice_status(self, company_id: int | None = None):
    """
    Sprawdza status wysłanych faktur wychodzących (status 'sending').
    Uruchamiany co 5 minut przez Celery Beat.
    """
    from apps.outgoing.models import OutgoingInvoice
    from apps.ksef.models import KSeFConfig
    from apps.ksef.client import KSeFClient, KSeFAuthError, KSeFAPIError

    qs = OutgoingInvoice.objects.filter(status=OutgoingInvoice.STATUS_SENDING)
    if company_id is not None:
        qs = qs.filter(company_id=company_id)

    invoices = list(qs.select_related('company'))
    if not invoices:
        return

    by_company: dict[int, list] = {}
    for inv in invoices:
        by_company.setdefault(inv.company_id, []).append(inv)

    for cid, company_invoices in by_company.items():
        config = KSeFConfig.objects.filter(company_id=cid).first()
        if not config:
            continue

        try:
            api_token = config.get_token()
            if not api_token:
                continue
            with KSeFClient(config.base_url, config.nip, api_token) as client:
                session_token = client.init_session()

                for inv in company_invoices:
                    if not inv.ksef_submission_reference:
                        logger.warning('poll_outgoing: brak submission_reference dla %s', inv.pk)
                        continue
                    try:
                        result = client.get_send_status(session_token, inv.ksef_submission_reference)
                        code = result.get('processing_code')

                        if code == 200:
                            inv.ksef_reference_number = result.get('ksef_reference_number') or ''
                            try:
                                upo = client.get_upo(session_token, inv.ksef_reference_number)
                                inv.upo_xml = upo.decode('utf-8', errors='replace')
                            except Exception as exc:
                                logger.warning('Nie udało się pobrać UPO dla %s: %s', inv.invoice_number, exc)
                            inv.status = OutgoingInvoice.STATUS_ACCEPTED
                            inv.error_message = ''
                            inv.save(update_fields=[
                                'ksef_reference_number', 'upo_xml',
                                'status', 'error_message', 'updated_at',
                            ])
                            logger.info('Faktura %s zaakceptowana przez KSeF, ksefRef=%s',
                                        inv.invoice_number, inv.ksef_reference_number)

                        elif code == 400:
                            error_detail = str(result.get('raw', {}).get('processingCode', {}).get('description', ''))
                            inv.status = OutgoingInvoice.STATUS_REJECTED
                            inv.error_message = error_detail or 'Faktura odrzucona przez KSeF.'
                            inv.save(update_fields=['status', 'error_message', 'updated_at'])
                            logger.warning('Faktura %s odrzucona przez KSeF: %s', inv.invoice_number, error_detail)

                        else:
                            logger.debug('Faktura %s w trakcie przetwarzania (code=%s)', inv.invoice_number, code)

                    except KSeFAPIError as exc:
                        logger.error('poll_outgoing: błąd API dla %s: %s', inv.invoice_number, exc)

        except (KSeFAuthError, KSeFAPIError) as exc:
            logger.error('poll_outgoing: błąd sesji KSeF dla firmy %s: %s', cid, exc)
            raise self.retry(exc=exc)

        except Exception as exc:
            logger.exception('poll_outgoing: nieoczekiwany błąd dla firmy %s', cid)
            raise self.retry(exc=exc)
