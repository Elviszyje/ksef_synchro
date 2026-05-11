from django import forms
from django.contrib.auth.forms import AuthenticationForm, UserCreationForm, UserChangeForm
from .models import CustomUser


class LoginForm(AuthenticationForm):
    username = forms.CharField(
        label='Login',
        widget=forms.TextInput(attrs={'class': 'form-control', 'autofocus': True, 'placeholder': 'Login'}),
    )
    password = forms.CharField(
        label='Hasło',
        widget=forms.PasswordInput(attrs={'class': 'form-control', 'placeholder': 'Hasło'}),
    )


class UserCreateForm(UserCreationForm):
    class Meta:
        model = CustomUser
        fields = ('username', 'first_name', 'last_name', 'email', 'role', 'is_active')

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        for field in self.fields.values():
            field.widget.attrs.setdefault('class', 'form-control')
        self.fields['role'].widget.attrs['class'] = 'form-select'
        self.fields['is_active'].widget.attrs['class'] = 'form-check-input'


class UserUpdateForm(UserChangeForm):
    password = None

    class Meta:
        model = CustomUser
        fields = ('username', 'first_name', 'last_name', 'email', 'role', 'is_active')

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        for field in self.fields.values():
            field.widget.attrs.setdefault('class', 'form-control')
        self.fields['role'].widget.attrs['class'] = 'form-select'
        self.fields['is_active'].widget.attrs['class'] = 'form-check-input'
