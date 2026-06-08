from rest_framework import serializers
from apps.bank_statements.models import BankStatement, BankTransaction, TransactionMatch
from apps.api.invoices.serializers import InvoiceListSerializer


class TransactionMatchSerializer(serializers.ModelSerializer):
    invoice = InvoiceListSerializer(read_only=True)

    class Meta:
        model = TransactionMatch
        fields = ['id', 'invoice', 'match_type', 'confidence', 'is_confirmed']


class BankTransactionSerializer(serializers.ModelSerializer):
    matches = TransactionMatchSerializer(many=True, read_only=True)

    class Meta:
        model = BankTransaction
        fields = [
            'id', 'transaction_date', 'value_date', 'amount', 'currency',
            'is_debit', 'description', 'counterparty', 'reference', 'is_matched', 'matches',
        ]


class BankStatementSerializer(serializers.ModelSerializer):
    transaction_count = serializers.SerializerMethodField()

    class Meta:
        model = BankStatement
        fields = [
            'id', 'file_name', 'account_number', 'statement_date',
            'status', 'file_format', 'uploaded_at', 'transaction_count',
        ]

    def get_transaction_count(self, obj):
        return obj.transactions.count()


class BankStatementDetailSerializer(BankStatementSerializer):
    transactions = BankTransactionSerializer(many=True, read_only=True)

    class Meta(BankStatementSerializer.Meta):
        fields = BankStatementSerializer.Meta.fields + ['transactions']
