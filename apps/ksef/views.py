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
        obj = self.get_object()
        notif_obj = NotificationConfig.get_active()
        return {
            'form': form or KSeFConfigForm(instance=obj),
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
