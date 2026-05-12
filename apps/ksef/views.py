from django.contrib import messages
from django.shortcuts import redirect
from django.views.generic import CreateView, UpdateView, ListView, View
from django.urls import reverse_lazy

from core.permissions import RoleRequiredMixin
from core.audit import log_event
from core.models import AuditLog
from .models import KSeFConfig, KSeFSyncLog, NotificationConfig
from .forms import KSeFConfigForm, NotificationConfigForm


class KSeFConfigView(RoleRequiredMixin, View):
    min_role = 'admin'
    template_name = 'ksef/config.html'

    def get_object(self):
        return KSeFConfig.get_active()

    def _get_context(self, form=None, notif_form=None):
        from django.conf import settings
        obj = self.get_object()
        notif_obj = NotificationConfig.get_active()
        if form is None:
            initial = {}
            if not obj and settings.COMPANY_NIP:
                initial['nip'] = settings.COMPANY_NIP
            form = KSeFConfigForm(instance=obj, initial=initial)
        return {
            'form': form,
            'notif_form': notif_form or NotificationConfigForm(instance=notif_obj),
            'config': obj,
            'notif_config': notif_obj,
        }

    def get(self, request):
        from django.template.response import TemplateResponse
        return TemplateResponse(request, self.template_name, self._get_context())

    def post(self, request):
        from django.template.response import TemplateResponse
        obj = self.get_object()
        notif_obj = NotificationConfig.get_active()
        action = request.POST.get('_action', 'ksef')

        if action == 'notification':
            notif_form = NotificationConfigForm(request.POST, instance=notif_obj)
            if notif_form.is_valid():
                notif_form.save()
                messages.success(request, 'Konfiguracja powiadomień zapisana.')
                return redirect('ksef:config')
            return TemplateResponse(request, self.template_name,
                                    self._get_context(notif_form=notif_form))

        form = KSeFConfigForm(request.POST, instance=obj)
        if form.is_valid():
            form.save()
            log_event(request.user, AuditLog.ACTION_KSEF_CONFIG,
                      detail={'changed_fields': list(form.changed_data)}, request=request)
            messages.success(request, 'Konfiguracja KSeF zapisana.')
            return redirect('ksef:config')
        return TemplateResponse(request, self.template_name, self._get_context(form=form))


class KSeFManualSyncView(RoleRequiredMixin, View):
    min_role = 'admin'

    def post(self, request):
        from .tasks import sync_ksef_invoices
        config = KSeFConfig.get_active()
        if not config:
            messages.error(request, 'Brak konfiguracji KSeF. Skonfiguruj połączenie najpierw.')
            return redirect('ksef:config')
        sync_ksef_invoices.delay(force=True)
        log_event(request.user, AuditLog.ACTION_KSEF_SYNC,
                  detail={'triggered_by': 'manual'}, request=request)
        messages.info(request, 'Synchronizacja z KSeF uruchomiona w tle.')
        return redirect('ksef:logs')


class TestNotificationView(RoleRequiredMixin, View):
    min_role = 'admin'

    def post(self, request):
        from django.http import HttpResponse
        from .models import NotificationConfig
        from .notifications import send_telegram
        config = NotificationConfig.get_active()
        if not config or not config.telegram_chat_id:
            return HttpResponse(
                '<span class="badge bg-danger">Brak konfiguracji</span>', status=200)
        ok = send_telegram(
            config.get_bot_token(),
            config.telegram_chat_id,
            '✅ <b>Test powiadomień KSeF</b>\nPołączenie działa poprawnie.',
        )
        if ok:
            return HttpResponse('<span class="badge bg-success">Wysłano ✓</span>')
        return HttpResponse('<span class="badge bg-danger">Błąd wysyłki</span>')


class KSeFSyncLogListView(RoleRequiredMixin, ListView):
    min_role = 'admin'
    model = KSeFSyncLog
    template_name = 'ksef/sync_log_list.html'
    context_object_name = 'logs'
    paginate_by = 30
    ordering = ['-started_at']

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx['running'] = KSeFSyncLog.objects.filter(
            status=KSeFSyncLog.STATUS_RUNNING
        ).order_by('-started_at').first()
        return ctx


class KSeFSyncStatusView(RoleRequiredMixin, View):
    """Partial dla HTMX — zwraca kartę statusu bieżącego joba."""
    min_role = 'admin'

    def get(self, request):
        from django.template.response import TemplateResponse
        from django.utils import timezone as dj_tz

        running = KSeFSyncLog.objects.filter(
            status=KSeFSyncLog.STATUS_RUNNING
        ).order_by('-started_at').first()

        response = TemplateResponse(
            request,
            'ksef/partials/sync_status.html',
            {'running': running},
        )
        # Gdy job właśnie się skończył — odśwież stronę (HTMX header)
        if not running:
            recent = KSeFSyncLog.objects.exclude(
                status=KSeFSyncLog.STATUS_RUNNING
            ).order_by('-finished_at').first()
            if recent and recent.finished_at:
                age = (dj_tz.now() - recent.finished_at).total_seconds()
                if age < 10:
                    response['HX-Refresh'] = 'true'
        return response


class KSeFSyncCancelView(RoleRequiredMixin, View):
    """Natychmiast ustawia CANCELLED w DB i próbuje odwołać task Celery."""
    min_role = 'admin'

    def post(self, request):
        from django.template.response import TemplateResponse
        from django.utils import timezone as dj_tz

        running = KSeFSyncLog.objects.filter(
            status=KSeFSyncLog.STATUS_RUNNING
        ).order_by('-started_at').first()

        if running:
            KSeFSyncLog.objects.filter(pk=running.pk).update(
                cancel_requested=True,
                status=KSeFSyncLog.STATUS_CANCELLED,
                error_message=(
                    f'Anulowano przez użytkownika'
                    f' (pobrano {running.invoices_fetched} faktur,'
                    f' {running.invoices_new} nowych)'
                ),
                finished_at=dj_tz.now(),
                current_stage='',
            )
            if running.celery_task_id:
                try:
                    from celery import current_app
                    current_app.control.revoke(
                        running.celery_task_id, terminate=True, signal='SIGTERM',
                    )
                except Exception:
                    pass

        response = TemplateResponse(
            request,
            'ksef/partials/sync_status.html',
            {'running': None},
        )
        response['HX-Refresh'] = 'true'
        return response
