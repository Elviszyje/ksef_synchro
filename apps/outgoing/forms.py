from django import forms
from django.forms import inlineformset_factory

from .models import OutgoingInvoice, InvoiceItem, Buyer


class OutgoingInvoiceForm(forms.ModelForm):
    class Meta:
        model = OutgoingInvoice
        fields = [
            'invoice_number', 'issue_date', 'delivery_date', 'payment_due_date',
            'payment_form', 'currency',
            'buyer_nip', 'buyer_name', 'buyer_address',
            'notes',
        ]
        widgets = {
            'issue_date': forms.DateInput(attrs={'type': 'date'}, format='%Y-%m-%d'),
            'delivery_date': forms.DateInput(attrs={'type': 'date'}, format='%Y-%m-%d'),
            'payment_due_date': forms.DateInput(attrs={'type': 'date'}, format='%Y-%m-%d'),
            'buyer_address': forms.Textarea(attrs={'rows': 3}),
            'notes': forms.Textarea(attrs={'rows': 2}),
        }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        for field in self.fields.values():
            if not isinstance(field.widget, (forms.Textarea, forms.Select, forms.CheckboxInput)):
                field.widget.attrs.setdefault('class', 'form-control')
            elif isinstance(field.widget, forms.Select):
                field.widget.attrs.setdefault('class', 'form-select')
            elif isinstance(field.widget, forms.Textarea):
                field.widget.attrs.setdefault('class', 'form-control')


class BuyerForm(forms.ModelForm):
    class Meta:
        model = Buyer
        fields = ('nip', 'name', 'address', 'email', 'phone', 'notes')
        widgets = {
            'address': forms.Textarea(attrs={'rows': 3, 'class': 'form-control'}),
            'notes': forms.Textarea(attrs={'rows': 2, 'class': 'form-control'}),
        }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        for name, field in self.fields.items():
            if not isinstance(field.widget, (forms.Textarea,)):
                field.widget.attrs.setdefault('class', 'form-control')


class InvoiceItemForm(forms.ModelForm):
    lp = forms.IntegerField(required=False, widget=forms.HiddenInput())

    class Meta:
        model = InvoiceItem
        fields = ['lp', 'name', 'unit', 'quantity', 'unit_price_net', 'vat_rate']
        widgets = {
            'lp': forms.HiddenInput(),
            'name': forms.TextInput(attrs={'class': 'form-control', 'placeholder': 'Nazwa towaru/usługi'}),
            'unit': forms.TextInput(attrs={'class': 'form-control', 'placeholder': 'szt.'}),
            'quantity': forms.NumberInput(attrs={'class': 'form-control', 'step': '0.001', 'min': '0'}),
            'unit_price_net': forms.NumberInput(attrs={'class': 'form-control', 'step': '0.01', 'min': '0'}),
            'vat_rate': forms.Select(attrs={'class': 'form-select'}),
        }


InvoiceItemFormSet = inlineformset_factory(
    OutgoingInvoice,
    InvoiceItem,
    form=InvoiceItemForm,
    extra=0,
    can_delete=True,
    min_num=1,
    validate_min=True,
)
