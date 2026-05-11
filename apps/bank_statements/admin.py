from django.contrib import admin
from .models import BankStatement, BankTransaction, TransactionMatch


class BankTransactionInline(admin.TabularInline):
    model = BankTransaction
    extra = 0
    readonly_fields = ('transaction_date', 'amount', 'is_debit', 'description', 'is_matched')
    can_delete = False


@admin.register(BankStatement)
class BankStatementAdmin(admin.ModelAdmin):
    list_display = ('file_name', 'account_number', 'statement_date', 'status', 'uploaded_by', 'uploaded_at')
    list_filter = ('status',)
    readonly_fields = ('uploaded_at', 'confirmed_at', 'raw_content')
    inlines = [BankTransactionInline]
