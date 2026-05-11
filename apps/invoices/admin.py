from django.contrib import admin
from .models import Invoice, InvoiceStatusLog


class InvoiceStatusLogInline(admin.TabularInline):
    model = InvoiceStatusLog
    extra = 0
    readonly_fields = ('old_status', 'new_status', 'changed_by', 'changed_at', 'note')
    can_delete = False


@admin.register(Invoice)
class InvoiceAdmin(admin.ModelAdmin):
    list_display = ('invoice_number', 'seller_name', 'seller_nip', 'issue_date',
                    'amount_gross', 'currency', 'status')
    list_filter = ('status', 'currency', 'is_split_payment', 'issue_date')
    search_fields = ('invoice_number', 'seller_name', 'seller_nip', 'ksef_reference_number')
    readonly_fields = ('synced_at', 'updated_at', 'ksef_reference_number')
    inlines = [InvoiceStatusLogInline]
    date_hierarchy = 'issue_date'
