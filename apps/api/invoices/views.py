from datetime import date
from decimal import Decimal

from django.shortcuts import get_object_or_404
from django.db.models import Sum, Count
from django.db.models.functions import TruncMonth
from rest_framework import generics
from rest_framework.views import APIView
from rest_framework.response import Response

from core.permissions import company_filter, has_min_role
from core.audit import log_event
from core.models import AuditLog
from apps.invoices.models import Invoice
from apps.invoices.views import get_allowed_transitions, _apply_status_change
from apps.api.permissions import IsViewer, IsAccountant, BelongsToCompany
from .serializers import (
    InvoiceListSerializer, InvoiceDetailSerializer,
    InvoiceStatusChangeSerializer, InvoiceBulkStatusSerializer,
    InvoiceNoteSerializer,
)
from .filters import InvoiceAPIFilter

try:
    from dateutil.relativedelta import relativedelta
except ImportError:
    class relativedelta:
        def __init__(self, months=0):
            self.months = months


class InvoiceListView(generics.ListAPIView):
    permission_classes = [IsViewer]
    serializer_class = InvoiceListSerializer
    filterset_class = InvoiceAPIFilter
    ordering_fields = ['issue_date', 'amount_gross', 'payment_due_date', 'seller_name']
    ordering = ['-issue_date']

    def get_queryset(self):
        return Invoice.objects.filter(**company_filter(self.request.user)).select_related('updated_by')


class InvoiceDetailView(generics.RetrieveAPIView):
    permission_classes = [IsViewer, BelongsToCompany]
    serializer_class = InvoiceDetailSerializer

    def get_queryset(self):
        return (
            Invoice.objects
            .filter(**company_filter(self.request.user))
            .prefetch_related('status_logs__changed_by')
        )


class InvoiceStatusChangeView(APIView):
    permission_classes = [IsAccountant]

    def post(self, request, pk):
        invoice = get_object_or_404(Invoice, pk=pk, **company_filter(request.user))
        serializer = InvoiceStatusChangeSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        new_status = serializer.validated_data['status']
        note = serializer.validated_data['note']

        allowed = get_allowed_transitions(invoice)
        if new_status not in allowed:
            return Response(
                {'detail': f'Niedozwolona zmiana statusu: {invoice.status} → {new_status}'},
                status=400,
            )

        if new_status == Invoice.STATUS_SENT_FOR_PAYMENT and not has_min_role(request.user, 'approver'):
            return Response({'detail': 'Brak uprawnień do przekazania faktury do opłacenia.'}, status=403)

        _apply_status_change(invoice, new_status, request.user, note)
        return Response(InvoiceDetailSerializer(invoice).data)


class InvoiceBulkStatusView(APIView):
    permission_classes = [IsAccountant]

    def post(self, request):
        serializer = InvoiceBulkStatusSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        ids = serializer.validated_data['ids']
        new_status = serializer.validated_data['status']

        invoices = Invoice.objects.filter(pk__in=ids, **company_filter(request.user))
        changed = 0
        for invoice in invoices:
            allowed = get_allowed_transitions(invoice)
            if new_status not in allowed:
                continue
            if new_status == Invoice.STATUS_SENT_FOR_PAYMENT and not has_min_role(request.user, 'approver'):
                continue
            _apply_status_change(invoice, new_status, request.user, 'Zmiana zbiorcza z aplikacji mobilnej.')
            changed += 1

        return Response({'changed': changed})


class InvoiceNoteUpdateView(APIView):
    permission_classes = [IsAccountant]

    def patch(self, request, pk):
        invoice = get_object_or_404(Invoice, pk=pk, **company_filter(request.user))
        serializer = InvoiceNoteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        invoice.notes = serializer.validated_data['notes']
        invoice.updated_by = request.user
        invoice.save(update_fields=['notes', 'updated_by', 'updated_at'])
        log_event(request.user, AuditLog.ACTION_INVOICE_NOTE, entity=invoice, request=request)
        return Response({'detail': 'Notatka zapisana.'})


class InvoiceDashboardView(APIView):
    permission_classes = [IsViewer]

    def get(self, request):
        today = date.today()
        date_from = today.replace(day=1) - relativedelta(months=11)

        monthly_qs = (
            Invoice.objects
            .filter(issue_date__gte=date_from, **company_filter(request.user))
            .annotate(month=TruncMonth('issue_date'))
            .values('month')
            .annotate(total_gross=Sum('amount_gross'), total_net=Sum('amount_net'), count=Count('id'))
            .order_by('month')
        )

        result = []
        for row in monthly_qs:
            result.append({
                'month': row['month'].strftime('%Y-%m'),
                'total_gross': str(row['total_gross'] or Decimal('0')),
                'total_net': str(row['total_net'] or Decimal('0')),
                'count': row['count'],
            })
        return Response(result)
