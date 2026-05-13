from functools import wraps
from django.contrib.auth.mixins import LoginRequiredMixin
from django.core.exceptions import PermissionDenied

ROLE_HIERARCHY = {
    'viewer': 0,
    'accountant': 1,
    'approver': 2,
    'admin': 3,
}


def has_min_role(user, min_role: str) -> bool:
    if not user.is_authenticated:
        return False
    if user.is_superuser:
        return True
    return ROLE_HIERARCHY.get(user.role, -1) >= ROLE_HIERARCHY.get(min_role, 999)


class RoleRequiredMixin(LoginRequiredMixin):
    min_role: str = 'viewer'

    def dispatch(self, request, *args, **kwargs):
        if not request.user.is_authenticated:
            return self.handle_no_permission()
        if not has_min_role(request.user, self.min_role):
            raise PermissionDenied
        return super().dispatch(request, *args, **kwargs)


def role_required(min_role: str):
    def decorator(view_func):
        @wraps(view_func)
        def wrapper(request, *args, **kwargs):
            if not has_min_role(request.user, min_role):
                raise PermissionDenied
            return view_func(request, *args, **kwargs)
        return wrapper
    return decorator


class CompanyQuerysetMixin:
    """Filtruje queryset do danych firmy zalogowanego usera. Superuser widzi wszystko."""

    def get_queryset(self):
        qs = super().get_queryset()
        user = self.request.user
        if user.is_superuser:
            return qs
        if user.company_id:
            return qs.filter(company_id=user.company_id)
        return qs.none()


class CompanyObjectMixin:
    """Weryfikuje dostęp do obiektu — 403 jeśli należy do innej firmy."""

    def get_object(self, queryset=None):
        obj = super().get_object(queryset)
        user = self.request.user
        if user.is_superuser:
            return obj
        if hasattr(obj, 'company_id') and obj.company_id != user.company_id:
            raise PermissionDenied
        return obj


class CompanyAccessMixin(CompanyQuerysetMixin, CompanyObjectMixin):
    """Łączy filtrowanie querysetu i weryfikację dostępu do obiektu."""


def company_filter(user) -> dict:
    """Zwraca dict do filtrowania querysetu po firmie. Superuser — bez filtra."""
    if user.is_superuser:
        return {}
    return {'company_id': user.company_id}
