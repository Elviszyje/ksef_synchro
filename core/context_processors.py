import datetime
from django.utils import timezone


def ksef_token_alert(request):
    if not request.user.is_authenticated:
        return {}
    if getattr(request.user, 'role', None) != 'admin':
        return {}

    try:
        from apps.ksef.models import KSeFConfig
        if request.user.is_superuser:
            config = KSeFConfig.objects.first()
        else:
            config = KSeFConfig.objects.filter(company_id=request.user.company_id).first()
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
