from django.contrib import messages
from django.shortcuts import redirect
from django.views.generic import CreateView, UpdateView, ListView, View
from django.urls import reverse_lazy

from core.permissions import RoleRequiredMixin, CompanyAccessMixin, company_filter
from core.audit import log_event
from core.models import AuditLog
from .models import KSeFConfig, KSeFSyncLog, NotificationConfig
from .forms import KSeFConfigForm, NotificationConfigForm


class KSeFConfigView(RoleRequiredMixin, View):
    min_role = 'admin'
    template_name = 'ksef/config.html'

    def get_object(self):
        return KSeFConfig.objects.filter(**company_filter(self.request.user)).first()

    def _get_context(self, form=None, notif_form=None):
        from django.conf import settings
        obj = self.get_object()
        notif_obj = NotificationConfig.objects.filter(**company_filter(self.request.user)).first()
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
        notif_obj = NotificationConfig.objects.filter(**company_filter(self.request.user)).first()
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


class KSeFConfigCompanyView(RoleRequiredMixin, View):
    """Konfiguracja KSeF dla konkretnej firmy — tylko dla superadmina."""
    superuser_only = True
    template_name = 'ksef/config.html'

    def _get_company(self, company_pk):
        from apps.accounts.models import Company
        from django.shortcuts import get_object_or_404
        return get_object_or_404(Company, pk=company_pk)

    def _get_context(self, company, form=None, notif_form=None):
        obj = KSeFConfig.objects.filter(company=company).first()
        notif_obj = NotificationConfig.objects.filter(company=company).first()
        if form is None:
            form = KSeFConfigForm(instance=obj, initial={'nip': company.nip} if not obj else {})
        return {
            'form': form,
            'notif_form': notif_form or NotificationConfigForm(instance=notif_obj),
            'config': obj,
            'notif_config': notif_obj,
            'company': company,
        }

    def get(self, request, company_pk):
        from django.template.response import TemplateResponse
        company = self._get_company(company_pk)
        return TemplateResponse(request, self.template_name, self._get_context(company))

    def post(self, request, company_pk):
        from django.template.response import TemplateResponse
        company = self._get_company(company_pk)
        obj = KSeFConfig.objects.filter(company=company).first()
        notif_obj = NotificationConfig.objects.filter(company=company).first()
        action = request.POST.get('_action', 'ksef')

        if action == 'notification':
            notif_form = NotificationConfigForm(request.POST, instance=notif_obj)
            if notif_form.is_valid():
                inst = notif_form.save(commit=False)
                inst.company = company
                inst.save()
                messages.success(request, 'Konfiguracja powiadomień zapisana.')
                return redirect('ksef:config_company', company_pk=company_pk)
            return TemplateResponse(request, self.template_name,
                                    self._get_context(company, notif_form=notif_form))

        form = KSeFConfigForm(request.POST, instance=obj)
        if form.is_valid():
            inst = form.save(commit=False)
            inst.company = company
            inst.save()
            log_event(request.user, AuditLog.ACTION_KSEF_CONFIG,
                      detail={'changed_fields': list(form.changed_data), 'company': company.name},
                      request=request)
            messages.success(request, f'Konfiguracja KSeF dla {company.name} zapisana.')
            return redirect('ksef:config_company', company_pk=company_pk)
        return TemplateResponse(request, self.template_name, self._get_context(company, form=form))


class KSeFManualSyncView(RoleRequiredMixin, View):
    min_role = 'admin'

    def post(self, request):
        from .tasks import sync_ksef_invoices
        config = KSeFConfig.objects.filter(**company_filter(request.user)).first()
        if not config:
            messages.error(request, 'Brak konfiguracji KSeF. Skonfiguruj połączenie najpierw.')
            return redirect('ksef:config')
        date_from = request.POST.get('date_from', '').strip() or None
        company_id = None if request.user.is_superuser else request.user.company_id
        sync_ksef_invoices.delay(force=True, date_from_override=date_from, company_id=company_id)
        log_event(request.user, AuditLog.ACTION_KSEF_SYNC,
                  detail={'triggered_by': 'manual', 'date_from': date_from}, request=request)
        msg = f'Synchronizacja uruchomiona od {date_from}.' if date_from else 'Synchronizacja z KSeF uruchomiona w tle.'
        messages.info(request, msg)
        return redirect('ksef:logs')


class TestNotificationView(RoleRequiredMixin, View):
    min_role = 'admin'

    def post(self, request):
        from django.http import HttpResponse
        from .models import NotificationConfig
        from .notifications import send_telegram
        config = NotificationConfig.objects.filter(**company_filter(request.user)).first()
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


class KSeFSyncLogListView(RoleRequiredMixin, CompanyAccessMixin, ListView):
    min_role = 'admin'
    model = KSeFSyncLog
    template_name = 'ksef/sync_log_list.html'
    context_object_name = 'logs'
    paginate_by = 30
    ordering = ['-started_at']

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx['running'] = KSeFSyncLog.objects.filter(
            status=KSeFSyncLog.STATUS_RUNNING, **company_filter(self.request.user)
        ).order_by('-started_at').first()
        return ctx


class KSeFSyncStatusView(RoleRequiredMixin, View):
    """Partial dla HTMX — zwraca kartę statusu bieżącego joba."""
    min_role = 'admin'

    def get(self, request):
        from django.template.response import TemplateResponse
        from django.utils import timezone as dj_tz

        running = KSeFSyncLog.objects.filter(
            status=KSeFSyncLog.STATUS_RUNNING, **company_filter(request.user)
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
            status=KSeFSyncLog.STATUS_RUNNING, **company_filter(request.user)
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
