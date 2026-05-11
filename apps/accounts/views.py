from django.contrib.auth.views import LoginView, LogoutView
from django.contrib.auth.mixins import LoginRequiredMixin
from django.views.generic import ListView, CreateView, UpdateView, DeleteView
from django.urls import reverse_lazy
from django.contrib import messages
from core.permissions import RoleRequiredMixin
from core.audit import log_event
from core.models import AuditLog
from .models import CustomUser
from .forms import LoginForm, UserCreateForm, UserUpdateForm


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


class UserCreateView(RoleRequiredMixin, CreateView):
    min_role = 'admin'
    model = CustomUser
    form_class = UserCreateForm
    template_name = 'accounts/user_form.html'
    success_url = reverse_lazy('accounts:user_list')

    def form_valid(self, form):
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

    def form_valid(self, form):
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
