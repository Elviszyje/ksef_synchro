from django import forms
from django.forms import inlineformset_factory
from django.contrib.auth.forms import AuthenticationForm, UserCreationForm, UserChangeForm
from .models import CustomUser, Company, CompanyLicense, CompanyBankAccount


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
        fields = ('nip', 'name', 'address', 'is_active')

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        for field in self.fields.values():
            field.widget.attrs.setdefault('class', 'form-control')
        self.fields['is_active'].widget.attrs['class'] = 'form-check-input'


class CompanyBankAccountForm(forms.ModelForm):
    class Meta:
        model = CompanyBankAccount
        fields = ('account_number', 'label', 'is_default')

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields['account_number'].widget.attrs.update({
            'class': 'form-control form-control-sm font-monospace',
            'placeholder': '00 0000 0000 0000 0000 0000 0000',
            'maxlength': '34',
        })
        self.fields['label'].widget.attrs.update({
            'class': 'form-control form-control-sm',
            'placeholder': 'np. Rachunek bieżący PLN',
        })
        self.fields['is_default'].widget.attrs['class'] = 'form-check-input'


CompanyBankAccountFormSet = inlineformset_factory(
    Company,
    CompanyBankAccount,
    form=CompanyBankAccountForm,
    extra=1,
    can_delete=True,
)


def _apply_user_widgets(form):
    for field in form.fields.values():
        field.widget.attrs.setdefault('class', 'form-control')
    form.fields['role'].widget.attrs['class'] = 'form-select'
    form.fields['company'].widget.attrs['class'] = 'form-select'
    form.fields['is_active'].widget.attrs['class'] = 'form-check-input'


def _restrict_for_user(form, requesting_user):
    from core.permissions import is_super_admin
    # Filtr ról — non-superadmin nie może nadać roli super_admin
    if not is_super_admin(requesting_user):
        form.fields['role'].choices = [
            (k, v) for k, v in form.fields['role'].choices
            if k != CustomUser.ROLE_SUPER_ADMIN
        ]
    # Filtr firm — non-superuser widzi i może wybrać tylko własną firmę
    if not requesting_user.is_superuser:
        own = requesting_user.company
        form.fields['company'].queryset = Company.objects.filter(pk=own.pk) if own else Company.objects.none()
        form.fields['company'].widget = forms.HiddenInput()
        form.fields['company'].initial = own


class UserCreateForm(UserCreationForm):
    class Meta:
        model = CustomUser
        fields = ('username', 'first_name', 'last_name', 'email', 'role', 'company', 'is_active')

    def __init__(self, *args, requesting_user=None, **kwargs):
        super().__init__(*args, **kwargs)
        _apply_user_widgets(self)
        if requesting_user is not None:
            _restrict_for_user(self, requesting_user)


class UserUpdateForm(UserChangeForm):
    password = None

    class Meta:
        model = CustomUser
        fields = ('username', 'first_name', 'last_name', 'email', 'role', 'company', 'is_active')

    def __init__(self, *args, requesting_user=None, **kwargs):
        super().__init__(*args, **kwargs)
        _apply_user_widgets(self)
        if requesting_user is not None:
            _restrict_for_user(self, requesting_user)


class RegisterForm(forms.Form):
    nip = forms.CharField(
        max_length=10,
        label='NIP firmy',
        widget=forms.TextInput(attrs={'class': 'form-control', 'placeholder': '0000000000'}),
    )
    company_name = forms.CharField(
        max_length=255,
        label='Nazwa firmy',
        widget=forms.TextInput(attrs={'class': 'form-control', 'placeholder': 'Jan Kowalski Usługi IT'}),
    )
    first_name = forms.CharField(
        max_length=150,
        label='Imię',
        widget=forms.TextInput(attrs={'class': 'form-control'}),
    )
    last_name = forms.CharField(
        max_length=150,
        label='Nazwisko',
        widget=forms.TextInput(attrs={'class': 'form-control'}),
    )
    email = forms.EmailField(
        label='E-mail',
        widget=forms.EmailInput(attrs={'class': 'form-control'}),
    )
    username = forms.CharField(
        max_length=150,
        label='Login',
        widget=forms.TextInput(attrs={'class': 'form-control', 'placeholder': 'jkowalski'}),
    )
    password1 = forms.CharField(
        label='Hasło',
        widget=forms.PasswordInput(attrs={'class': 'form-control'}),
    )
    password2 = forms.CharField(
        label='Powtórz hasło',
        widget=forms.PasswordInput(attrs={'class': 'form-control'}),
    )

    def clean_nip(self):
        nip = self.cleaned_data.get('nip', '').strip().replace('-', '').replace(' ', '')
        if not nip.isdigit() or len(nip) != 10:
            raise forms.ValidationError('NIP musi składać się z dokładnie 10 cyfr.')
        if Company.objects.filter(nip=nip).exists():
            raise forms.ValidationError('Firma z tym NIP jest już zarejestrowana.')
        return nip

    def clean_username(self):
        username = self.cleaned_data.get('username', '').strip()
        if CustomUser.objects.filter(username=username).exists():
            raise forms.ValidationError('Ta nazwa użytkownika jest już zajęta.')
        return username

    def clean_email(self):
        email = self.cleaned_data.get('email', '').strip().lower()
        if CustomUser.objects.filter(email__iexact=email).exists():
            raise forms.ValidationError('Ten adres e-mail jest już zarejestrowany.')
        return email

    def clean(self):
        cleaned_data = super().clean()
        p1 = cleaned_data.get('password1')
        p2 = cleaned_data.get('password2')
        if p1 and len(p1) < 8:
            self.add_error('password1', 'Hasło musi mieć co najmniej 8 znaków.')
        if p1 and p2 and p1 != p2:
            self.add_error('password2', 'Hasła nie są identyczne.')
        return cleaned_data


class SetPasswordForm(forms.Form):
    password1 = forms.CharField(
        label='Nowe hasło',
        widget=forms.PasswordInput(attrs={'class': 'form-control', 'autofocus': True}),
    )
    password2 = forms.CharField(
        label='Powtórz hasło',
        widget=forms.PasswordInput(attrs={'class': 'form-control'}),
    )

    def clean(self):
        cd = super().clean()
        p1, p2 = cd.get('password1'), cd.get('password2')
        if p1 and len(p1) < 8:
            self.add_error('password1', 'Hasło musi mieć co najmniej 8 znaków.')
        if p1 and p2 and p1 != p2:
            self.add_error('password2', 'Hasła nie są identyczne.')
        return cd


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
