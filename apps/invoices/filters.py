import django_filters
from django import forms
from .models import Invoice


class InvoiceFilter(django_filters.FilterSet):
    seller_name = django_filters.CharFilter(
        lookup_expr='icontains',
        label='Sprzedawca',
        widget=forms.TextInput(attrs={'class': 'form-control form-control-sm', 'placeholder': 'Szukaj sprzedawcy...'}),
    )
    seller_nip = django_filters.CharFilter(
        lookup_expr='icontains',
        label='NIP sprzedawcy',
        widget=forms.TextInput(attrs={'class': 'form-control form-control-sm', 'placeholder': 'NIP'}),
    )
    invoice_number = django_filters.CharFilter(
        lookup_expr='icontains',
        label='Numer faktury',
        widget=forms.TextInput(attrs={'class': 'form-control form-control-sm', 'placeholder': 'Nr faktury'}),
    )
    status = django_filters.MultipleChoiceFilter(
        choices=Invoice.STATUS_CHOICES,
        label='Status',
        widget=forms.CheckboxSelectMultiple,
    )
    issue_date_from = django_filters.DateFilter(
        field_name='issue_date',
        lookup_expr='gte',
        label='Data wystawienia od',
        widget=forms.DateInput(attrs={'class': 'form-control form-control-sm', 'type': 'date'}),
    )
    issue_date_to = django_filters.DateFilter(
        field_name='issue_date',
        lookup_expr='lte',
        label='Data wystawienia do',
        widget=forms.DateInput(attrs={'class': 'form-control form-control-sm', 'type': 'date'}),
    )
    amount_gross_min = django_filters.NumberFilter(
        field_name='amount_gross',
        lookup_expr='gte',
        label='Kwota brutto min',
        widget=forms.NumberInput(attrs={'class': 'form-control form-control-sm', 'placeholder': 'Min'}),
    )
    amount_gross_max = django_filters.NumberFilter(
        field_name='amount_gross',
        lookup_expr='lte',
        label='Kwota brutto max',
        widget=forms.NumberInput(attrs={'class': 'form-control form-control-sm', 'placeholder': 'Max'}),
    )

    class Meta:
        model = Invoice
        fields = []
