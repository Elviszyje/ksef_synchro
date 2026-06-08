from datetime import date

from django.conf import settings
from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework.views import APIView
from rest_framework.response import Response

from core.permissions import company_filter
from core.audit import log_event
from core.models import AuditLog
from apps.invoices.models import Invoice, InvoiceStatusLog
from apps.payments.models import PaymentFile, PaymentFileItem
from apps.payments.views import _build_generator, _get_default_account
from apps.payments.bank_detection import detect_bank_key, get_file_suffix
from apps.accounts.models import CompanyBankAccount
from apps.api.permissions import IsApprover, IsAccountant
from .serializers import (
    PaymentFileSerializer, AcceptedInvoiceForPaymentSerializer,
    PaymentFileCreateSerializer, CompanyBankAccountSerializer,
)


class AcceptedInvoicesForPaymentView(generics.ListAPIView):
    permission_classes = [IsApprover]
    serializer_class = AcceptedInvoiceForPaymentSerializer

    def get_queryset(self):
        return Invoice.objects.filter(
            status=Invoice.STATUS_ACCEPTED,
            **company_filter(self.request.user),
        ).exclude(bank_account_number='').order_by('-issue_date')


class PaymentFileListView(generics.ListAPIView):
    permission_classes = [IsApprover]
    serializer_class = PaymentFileSerializer

    def get_queryset(self):
        return PaymentFile.objects.filter(**company_filter(self.request.user))


class PaymentFileCreateView(APIView):
    permission_classes = [IsApprover]

    def post(self, request):
        serializer = PaymentFileCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        invoice_ids = serializer.validated_data['invoice_ids']
        fmt = serializer.validated_data['format']

        invoices = list(
            Invoice.objects.filter(
                pk__in=invoice_ids,
                status=Invoice.STATUS_ACCEPTED,
                **company_filter(request.user),
            ).exclude(bank_account_number='')
        )

        if not invoices:
            return Response(
                {'detail': 'Żadna z wybranych faktur nie jest dostępna do przelewu.'},
                status=400,
            )

        default_account = _get_default_account(request.user)
        if not default_account:
            return Response({'detail': 'Firma nie ma skonfigurowanego rachunku bankowego.'}, status=400)

        requested_account = serializer.validated_data.get('debit_account', '').replace(' ', '').replace('-', '')
        if requested_account:
            try:
                account_obj = CompanyBankAccount.objects.get(
                    account_number=requested_account,
                    **({'company': request.user.company} if not request.user.is_superuser else {}),
                )
                debit_account_number = account_obj.account_number
                bank_key = account_obj.bank_key or detect_bank_key(debit_account_number)
            except CompanyBankAccount.DoesNotExist:
                return Response({'detail': 'Podany rachunek bankowy nie istnieje w tej firmie.'}, status=400)
        else:
            debit_account_number = default_account.account_number
            bank_key = default_account.bank_key or detect_bank_key(debit_account_number)
        generator, extension, bank_label = _build_generator(debit_account_number, bank_key, request.user)
        content_bytes = generator.generate(invoices)

        today_str = date.today().strftime('%Y%m%d')
        suffix = get_file_suffix(bank_key)
        file_name = f'przelewy_{today_str}_{suffix}.{extension}'
        total = sum(inv.amount_gross for inv in invoices)

        fmt_map = {'erste': PaymentFile.FORMAT_ERSTE, 'mbank': PaymentFile.FORMAT_MBANK}
        resolved_fmt = fmt_map.get(bank_key, PaymentFile.FORMAT_ELIXIR)

        pf = PaymentFile.objects.create(
            company=request.user.company if not request.user.is_superuser else None,
            format=resolved_fmt,
            debit_account=debit_account_number.replace(' ', ''),
            file_name=file_name,
            file_content=content_bytes,
            total_amount=total,
            invoice_count=len(invoices),
            created_by=request.user,
        )

        for i, inv in enumerate(invoices, start=1):
            PaymentFileItem.objects.create(
                payment_file=pf, invoice=inv, amount=inv.amount_gross,
                debit_account=debit_account_number.replace(' ', ''), line_number=i,
            )
            old_status = inv.status
            inv.status = Invoice.STATUS_SENT_FOR_PAYMENT
            inv.updated_by = request.user
            inv.save(update_fields=['status', 'updated_by', 'updated_at'])
            InvoiceStatusLog.objects.create(
                invoice=inv, old_status=old_status, new_status=Invoice.STATUS_SENT_FOR_PAYMENT,
                changed_by=request.user, note=f'Automatycznie po wygenerowaniu pliku {file_name}',
            )

        log_event(request.user, AuditLog.ACTION_PAYMENT_FILE, entity=pf, request=request,
                  detail={'filename': file_name, 'format': resolved_fmt, 'count': pf.invoice_count, 'total': str(pf.total_amount)})

        return Response(PaymentFileSerializer(pf).data, status=201)


class PaymentFileDownloadView(APIView):
    permission_classes = [IsApprover]

    def get(self, request, pk):
        pf = get_object_or_404(PaymentFile, pk=pk, **company_filter(request.user))
        response = HttpResponse(bytes(pf.file_content), content_type=pf.get_content_type())
        response['Content-Disposition'] = f'attachment; filename="{pf.file_name}"'
        return response


class CompanyBankAccountsView(APIView):
    permission_classes = [IsAccountant]

    def _company_filter(self, user):
        return {} if user.is_superuser else {'company': user.company}

    def get(self, request):
        qs = CompanyBankAccount.objects.filter(
            **self._company_filter(request.user)
        ).order_by('-is_default', 'label')
        return Response(CompanyBankAccountSerializer(qs, many=True).data)

    def post(self, request):
        company = request.user.company
        if not company:
            return Response({'detail': 'Brak przypisanej firmy.'}, status=400)
        serializer = CompanyBankAccountSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save(company=company)
        return Response(serializer.data, status=201)


class CompanyBankAccountDetailView(APIView):
    permission_classes = [IsAccountant]

    def _get_account(self, request, pk):
        cf = {} if request.user.is_superuser else {'company': request.user.company}
        return get_object_or_404(CompanyBankAccount, pk=pk, **cf)

    def patch(self, request, pk):
        account = self._get_account(request, pk)
        serializer = CompanyBankAccountSerializer(account, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)

    def delete(self, request, pk):
        account = self._get_account(request, pk)
        account.delete()
        return Response(status=204)
