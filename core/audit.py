def _get_ip(request):
    xff = request.META.get('HTTP_X_FORWARDED_FOR')
    if xff:
        return xff.split(',')[0].strip()
    return request.META.get('REMOTE_ADDR')


def log_event(actor, action, *, entity=None, detail=None, request=None):
    from .models import AuditLog
    entry = AuditLog(actor=actor, action=action, detail=detail or {})
    if entity is not None:
        entry.entity_type = entity.__class__.__name__
        entry.entity_id = str(entity.pk) if entity.pk else ''
        entry.entity_repr = str(entity)[:255]
    if request is not None:
        entry.ip_address = _get_ip(request)
    entry.save()
