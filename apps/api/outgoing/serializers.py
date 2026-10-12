from rest_framework import serializers
from apps.outgoing.models import OutgoingInvoice, InvoiceItem, Buyer, CatalogItem


class BuyerSerializer(serializers.ModelSerializer):
    class Meta:
        model = Buyer
        fields = ['id', 'nip', 'name', 'address', 'email', 'phone', 'notes']


class CatalogItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = CatalogItem
        fields = ['id', 'name', 'unit', 'unit_price_net', 'vat_rate', 'use_count', 'last_used_at']


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
            'vat_exemption_type', 'vat_exemption_basis',
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
            'vat_exemption_type', 'vat_exemption_basis',
        ]

    def validate(self, attrs):
        items = attrs.get('items')
        if items is None and self.instance is not None:
            items = [{'vat_rate': i.vat_rate} for i in self.instance.items.all()]
        basis = attrs.get('vat_exemption_basis', getattr(self.instance, 'vat_exemption_basis', '')) or ''
        if any(i.get('vat_rate') == 'zw' for i in items or []) and not basis.strip():
            raise serializers.ValidationError(
                {'vat_exemption_basis': 'Pozycje ze stawką ZW wymagają podania podstawy prawnej zwolnienia z VAT.'})
        return attrs

    def create(self, validated_data):
        items_data = validated_data.pop('items')
        invoice = OutgoingInvoice.objects.create(**validated_data)
        for i, item_data in enumerate(items_data, start=1):
            item_data.setdefault('lp', i)
            InvoiceItem.objects.create(invoice=invoice, **item_data)
        CatalogItem.remember(invoice.company, invoice.items.all())
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
            CatalogItem.remember(instance.company, instance.items.all())
        return instance
