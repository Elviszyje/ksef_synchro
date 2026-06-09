from rest_framework import serializers
from apps.invoices.models import Invoice, InvoiceStatusLog


class InvoiceStatusLogSerializer(serializers.ModelSerializer):
    changed_by_username = serializers.CharField(source='changed_by.username', read_only=True, default=None)

    class Meta:
        model = InvoiceStatusLog
        fields = ['id', 'old_status', 'new_status', 'changed_by_username', 'changed_at', 'note']


class InvoiceListSerializer(serializers.ModelSerializer):
    status_display = serializers.CharField(source='get_status_display', read_only=True)
    is_overdue = serializers.SerializerMethodField()

    class Meta:
        model = Invoice
        fields = [
            'id', 'invoice_number', 'ksef_reference_number',
            'seller_name', 'seller_nip',
            'amount_net', 'amount_vat', 'amount_gross', 'currency',
            'is_split_payment', 'issue_date', 'payment_due_date',
            'bank_account_number', 'payment_title',
            'status', 'status_display', 'is_overdue',
            'notes', 'invoice_type',
            'synced_at', 'updated_at',
        ]

    def get_is_overdue(self, obj):
        return obj.is_overdue()


class InvoiceDetailSerializer(InvoiceListSerializer):
    status_logs = InvoiceStatusLogSerializer(many=True, read_only=True)
    allowed_transitions = serializers.SerializerMethodField()

    class Meta(InvoiceListSerializer.Meta):
        fields = InvoiceListSerializer.Meta.fields + [
            'seller_address', 'buyer_nip',
            'vat_amount_split', 'payment_date', 'payment_form',
            'description', 'status_logs', 'allowed_transitions',
        ]

    def get_allowed_transitions(self, obj):
        from apps.invoices.views import get_allowed_transitions
        return get_allowed_transitions(obj)


class InvoiceStatusChangeSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=Invoice.STATUS_CHOICES)
    note = serializers.CharField(required=False, allow_blank=True, default='')


class InvoiceBulkStatusSerializer(serializers.Serializer):
    ids = serializers.ListField(child=serializers.IntegerField(), min_length=1)
    status = serializers.ChoiceField(choices=Invoice.STATUS_CHOICES)


class InvoiceNoteSerializer(serializers.Serializer):
    notes = serializers.CharField(allow_blank=True)
