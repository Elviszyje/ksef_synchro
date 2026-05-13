from django.db.models import Q
from django.template.response import TemplateResponse
from django.views.generic import View

from core.permissions import RoleRequiredMixin
from .models import AuditLog


class AuditLogListView(RoleRequiredMixin, View):
    superuser_only = True
    template_name = 'core/audit_log.html'
    paginate_by = 50

    def get(self, request):
        from django.core.paginator import Paginator

        qs = AuditLog.objects.select_related('actor').order_by('-timestamp')

        action = request.GET.get('action', '')
        actor_q = request.GET.get('actor', '').strip()
        date_from = request.GET.get('date_from', '')
        date_to = request.GET.get('date_to', '')

        if action:
            qs = qs.filter(action=action)
        if actor_q:
            qs = qs.filter(
                Q(actor__username__icontains=actor_q)
                | Q(actor__first_name__icontains=actor_q)
                | Q(actor__last_name__icontains=actor_q)
            )
        if date_from:
            qs = qs.filter(timestamp__date__gte=date_from)
        if date_to:
            qs = qs.filter(timestamp__date__lte=date_to)

        paginator = Paginator(qs, self.paginate_by)
        page_obj = paginator.get_page(request.GET.get('page', 1))

        return TemplateResponse(request, self.template_name, {
            'page_obj': page_obj,
            'total_count': qs.count(),
            'action_choices': AuditLog.ACTION_CHOICES,
            'selected_action': action,
            'actor_query': actor_q,
            'date_from': date_from,
            'date_to': date_to,
        })
