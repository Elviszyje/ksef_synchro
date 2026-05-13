from django.contrib.auth.views import LoginView, LogoutView
from django.contrib.auth.mixins import LoginRequiredMixin
from django.views.generic import ListView, CreateView, UpdateView, DeleteView
from django.urls import reverse_lazy
from django.contrib import messages
from core.permissions import RoleRequiredMixin, company_filter, is_super_admin
from core.audit import log_event
from core.models import AuditLog
from .models import CustomUser, Company
from .forms import LoginForm, UserCreateForm, UserUpdateForm, CompanyForm


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
