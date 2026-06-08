from rest_framework import serializers
from apps.outgoing.models import OutgoingInvoice, InvoiceItem, Buyer


class BuyerSerializer(serializers.ModelSerializer):
    class Meta:
        model = Buyer
        fields = ['id', 'nip', 'name', 'address', 'email', 'phone', 'notes']


class InvoiceItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = InvoiceItem
        fields = [
            'id', 'lp', 'name', 'unit', 'quantity', 'unit_price_net', 'vat_rate',
            'amount_net', 'amount_vat', 'amount_gross',
        ]
        read_only_fields = ['amount_net', 'amount_vat', 'amount_gross']


class OutgoingInvoiceListSerializer(serializers.ModelSerializer):
    status_display = serializers.CharField(source='get_status_display', read_only=True)
    amount_gross = serializers.SerializerMethodField()

    class Meta:
        model = OutgoingInvoice
        fields = [
            'id', 'invoice_number', 'issue_date', 'payment_due_date',
            'buyer_name', 'buyer_nip', 'amount_gross', 'currency',
            'status', 'status_display', 'created_at',
        ]

    def get_amount_gross(self, obj):
        return str(obj.amount_gross)


class OutgoingInvoiceDetailSerializer(OutgoingInvoiceListSerializer):
    items = InvoiceItemSerializer(many=True, read_only=True)
    amount_net = serializers.SerializerMethodField()
    amount_vat = serializers.SerializerMethodField()
    can_be_edited = serializers.SerializerMethodField()
    can_be_queued = serializers.SerializerMethodField()

    class Meta(OutgoingInvoiceListSerializer.Meta):
        fields = OutgoingInvoiceListSerializer.Meta.fields + [
            'delivery_date', 'payment_form', 'buyer_address',
            'notes', 'ksef_reference_number', 'error_message',
            'amount_net', 'amount_vat', 'items',
            'can_be_edited', 'can_be_queued', 'updated_at',
        ]

    def get_amount_net(self, obj):
        return str(obj.amount_net)

    def get_amount_vat(self, obj):
        return str(obj.amount_vat)

    def get_can_be_edited(self, obj):
        return obj.can_be_edited()

    def get_can_be_queued(self, obj):
        return obj.can_be_queued()


class OutgoingInvoiceWriteSerializer(serializers.ModelSerializer):
    items = InvoiceItemSerializer(many=True)

    class Meta:
        model = OutgoingInvoice
        fields = [
            'invoice_number', 'issue_date', 'delivery_date', 'payment_due_date',
            'payment_form', 'currency',
            'buyer_nip', 'buyer_name', 'buyer_address', 'notes', 'items',
        ]

    def create(self, validated_data):
        items_data = validated_data.pop('items')
        invoice = OutgoingInvoice.objects.create(**validated_data)
        for i, item_data in enumerate(items_data, start=1):
            item_data.setdefault('lp', i)
            InvoiceItem.objects.create(invoice=invoice, **item_data)
        return invoice

    def update(self, instance, validated_data):
        items_data = validated_data.pop('items', None)
        for attr, val in validated_data.items():
            setattr(instance, attr, val)
        instance.save()
        if items_data is not None:
            instance.items.all().delete()
            for i, item_data in enumerate(items_data, start=1):
                item_data.setdefault('lp', i)
                InvoiceItem.objects.create(invoice=instance, **item_data)
        return instance
