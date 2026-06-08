from django.db import IntegrityError
from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.views import APIView
from rest_framework.response import Response

from rest_framework.request import Request

from core.permissions import company_filter
from apps.outgoing.models import OutgoingInvoice, Buyer
from apps.outgoing.nip_lookup import fetch_nip_data
from apps.api.permissions import IsViewer, IsAccountant, IsApprover
from .serializers import (
    OutgoingInvoiceListSerializer, OutgoingInvoiceDetailSerializer,
    OutgoingInvoiceWriteSerializer, BuyerSerializer,
)


class OutgoingInvoiceListView(generics.ListAPIView):
    permission_classes = [IsViewer]
    serializer_class = OutgoingInvoiceListSerializer

    def get_queryset(self):
        qs = OutgoingInvoice.objects.filter(**company_filter(self.request.user))
        status_filter = self.request.query_params.get('status')
        if status_filter:
            qs = qs.filter(status=status_filter)
        return qs


class OutgoingInvoiceCreateView(generics.CreateAPIView):
    permission_classes = [IsAccountant]
    serializer_class = OutgoingInvoiceWriteSerializer

    def perform_create(self, serializer):
        company = self.request.user.company
        lic = getattr(company, 'license', None)
        if lic and not lic.can_send_outgoing_invoice():
            raise PermissionDenied('Osiągnięto limit planu dla faktur wychodzących.')
        try:
            serializer.save(company=company, created_by=self.request.user)
        except IntegrityError:
            raise ValidationError({'invoice_number': 'Faktura o tym numerze już istnieje w tej firmie.'})


class OutgoingInvoiceDetailView(generics.RetrieveAPIView):
    permission_classes = [IsViewer]
    serializer_class = OutgoingInvoiceDetailSerializer

    def get_queryset(self):
        return OutgoingInvoice.objects.filter(**company_filter(self.request.user)).prefetch_related('items')


class OutgoingInvoiceUpdateView(generics.UpdateAPIView):
    permission_classes = [IsAccountant]
    serializer_class = OutgoingInvoiceWriteSerializer

    def get_queryset(self):
        return OutgoingInvoice.objects.filter(**company_filter(self.request.user))

    def perform_update(self, serializer):
        if not serializer.instance.can_be_edited():
            raise ValidationError('Fakturę można edytować tylko w statusie Szkic.')
        serializer.save()


class OutgoingInvoiceQueueView(APIView):
    permission_classes = [IsApprover]

    def post(self, request, pk):
        inv = get_object_or_404(OutgoingInvoice, pk=pk, **company_filter(request.user))
        if not inv.can_be_queued():
            return Response({'detail': 'Faktura nie może być wysłana w bieżącym statusie.'}, status=400)
        lic = getattr(getattr(request.user, 'company', None), 'license', None)
        if lic and not lic.can_send_outgoing_invoice():
            limit = lic.outgoing_invoice_limit()
            return Response({'detail': f'Osiągnięto limit planu ({limit} faktur/miesiąc).'}, status=403)
        company = request.user.company
        if inv.payment_form == OutgoingInvoice.PAYMENT_FORM_TRANSFER and not company.bank_account:
            return Response({'detail': 'Brak numeru konta bankowego firmy.'}, status=400)
        if not inv.items.exists():
            return Response({'detail': 'Faktura nie ma żadnych pozycji.'}, status=400)
        inv.status = OutgoingInvoice.STATUS_QUEUED
        inv.error_message = ''
        inv.save(update_fields=['status', 'error_message', 'updated_at'])
        return Response(OutgoingInvoiceDetailSerializer(inv).data)


class OutgoingInvoiceBulkQueueView(APIView):
    """POST {"invoice_ids": [...]} — wysyła szkice do kolejki KSeF."""
    permission_classes = [IsApprover]

    def post(self, request):
        ids = request.data.get('invoice_ids', [])
        if not ids:
            return Response({'detail': 'Brak invoice_ids.'}, status=400)
        qs = OutgoingInvoice.objects.filter(
            pk__in=ids,
            status=OutgoingInvoice.STATUS_DRAFT,
            **company_filter(request.user),
        )
        queued, errors = [], []
        for inv in qs:
            if not inv.items.exists():
                errors.append({'id': inv.pk, 'invoice_number': inv.invoice_number, 'error': 'brak pozycji'})
                continue
            inv.status = OutgoingInvoice.STATUS_QUEUED
            inv.error_message = ''
            inv.save(update_fields=['status', 'error_message', 'updated_at'])
            queued.append(inv.pk)
        return Response({'queued': queued, 'errors': errors})


class BuyerListView(generics.ListAPIView):
    permission_classes = [IsAccountant]
    serializer_class = BuyerSerializer

    def get_queryset(self):
        return Buyer.objects.filter(**company_filter(self.request.user))


class BuyerSearchView(generics.ListAPIView):
    permission_classes = [IsAccountant]
    serializer_class = BuyerSerializer

    def get_queryset(self):
        q = self.request.query_params.get('q', '').strip()
        if len(q) < 2:
            return Buyer.objects.none()
        qs = Buyer.objects.filter(**company_filter(self.request.user))
        return (qs.filter(name__icontains=q) | qs.filter(nip__icontains=q))[:10]


class NipLookupView(APIView):
    permission_classes = [IsAccountant]

    def get(self, request: Request):
        nip = request.query_params.get('nip', '').strip().replace('-', '').replace(' ', '')
        if len(nip) != 10 or not nip.isdigit():
            return Response({'error': 'Nieprawidłowy NIP (wymagane 10 cyfr).'}, status=400)
        data = fetch_nip_data(nip)
        if data is None:
            return Response({'error': 'Nie znaleziono firmy o podanym NIP lub błąd połączenia.'}, status=404)
        return Response(data)
