from django.contrib import admin
from .models import PaymentFile, PaymentFileItem


class PaymentFileItemInline(admin.TabularInline):
    model = PaymentFileItem
    extra = 0
    readonly_fields = ('invoice', 'amount', 'line_number')
    can_delete = False


@admin.register(PaymentFile)
class PaymentFileAdmin(admin.ModelAdmin):
    list_display = ('file_name', 'format', 'invoice_count', 'total_amount', 'created_by', 'created_at')
    list_filter = ('format', 'created_at')
    readonly_fields = ('file_content', 'created_at', 'created_by')
    inlines = [PaymentFileItemInline]
