from rest_framework.permissions import BasePermission
from core.permissions import has_min_role, is_super_admin


class HasMinRole(BasePermission):
    min_role = 'viewer'

    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated and has_min_role(request.user, self.min_role))


def role_permission(min_role: str):
    return type(f'Has{min_role.title()}Role', (HasMinRole,), {'min_role': min_role})


IsViewer = role_permission('viewer')
IsAccountant = role_permission('accountant')
IsApprover = role_permission('approver')
IsAdmin = role_permission('admin')


class BelongsToCompany(BasePermission):
    def has_object_permission(self, request, view, obj):
        if is_super_admin(request.user):
            return True
        return getattr(obj, 'company_id', None) == request.user.company_id
