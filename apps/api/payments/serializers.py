from rest_framework import serializers
from apps.payments.models import PaymentFile
from apps.accounts.models import CompanyBankAccount
from apps.api.invoices.serializers import InvoiceListSerializer


class PaymentFileSerializer(serializers.ModelSerializer):
    class Meta:
        model = PaymentFile
        fields = ['id', 'format', 'file_name', 'total_amount', 'invoice_count', 'debit_account', 'created_at']


class AcceptedInvoiceForPaymentSerializer(InvoiceListSerializer):
    pass


class PaymentFileCreateSerializer(serializers.Serializer):
    invoice_ids = serializers.ListField(child=serializers.IntegerField(), min_length=1)
    format = serializers.ChoiceField(choices=PaymentFile.FORMAT_CHOICES, default=PaymentFile.FORMAT_ERSTE)
    debit_account = serializers.CharField(required=False, allow_blank=True)


class CompanyBankAccountSerializer(serializers.ModelSerializer):
    class Meta:
        model = CompanyBankAccount
        fields = ['id', 'account_number', 'label', 'bank_name', 'bank_key', 'is_default']
        read_only_fields = ['bank_name', 'bank_key']
