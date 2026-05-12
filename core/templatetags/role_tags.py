from django import template
from core.permissions import has_min_role

register = template.Library()


@register.simple_tag(takes_context=True)
def has_role(context, min_role: str) -> bool:
    request = context.get('request')
    if not request:
        return False
    return has_min_role(request.user, min_role)


@register.filter
def get_item(dictionary, key):
    """{{ mydict|get_item:key }}"""
    if isinstance(dictionary, dict):
        return dictionary.get(key)
    return None


@register.filter
def plmoney(value):
    """Formatuje kwotę w stylu polskim: 1 234 567,89"""
    try:
        from decimal import Decimal
        val = Decimal(str(value))
        formatted = f"{val:,.2f}"
        integer_part, decimal_part = formatted.split('.')
        return f"{integer_part.replace(',', ' ')},{decimal_part}"
    except (ValueError, TypeError):
        return str(value)


@register.filter
def pretty_xml(value):
    """Formatuje XML do czytelnej postaci z wcięciami."""
    if not value:
        return ''
    try:
        import xml.dom.minidom
        return xml.dom.minidom.parseString(
            value.encode('utf-8') if isinstance(value, str) else value
        ).toprettyxml(indent='  ')
    except Exception:
        return value


@register.simple_tag(takes_context=True)
def querystring(context, **kwargs):
    """
    Zwraca aktualny query string z podmienionymi wartościami.
    Użycie: ?{% querystring page=3 %}
    """
    request = context.get('request')
    if not request:
        return ''
    params = request.GET.copy()
    for key, value in kwargs.items():
        if value is None:
            params.pop(key, None)
        else:
            params[key] = value
    return params.urlencode()
