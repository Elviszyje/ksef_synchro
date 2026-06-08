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


def license_alert(request):
    if not request.user.is_authenticated or not getattr(request.user, 'company_id', None):
        return {}
    try:
        lic = request.user.company.license
    except Exception:
        return {}
    limit = lic.invoice_limit()
    if limit is None:
        return {}
    used = lic.invoices_last_30_days()
    if used >= limit:
        return {'license_alert': 'limit_reached', 'license_used': used, 'license_limit': limit}
    if used >= int(limit * 0.8):
        return {'license_alert': 'approaching_limit', 'license_used': used, 'license_limit': limit}
    return {}


def outgoing_license_alert(request):
    if not request.user.is_authenticated or not getattr(request.user, 'company_id', None):
        return {}
    try:
        lic = request.user.company.license
    except Exception:
        return {}
    limit = lic.outgoing_invoice_limit()
    if limit is None:
        return {}
    used = lic.outgoing_invoices_this_month()
    if used >= limit:
        return {'outgoing_license_alert': 'limit_reached', 'outgoing_license_used': used, 'outgoing_license_limit': limit}
    if used >= int(limit * 0.8):
        return {'outgoing_license_alert': 'approaching_limit', 'outgoing_license_used': used, 'outgoing_license_limit': limit}
    return {}
