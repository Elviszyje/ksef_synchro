import django_filters
from apps.invoices.models import Invoice


class InvoiceAPIFilter(django_filters.FilterSet):
    seller_name = django_filters.CharFilter(lookup_expr='icontains')
    seller_nip = django_filters.CharFilter(lookup_expr='icontains')
    invoice_number = django_filters.CharFilter(lookup_expr='icontains')
    status = django_filters.MultipleChoiceFilter(choices=Invoice.STATUS_CHOICES)
    issue_date_from = django_filters.DateFilter(field_name='issue_date', lookup_expr='gte')
    issue_date_to = django_filters.DateFilter(field_name='issue_date', lookup_expr='lte')
    amount_gross_min = django_filters.NumberFilter(field_name='amount_gross', lookup_expr='gte')
    amount_gross_max = django_filters.NumberFilter(field_name='amount_gross', lookup_expr='lte')

    class Meta:
        model = Invoice
        fields = []
