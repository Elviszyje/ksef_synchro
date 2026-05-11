import datetime
from django.utils import timezone


def ksef_token_alert(request):
    if not request.user.is_authenticated:
        return {}
    if getattr(request.user, 'role', None) != 'admin':
        return {}

    try:
        from apps.ksef.models import KSeFConfig
        config = KSeFConfig.get_active()
    except Exception:
        return {}

    if not config:
        return {'ksef_alert': 'no_config'}

    if not config.token_expiry:
        return {}

    remaining = config.token_expiry - timezone.now()
    days = remaining.days

    if remaining.total_seconds() <= 0:
        return {'ksef_alert': 'expired', 'ksef_alert_days': 0}
    elif days <= 14:
        return {'ksef_alert': 'expiring', 'ksef_alert_days': days}

    return {}
