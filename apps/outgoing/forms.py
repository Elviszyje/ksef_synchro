from django import forms
from django.forms import inlineformset_factory

from .models import OutgoingInvoice, InvoiceItem, Buyer, CatalogItem


class OutgoingInvoiceForm(forms.ModelForm):
    class Meta:
        model = OutgoingInvoice
        fields = [
            'invoice_number', 'issue_date', 'delivery_date', 'payment_due_date',
            'payment_form', 'currency',
            'buyer_nip', 'buyer_name', 'buyer_address',
            'notes',
            'vat_exemption_type', 'vat_exemption_basis',
        ]
        widgets = {
            'issue_date': forms.DateInput(attrs={'type': 'date'}, format='%Y-%m-%d'),
            'delivery_date': forms.DateInput(attrs={'type': 'date'}, format='%Y-%m-%d'),
            'payment_due_date': forms.DateInput(attrs={'type': 'date'}, format='%Y-%m-%d'),
            'buyer_address': forms.Textarea(attrs={'rows': 3}),
            'notes': forms.Textarea(attrs={'rows': 2}),
            'vat_exemption_basis': forms.TextInput(attrs={'list': 'exemption-basis-suggestions',
                                                          'placeholder': 'np. art. 43 ust. 1 pkt 29 lit. a ustawy o VAT'}),
        }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields['vat_exemption_type'].required = False
        for field in self.fields.values():
            if not isinstance(field.widget, (forms.Textarea, forms.Select, forms.CheckboxInput)):
                field.widget.attrs.setdefault('class', 'form-control')
            elif isinstance(field.widget, forms.Select):
                field.widget.attrs.setdefault('class', 'form-select')
            elif isinstance(field.widget, forms.Textarea):
                field.widget.attrs.setdefault('class', 'form-control')

    def validate_exemption(self, formset) -> bool:
        """
        Podstawa zwolnienia jest wymagana, gdy którakolwiek (nieusunięta) pozycja ma stawkę ZW.
        Wywoływane po walidacji formularza i formsetu; zwraca False i dodaje błąd, gdy brakuje.
        """
        has_exempt = any(
            f.cleaned_data.get('vat_rate') == 'zw'
            for f in formset.forms
            if f.cleaned_data and not f.cleaned_data.get('DELETE')
        )
        if has_exempt and not self.cleaned_data.get('vat_exemption_basis', '').strip():
            self.add_error('vat_exemption_basis',
                           'Pozycje ze stawką ZW wymagają podania podstawy prawnej zwolnienia z VAT.')
            return False
        if not self.cleaned_data.get('vat_exemption_type'):
            self.cleaned_data['vat_exemption_type'] = OutgoingInvoice.EXEMPTION_ACT
            self.instance.vat_exemption_type = OutgoingInvoice.EXEMPTION_ACT
        return True


class CatalogItemForm(forms.ModelForm):
    class Meta:
        model = CatalogItem
        fields = ('name', 'unit', 'unit_price_net', 'vat_rate')
        widgets = {
            'name': forms.TextInput(attrs={'class': 'form-control'}),
            'unit': forms.TextInput(attrs={'class': 'form-control'}),
            'unit_price_net': forms.NumberInput(attrs={'class': 'form-control', 'step': '0.01', 'min': '0'}),
            'vat_rate': forms.Select(attrs={'class': 'form-select'}),
        }


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
            'name': forms.TextInput(attrs={'class': 'form-control', 'placeholder': 'Nazwa towaru/usługi',
                                           'list': 'catalog-names', 'autocomplete': 'off'}),
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
