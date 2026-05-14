from django.contrib.auth.views import LoginView, LogoutView
from django.contrib.auth.mixins import LoginRequiredMixin
from django.http import JsonResponse
from django.views.generic import ListView, CreateView, UpdateView, DeleteView, View
from django.urls import reverse_lazy
from django.contrib import messages
from core.permissions import RoleRequiredMixin, company_filter, is_super_admin
from core.audit import log_event
from core.models import AuditLog
from .models import CustomUser, Company, CompanyLicense
from .forms import LoginForm, UserCreateForm, UserUpdateForm, CompanyForm, LicenseForm


class CustomLoginView(LoginView):
    template_name = 'accounts/login.html'
    form_class = LoginForm
    redirect_authenticated_user = True


class CustomLogoutView(LogoutView):
    next_page = 'accounts:login'


class UserListView(RoleRequiredMixin, ListView):
    min_role = 'admin'
    model = CustomUser
    template_name = 'accounts/user_list.html'
    context_object_name = 'users'
    ordering = ['username']

    def get_queryset(self):
        qs = super().get_queryset()
        if self.request.user.is_superuser:
            return qs
        return qs.filter(company=self.request.user.company)


class UserCreateView(RoleRequiredMixin, CreateView):
    min_role = 'admin'
    model = CustomUser
    form_class = UserCreateForm
    template_name = 'accounts/user_form.html'
    success_url = reverse_lazy('accounts:user_list')

    def get_form_kwargs(self):
        kwargs = super().get_form_kwargs()
        kwargs['requesting_user'] = self.request.user
        return kwargs

    def form_valid(self, form):
        if form.instance.role == CustomUser.ROLE_SUPER_ADMIN and not is_super_admin(self.request.user):
            form.add_error('role', 'Nie masz uprawnień do nadania tej roli.')
            return self.form_invalid(form)
        company = form.instance.company
        if company:
            lic = getattr(company, 'license', None)
            if lic and not lic.can_add_user():
                form.add_error(None, f'Plan {lic.get_plan_display()} pozwala na max {lic.user_limit()} aktywnych użytkowników.')
                return self.form_invalid(form)
        response = super().form_valid(form)
        log_event(self.request.user, AuditLog.ACTION_USER_CREATE, entity=form.instance,
                  request=self.request,
                  detail={'username': form.instance.username, 'role': form.instance.role})
        messages.success(self.request, f'Użytkownik {form.instance.username} został utworzony.')
        return response


class UserUpdateView(RoleRequiredMixin, UpdateView):
    min_role = 'admin'
    model = CustomUser
    form_class = UserUpdateForm
    template_name = 'accounts/user_form.html'
    success_url = reverse_lazy('accounts:user_list')

    def get_form_kwargs(self):
        kwargs = super().get_form_kwargs()
        kwargs['requesting_user'] = self.request.user
        return kwargs

    def form_valid(self, form):
        if form.instance.role == CustomUser.ROLE_SUPER_ADMIN and not is_super_admin(self.request.user):
            form.add_error('role', 'Nie masz uprawnień do nadania tej roli.')
            return self.form_invalid(form)
        response = super().form_valid(form)
        log_event(self.request.user, AuditLog.ACTION_USER_MODIFY, entity=form.instance,
                  request=self.request,
                  detail={'username': form.instance.username,
                          'changed_fields': list(form.changed_data)})
        messages.success(self.request, f'Użytkownik {form.instance.username} został zaktualizowany.')
        return response


class UserDeleteView(RoleRequiredMixin, DeleteView):
    min_role = 'admin'
    model = CustomUser
    template_name = 'accounts/user_confirm_delete.html'
    success_url = reverse_lazy('accounts:user_list')

    def form_valid(self, form):
        if self.object == self.request.user:
            messages.error(self.request, 'Nie możesz usunąć własnego konta.')
            return self.get(self.request)
        username = self.object.username
        log_event(self.request.user, AuditLog.ACTION_USER_DELETE,
                  request=self.request, detail={'username': username})
        messages.success(self.request, f'Użytkownik {username} został usunięty.')
        return super().form_valid(form)


class CompanyListView(RoleRequiredMixin, ListView):
    min_role = 'admin'
    model = Company
    template_name = 'accounts/company_list.html'
    context_object_name = 'companies'
    ordering = ['name']

    def get_queryset(self):
        qs = super().get_queryset()
        if self.request.user.is_superuser:
            return qs
        return qs.filter(pk=self.request.user.company_id)


class CompanyCreateView(RoleRequiredMixin, CreateView):
    min_role = 'admin'
    model = Company
    form_class = CompanyForm
    template_name = 'accounts/company_form.html'
    success_url = reverse_lazy('accounts:company_list')

    def dispatch(self, request, *args, **kwargs):
        if not request.user.is_superuser:
            from django.core.exceptions import PermissionDenied
            raise PermissionDenied
        return super().dispatch(request, *args, **kwargs)

    def form_valid(self, form):
        response = super().form_valid(form)
        messages.success(self.request, f'Firma {form.instance.name} została utworzona.')
        return response


class CompanyUpdateView(RoleRequiredMixin, UpdateView):
    min_role = 'admin'
    model = Company
    form_class = CompanyForm
    template_name = 'accounts/company_form.html'
    success_url = reverse_lazy('accounts:company_list')

    def get_queryset(self):
        qs = super().get_queryset()
        if self.request.user.is_superuser:
            return qs
        return qs.filter(pk=self.request.user.company_id)

    def form_valid(self, form):
        response = super().form_valid(form)
        messages.success(self.request, f'Firma {form.instance.name} została zaktualizowana.')
        return response


class LicenseUpdateView(RoleRequiredMixin, UpdateView):
    superuser_only = True
    model = CompanyLicense
    form_class = LicenseForm
    template_name = 'accounts/license_form.html'
    success_url = reverse_lazy('accounts:company_list')

    def get_object(self, queryset=None):
        return CompanyLicense.objects.get(company_id=self.kwargs['company_pk'])

    def form_valid(self, form):
        response = super().form_valid(form)
        messages.success(self.request, f'Licencja firmy {form.instance.company.name} została zaktualizowana.')
        return response


class StoreWebhookView(View):
    """Przyjmuje zakup z App Store / Play Store — zapisuje token. Bez weryfikacji receipt."""

    def post(self, request):
        import hmac
        import json
        from datetime import date
        from django.conf import settings

        secret = settings.STORE_WEBHOOK_SECRET
        sig = request.headers.get('X-Webhook-Secret', '')
        if not secret or not hmac.compare_digest(sig, secret):
            return JsonResponse({'error': 'Unauthorized'}, status=401)

        try:
            data = json.loads(request.body)
        except (ValueError, KeyError):
            return JsonResponse({'error': 'Invalid JSON'}, status=400)

        company_id = data.get('company_id')
        platform = data.get('platform', '')
        token = data.get('purchase_token', '')
        plan = data.get('plan', CompanyLicense.PLAN_FREE)

        if plan not in dict(CompanyLicense.PLANS):
            return JsonResponse({'error': 'Invalid plan'}, status=400)

        lic, _ = CompanyLicense.objects.get_or_create(
            company_id=company_id,
            defaults={'plan': CompanyLicense.PLAN_FREE, 'valid_from': date.today()},
        )
        lic.store_platform = platform
        lic.store_purchase_token = token
        lic.plan = plan
        lic.save(update_fields=['store_platform', 'store_purchase_token', 'plan', 'updated_at'])
        return JsonResponse({'status': 'ok'})
