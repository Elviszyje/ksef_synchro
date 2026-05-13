from functools import wraps
from django.contrib.auth.mixins import LoginRequiredMixin
from django.core.exceptions import PermissionDenied

ROLE_HIERARCHY = {
    'viewer': 0,
    'accountant': 1,
    'approver': 2,
    'admin': 3,
    'super_admin': 4,
}


def is_super_admin(user) -> bool:
    return user.is_superuser or getattr(user, 'role', '') == 'super_admin'


def has_min_role(user, min_role: str) -> bool:
    if not user.is_authenticated:
        return False
    if is_super_admin(user):
        return True
    return ROLE_HIERARCHY.get(user.role, -1) >= ROLE_HIERARCHY.get(min_role, 999)


class RoleRequiredMixin(LoginRequiredMixin):
    min_role: str = 'viewer'
    superuser_only: bool = False

    def dispatch(self, request, *args, **kwargs):
        if not request.user.is_authenticated:
            return self.handle_no_permission()
        if self.superuser_only and not is_super_admin(request.user):
            raise PermissionDenied
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
    """Filtruje queryset do danych firmy zalogowanego usera. Super admin widzi wszystko."""

    def get_queryset(self):
        qs = super().get_queryset()
        user = self.request.user
        if is_super_admin(user):
            return qs
        if user.company_id:
            return qs.filter(company_id=user.company_id)
        return qs.none()


class CompanyObjectMixin:
    """Weryfikuje dostęp do obiektu — 403 jeśli należy do innej firmy."""

    def get_object(self, queryset=None):
        obj = super().get_object(queryset)
        user = self.request.user
        if is_super_admin(user):
            return obj
        if hasattr(obj, 'company_id') and obj.company_id != user.company_id:
            raise PermissionDenied
        return obj


class CompanyAccessMixin(CompanyQuerysetMixin, CompanyObjectMixin):
    """Łączy filtrowanie querysetu i weryfikację dostępu do obiektu."""


def company_filter(user) -> dict:
    """Zwraca dict do filtrowania querysetu po firmie. Super admin — bez filtra."""
    if is_super_admin(user):
        return {}
    return {'company_id': user.company_id}
