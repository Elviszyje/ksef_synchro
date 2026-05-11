import logging

import httpx
from django.utils import timezone

logger = logging.getLogger(__name__)

TELEGRAM_API = 'https://api.telegram.org/bot{token}/sendMessage'


def send_telegram(bot_token: str, chat_id: str, text: str) -> bool:
    if not bot_token or not chat_id:
        logger.warning('Telegram: brak tokena lub chat_id')
        return False
    try:
        url = TELEGRAM_API.format(token=bot_token)
        resp = httpx.post(url, json={'chat_id': chat_id, 'text': text, 'parse_mode': 'HTML'},
                          timeout=10)
        if resp.status_code == 200:
            return True
        logger.error('Telegram API błąd %s: %s', resp.status_code, resp.text[:200])
        return False
    except Exception as exc:
        logger.error('Telegram send wyjątek: %s', exc)
        return False


def is_quiet(now_t, quiet_from, quiet_to) -> bool:
    """True jeśli now_t należy do okna ciszy (obsługuje przejście przez północ)."""
    if quiet_from <= quiet_to:
        return quiet_from <= now_t <= quiet_to
    return now_t >= quiet_from or now_t <= quiet_to


def format_new_invoices_message(invoices: list) -> str:
    lines = [f'<b>📄 Nowe faktury w KSeF</b>', f'Liczba: <b>{len(invoices)}</b>\n']
    for inv in invoices[:10]:
        lines.append(
            f'• {inv.invoice_number} — {inv.seller_name[:30]} — '
            f'<b>{inv.amount_gross:,.2f} {inv.currency}</b>'
        )
    if len(invoices) > 10:
        lines.append(f'… i {len(invoices) - 10} więcej')
    return '\n'.join(lines)


def format_digest_message(pending_qs) -> str:
    total = sum(p.invoice_count for p in pending_qs)
    lines = [
        f'<b>☀️ Poranny digest KSeF</b>',
        f'Łącznie nowych faktur podczas ciszy nocnej: <b>{total}</b>\n',
    ]
    for p in pending_qs:
        ts = p.created_at.astimezone(timezone.get_current_timezone()).strftime('%H:%M')
        lines.append(f'[{ts}] {p.invoice_count} faktur')
    return '\n'.join(lines)


def maybe_notify(new_invoices: list):
    from .models import NotificationConfig, PendingNotification
    config = NotificationConfig.get_active()
    if not config or not config.enabled:
        return

    now_t = timezone.localtime().time()
    text = format_new_invoices_message(new_invoices)

    if is_quiet(now_t, config.quiet_from, config.quiet_to):
        PendingNotification.objects.create(
            invoice_count=len(new_invoices),
            summary=text,
        )
        logger.info('Powiadomienie zakolejkowane (cisza nocna): %d faktur', len(new_invoices))
    else:
        ok = send_telegram(config.get_bot_token(), config.telegram_chat_id, text)
        logger.info('Telegram wysłany: %s', 'OK' if ok else 'BŁĄD')
