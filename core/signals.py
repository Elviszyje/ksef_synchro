from django.contrib.auth.signals import user_logged_in, user_logged_out
from django.dispatch import receiver


@receiver(user_logged_in)
def on_login(sender, request, user, **kwargs):
    from core.audit import log_event
    from core.models import AuditLog
    log_event(user, AuditLog.ACTION_LOGIN, entity=user, request=request)


@receiver(user_logged_out)
def on_logout(sender, request, user, **kwargs):
    if user:
        from core.audit import log_event
        from core.models import AuditLog
        log_event(user, AuditLog.ACTION_LOGOUT, entity=user, request=request)
