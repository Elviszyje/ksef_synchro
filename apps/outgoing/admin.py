from django.contrib import admin
from .models import OutgoingInvoice, InvoiceItem


class InvoiceItemInline(admin.TabularInline):
    model = InvoiceItem
    extra = 0
    fields = ['lp', 'name', 'unit', 'quantity', 'unit_price_net', 'vat_rate', 'amount_net', 'amount_vat', 'amount_gross']
    readonly_fields = ['amount_net', 'amount_vat', 'amount_gross']


@admin.register(OutgoingInvoice)
class OutgoingInvoiceAdmin(admin.ModelAdmin):
    list_display = ['invoice_number', 'buyer_name', 'buyer_nip', 'status', 'issue_date', 'created_at', 'company']
    list_filter = ['status', 'company', 'issue_date']
    search_fields = ['invoice_number', 'buyer_name', 'buyer_nip', 'ksef_reference_number']
    readonly_fields = ['created_at', 'updated_at', 'generated_xml', 'upo_xml', 'ksef_submission_reference', 'ksef_reference_number']
    inlines = [InvoiceItemInline]
    date_hierarchy = 'issue_date'
