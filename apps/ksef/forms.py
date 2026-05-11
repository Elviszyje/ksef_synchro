from django import forms
from .models import KSeFConfig, NotificationConfig

_TIME_WIDGET = {'class': 'form-control form-control-sm', 'type': 'time'}


class KSeFConfigForm(forms.ModelForm):
    token_plain = forms.CharField(
        label='Token API KSeF',
        required=False,
        widget=forms.PasswordInput(
            attrs={'class': 'form-control', 'placeholder': 'Zostaw puste aby nie zmieniać'},
            render_value=False,
        ),
        help_text='Podaj token tylko przy pierwszym zapisie lub gdy chcesz go zmienić.',
    )

    class Meta:
        model = KSeFConfig
        fields = ('nip', 'environment', 'sync_interval_hours',
                  'sync_enabled', 'sync_window_start', 'sync_window_end')
        widgets = {
            'nip': forms.TextInput(attrs={'class': 'form-control', 'placeholder': '0000000000'}),
            'environment': forms.Select(attrs={'class': 'form-select'}),
            'sync_interval_hours': forms.NumberInput(attrs={'class': 'form-control', 'min': 1, 'max': 24}),
            'sync_enabled': forms.CheckboxInput(attrs={'class': 'form-check-input', 'role': 'switch'}),
            'sync_window_start': forms.TimeInput(attrs=_TIME_WIDGET),
            'sync_window_end': forms.TimeInput(attrs=_TIME_WIDGET),
        }

    def clean(self):
        cleaned = super().clean()
        start = cleaned.get('sync_window_start')
        end = cleaned.get('sync_window_end')
        if bool(start) != bool(end):
            raise forms.ValidationError('Podaj obie godziny okna synchronizacji lub żadnej.')
        return cleaned

    def save(self, commit=True):
        instance = super().save(commit=False)
        token_plain = self.cleaned_data.get('token_plain', '').strip()
        if token_plain:
            instance.set_token(token_plain)
        if commit:
            instance.save()
        return instance


class NotificationConfigForm(forms.ModelForm):
    bot_token_plain = forms.CharField(
        label='Token bota Telegram',
        required=False,
        widget=forms.PasswordInput(
            attrs={'class': 'form-control form-control-sm',
                   'placeholder': 'Zostaw puste aby nie zmieniać'},
            render_value=False,
        ),
        help_text='Utwórz bota przez @BotFather i wklej token. Zmień tylko gdy chcesz zaktualizować.',
    )

    class Meta:
        model = NotificationConfig
        fields = ('enabled', 'telegram_chat_id',
                  'quiet_from', 'quiet_to', 'digest_time')
        widgets = {
            'enabled': forms.CheckboxInput(attrs={'class': 'form-check-input', 'role': 'switch'}),
            'telegram_chat_id': forms.TextInput(
                attrs={'class': 'form-control form-control-sm', 'placeholder': '-100xxxxxxxxxx'}
            ),
            'quiet_from': forms.TimeInput(attrs=_TIME_WIDGET),
            'quiet_to': forms.TimeInput(attrs=_TIME_WIDGET),
            'digest_time': forms.TimeInput(attrs=_TIME_WIDGET),
        }

    def save(self, commit=True):
        instance = super().save(commit=False)
        token = self.cleaned_data.get('bot_token_plain', '').strip()
        if token:
            instance.set_bot_token(token)
        if commit:
            instance.save()
        return instance
