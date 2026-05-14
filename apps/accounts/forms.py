from django import forms
from django.contrib.auth.forms import AuthenticationForm, UserCreationForm, UserChangeForm
from .models import CustomUser, Company, CompanyLicense


class LoginForm(AuthenticationForm):
    username = forms.CharField(
        label='Login',
        widget=forms.TextInput(attrs={'class': 'form-control', 'autofocus': True, 'placeholder': 'Login'}),
    )
    password = forms.CharField(
        label='Hasło',
        widget=forms.PasswordInput(attrs={'class': 'form-control', 'placeholder': 'Hasło'}),
    )


class CompanyForm(forms.ModelForm):
    class Meta:
        model = Company
        fields = ('nip', 'name', 'address', 'bank_account', 'is_active')

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        for field in self.fields.values():
            field.widget.attrs.setdefault('class', 'form-control')
        self.fields['is_active'].widget.attrs['class'] = 'form-check-input'


def _apply_user_widgets(form):
    for field in form.fields.values():
        field.widget.attrs.setdefault('class', 'form-control')
    form.fields['role'].widget.attrs['class'] = 'form-select'
    form.fields['company'].widget.attrs['class'] = 'form-select'
    form.fields['is_active'].widget.attrs['class'] = 'form-check-input'


def _filter_roles(form, requesting_user):
    from core.permissions import is_super_admin
    if not is_super_admin(requesting_user):
        form.fields['role'].choices = [
            (k, v) for k, v in form.fields['role'].choices
            if k != CustomUser.ROLE_SUPER_ADMIN
        ]


class UserCreateForm(UserCreationForm):
    class Meta:
        model = CustomUser
        fields = ('username', 'first_name', 'last_name', 'email', 'role', 'company', 'is_active')

    def __init__(self, *args, requesting_user=None, **kwargs):
        super().__init__(*args, **kwargs)
        _apply_user_widgets(self)
        if requesting_user is not None:
            _filter_roles(self, requesting_user)


class UserUpdateForm(UserChangeForm):
    password = None

    class Meta:
        model = CustomUser
        fields = ('username', 'first_name', 'last_name', 'email', 'role', 'company', 'is_active')

    def __init__(self, *args, requesting_user=None, **kwargs):
        super().__init__(*args, **kwargs)
        _apply_user_widgets(self)
        if requesting_user is not None:
            _filter_roles(self, requesting_user)


class LicenseForm(forms.ModelForm):
    class Meta:
        model = CompanyLicense
        fields = ('plan', 'valid_from', 'valid_until', 'is_active')
        widgets = {
            'valid_from': forms.DateInput(attrs={'type': 'date', 'class': 'form-control'}),
            'valid_until': forms.DateInput(attrs={'type': 'date', 'class': 'form-control'}),
        }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields['plan'].widget.attrs['class'] = 'form-select'
        self.fields['is_active'].widget.attrs['class'] = 'form-check-input'
