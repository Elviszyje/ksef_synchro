from datetime import date

from django.conf import settings
from django.contrib import messages
from django.http import HttpResponse
from django.shortcuts import get_object_or_404, redirect
from django.views.generic import ListView, View
from django.template.response import TemplateResponse

from core.permissions import RoleRequiredMixin, CompanyAccessMixin, company_filter
from core.audit import log_event
from core.models import AuditLog
from apps.invoices.models import Invoice, InvoiceStatusLog
from .models import PaymentFile, PaymentFileItem
from .generators.erste_bank import ErsteBankGenerator
from .generators.elixir import ElixirGenerator


def _get_generator(fmt: str):
    kwargs = {
        'debit_account': settings.COMPANY_BANK_ACCOUNT,
        'company_name': settings.COMPANY_NAME,
        'company_address': settings.COMPANY_ADDRESS,
    }
    if fmt == PaymentFile.FORMAT_ERSTE:
        return ErsteBankGenerator(**kwargs)
    return ElixirGenerator(**kwargs)


class PaymentFileListView(RoleRequiredMixin, CompanyAccessMixin, ListView):
    min_role = 'approver'
    model = PaymentFile
    template_name = 'payments/payment_file_list.html'
    context_object_name = 'payment_files'
    paginate_by = 30


class PaymentFileCreateView(RoleRequiredMixin, View):
    min_role = 'approver'
    template_name = 'payments/payment_file_form.html'

    def _get_accepted_invoices(self, request):
        return Invoice.objects.filter(
            status=Invoice.STATUS_ACCEPTED,
            **company_filter(request.user),
        ).exclude(bank_account_number='').order_by('-issue_date')

    def get(self, request):
        invoices = self._get_accepted_invoices(request)
        return TemplateResponse(request, self.template_name, {
            'invoices': invoices,
            'format_choices': PaymentFile.FORMAT_CHOICES,
        })

    def post(self, request):
        invoice_ids = request.POST.getlist('invoice_ids')
        fmt = request.POST.get('format', PaymentFile.FORMAT_ERSTE)

        if not invoice_ids:
            messages.error(request, 'Nie wybrano żadnych faktur.')
            return redirect('payments:create')

        if fmt not in (PaymentFile.FORMAT_ERSTE, PaymentFile.FORMAT_ELIXIR):
            messages.error(request, 'Nieprawidłowy format pliku.')
            return redirect('payments:create')

        invoices = Invoice.objects.filter(
            pk__in=invoice_ids,
            status=Invoice.STATUS_ACCEPTED,
            **company_filter(request.user),
        ).exclude(bank_account_number='')

        if not invoices.exists():
            messages.error(request, 'Żadna z wybranych faktur nie jest dostępna do przelewu.')
            return redirect('payments:create')

        # Generuj plik
        generator = _get_generator(fmt)
        content_bytes = generator.generate(invoices)

        today_str = date.today().strftime('%Y%m%d')
        extension = 'txt' if fmt == PaymentFile.FORMAT_ERSTE else 'pli'
        file_name = f'przelewy_{today_str}.{extension}'

        total = sum(inv.amount_gross for inv in invoices)

        pf = PaymentFile.objects.create(
            company=request.user.company if not request.user.is_superuser else None,
            format=fmt,
            file_name=file_name,
            file_content=content_bytes,
            total_amount=total,
            invoice_count=invoices.count(),
            created_by=request.user,
        )

        for i, inv in enumerate(invoices, start=1):
            PaymentFileItem.objects.create(
                payment_file=pf,
                invoice=inv,
                amount=inv.amount_gross,
                line_number=i,
            )

        # Zmień statusy na "przekazano do opłacenia"
        for inv in invoices:
            old_status = inv.status
            inv.status = Invoice.STATUS_SENT_FOR_PAYMENT
            inv.updated_by = request.user
            inv.save(update_fields=['status', 'updated_by', 'updated_at'])
            InvoiceStatusLog.objects.create(
                invoice=inv,
                old_status=old_status,
                new_status=Invoice.STATUS_SENT_FOR_PAYMENT,
                changed_by=request.user,
                note=f'Automatycznie po wygenerowaniu pliku {file_name}',
            )

        log_event(request.user, AuditLog.ACTION_PAYMENT_FILE, entity=pf, request=request,
                  detail={'filename': file_name, 'format': fmt,
                          'count': pf.invoice_count, 'total': str(pf.total_amount)})

        messages.success(request, f'Plik {file_name} wygenerowany. {invoices.count()} faktur oznaczono jako "Przekazano do opłacenia".')
        return redirect('payments:download', pk=pf.pk)


class PaymentFileDownloadView(RoleRequiredMixin, View):
    min_role = 'approver'

    def get(self, request, pk):
        pf = get_object_or_404(PaymentFile, pk=pk, **company_filter(request.user))
        encoding = 'windows-1250' if pf.format == PaymentFile.FORMAT_ERSTE else 'cp1250'
        response = HttpResponse(
            bytes(pf.file_content),
            content_type=f'text/plain; charset={encoding}',
        )
        response['Content-Disposition'] = f'attachment; filename="{pf.file_name}"'
        return response
