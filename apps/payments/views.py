from collections import defaultdict
from datetime import date

from django.contrib import messages
from django.db import transaction
from django.http import HttpResponse
from django.shortcuts import get_object_or_404, redirect
from django.views.generic import DetailView, ListView, View
from django.template.response import TemplateResponse

from core.permissions import RoleRequiredMixin, CompanyAccessMixin, company_filter
from core.audit import log_event
from core.models import AuditLog
from apps.invoices.models import Invoice, InvoiceStatusLog
from apps.accounts.models import CompanyBankAccount
from .models import PaymentFile, PaymentFileItem
from .bank_detection import detect_bank_key, get_file_suffix, BANK_LABELS
from .generators.registry import get_generator_for_bank


def _get_company_bank_accounts(user):
    """Zwraca QuerySet rachunków firmy użytkownika."""
    if not user.company_id:
        return CompanyBankAccount.objects.none()
    return CompanyBankAccount.objects.filter(company_id=user.company_id)


def _get_default_account(user):
    """Zwraca domyślny rachunek bankowy firmy lub None."""
    qs = _get_company_bank_accounts(user)
    return qs.filter(is_default=True).first() or qs.first()


def _build_generator(debit_account_number: str, bank_key: str, user):
    """Tworzy generator dla danego rachunku obciążeniowego."""
    from django.conf import settings
    company = getattr(user, 'company', None)
    company_name = company.name if company else getattr(settings, 'COMPANY_NAME', '')
    company_address = company.address if company else getattr(settings, 'COMPANY_ADDRESS', '')
    GeneratorClass, extension, label = get_generator_for_bank(bank_key)
    gen = GeneratorClass(
        debit_account=debit_account_number,
        company_name=company_name,
        company_address=company_address,
    )
    return gen, extension, label


def _generate_and_save_file(request, debit_account_number: str, bank_key: str, invoices, line_offset: int = 1):
    """Generuje jeden PaymentFile dla podanych faktur i rachunku obciążeniowego."""
    gen, extension, bank_label = _build_generator(debit_account_number, bank_key, request.user)
    content_bytes = gen.generate(invoices)

    today_str = date.today().strftime('%Y%m%d')
    suffix = get_file_suffix(bank_key)
    file_name = f'przelewy_{today_str}_{suffix}.{extension}'

    fmt_map = {'erste': PaymentFile.FORMAT_ERSTE, 'mbank': PaymentFile.FORMAT_MBANK}
    fmt = fmt_map.get(bank_key, PaymentFile.FORMAT_ELIXIR)

    total = sum(inv.amount_gross for inv in invoices)
    pf = PaymentFile.objects.create(
        company=request.user.company if not request.user.is_superuser else None,
        format=fmt,
        debit_account=debit_account_number.replace(' ', ''),
        file_name=file_name,
        file_content=content_bytes,
        total_amount=total,
        invoice_count=len(invoices),
        created_by=request.user,
    )
    for i, inv in enumerate(invoices, start=line_offset):
        debit = getattr(inv, '_debit_account', debit_account_number)
        PaymentFileItem.objects.create(
            payment_file=pf,
            invoice=inv,
            amount=inv.amount_gross,
            debit_account=debit.replace(' ', ''),
            line_number=i,
        )
    return pf, file_name


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
        bank_accounts = _get_company_bank_accounts(request.user)
        default_account = _get_default_account(request.user)
        return TemplateResponse(request, self.template_name, {
            'invoices': invoices,
            'bank_accounts': bank_accounts,
            'default_account_id': default_account.pk if default_account else None,
        })

    def post(self, request):
        invoice_ids = request.POST.getlist('invoice_ids')
        confirmed = request.POST.get('confirmed') == '1'

        if not invoice_ids:
            messages.error(request, 'Nie wybrano żadnych faktur.')
            return redirect('payments:create')

        invoices = list(Invoice.objects.filter(
            pk__in=invoice_ids,
            status=Invoice.STATUS_ACCEPTED,
            **company_filter(request.user),
        ).exclude(bank_account_number=''))

        if not invoices:
            messages.error(request, 'Żadna z wybranych faktur nie jest dostępna do przelewu.')
            return redirect('payments:create')

        # Zbierz rachunek obciążeniowy per faktura
        bank_accounts_qs = _get_company_bank_accounts(request.user)
        bank_accounts = {str(ba.pk): ba for ba in bank_accounts_qs}
        default_account = _get_default_account(request.user)

        for inv in invoices:
            key = f'debit_{inv.pk}'
            chosen_id = request.POST.get(key)
            if chosen_id and chosen_id in bank_accounts:
                ba = bank_accounts[chosen_id]
            elif default_account:
                ba = default_account
            else:
                messages.error(request, 'Firma nie ma skonfigurowanego rachunku bankowego.')
                return redirect('payments:create')
            inv._debit_account = ba.account_number
            inv._debit_bank_key = ba.bank_key or detect_bank_key(ba.account_number)

        # Grupuj per bank nadawcy (debit account)
        groups: dict[str, list] = defaultdict(list)
        for inv in invoices:
            groups[inv._debit_account].append(inv)

        # Jeśli wiele grup i brak potwierdzenia → pokaż ostrzeżenie
        if len(groups) > 1 and not confirmed:
            bank_accounts_list = _get_company_bank_accounts(request.user)
            default_id = default_account.pk if default_account else None
            group_info = []
            for acct_nr, inv_list in groups.items():
                bank_key = inv_list[0]._debit_bank_key
                label = BANK_LABELS.get(bank_key) or acct_nr[-8:]
                suffix = get_file_suffix(bank_key)
                ext = get_generator_for_bank(bank_key)[1]
                group_info.append({
                    'label': label,
                    'count': len(inv_list),
                    'file_name': f'przelewy_{date.today().strftime("%Y%m%d")}_{suffix}.{ext}',
                })
            return TemplateResponse(request, self.template_name, {
                'invoices': self._get_accepted_invoices(request),
                'bank_accounts': bank_accounts_list,
                'default_account_id': default_id,
                'multi_bank_warning': True,
                'group_info': group_info,
                'post_data': request.POST,
            })

        # Generuj pliki (atomowo)
        created_files = []
        with transaction.atomic():
            for acct_nr, inv_group in groups.items():
                bank_key = inv_group[0]._debit_bank_key
                pf, file_name = _generate_and_save_file(request, acct_nr, bank_key, inv_group)
                created_files.append((pf, file_name, inv_group))

            # Zmień statusy faktur
            all_invoices = invoices
            for inv in all_invoices:
                old_status = inv.status
                inv.status = Invoice.STATUS_SENT_FOR_PAYMENT
                inv.updated_by = request.user
                inv.save(update_fields=['status', 'updated_by', 'updated_at'])
                InvoiceStatusLog.objects.create(
                    invoice=inv,
                    old_status=old_status,
                    new_status=Invoice.STATUS_SENT_FOR_PAYMENT,
                    changed_by=request.user,
                    note=f'Automatycznie po wygenerowaniu pliku {created_files[0][1]}',
                )

            for pf, file_name, inv_group in created_files:
                log_event(request.user, AuditLog.ACTION_PAYMENT_FILE, entity=pf, request=request,
                          detail={'filename': file_name, 'format': pf.format,
                                  'count': pf.invoice_count, 'total': str(pf.total_amount)})

        if len(created_files) == 1:
            pf, file_name, _ = created_files[0]
            messages.success(request, f'Plik {file_name} wygenerowany. {len(invoices)} faktur oznaczono jako "Przekazano do opłacenia".')
            return redirect('payments:download', pk=pf.pk)
        else:
            names = ', '.join(fn for _, fn, _ in created_files)
            messages.success(request, f'Wygenerowano {len(created_files)} pliki: {names}. {len(invoices)} faktur oznaczono jako "Przekazano do opłacenia".')
            return redirect('payments:list')


class PaymentFileDownloadView(RoleRequiredMixin, View):
    min_role = 'approver'

    def get(self, request, pk):
        pf = get_object_or_404(PaymentFile, pk=pk, **company_filter(request.user))
        response = HttpResponse(
            bytes(pf.file_content),
            content_type=pf.get_content_type(),
        )
        response['Content-Disposition'] = f'attachment; filename="{pf.file_name}"'
        return response


class PaymentFileDetailView(RoleRequiredMixin, View):
    min_role = 'approver'
    template_name = 'payments/payment_file_detail.html'

    def get(self, request, pk):
        pf = get_object_or_404(PaymentFile, pk=pk, **company_filter(request.user))
        items = pf.items.select_related('invoice').order_by('line_number')
        can_reset = not items.filter(invoice__status=Invoice.STATUS_PAID).exists()
        return TemplateResponse(request, self.template_name, {
            'pf': pf,
            'items': items,
            'can_reset': can_reset,
        })


class PaymentFileResetView(RoleRequiredMixin, View):
    min_role = 'approver'

    def post(self, request, pk):
        pf = get_object_or_404(PaymentFile, pk=pk, **company_filter(request.user))
        items = list(pf.items.select_related('invoice').all())

        if any(item.invoice.status == Invoice.STATUS_PAID for item in items):
            messages.error(request, 'Nie można zresetować paczki — co najmniej jedna faktura ma status "Opłacona".')
            return redirect('payments:detail', pk=pk)

        file_name = pf.file_name
        with transaction.atomic():
            for item in items:
                inv = item.invoice
                if inv.status == Invoice.STATUS_SENT_FOR_PAYMENT:
                    old_status = inv.status
                    inv.status = Invoice.STATUS_ACCEPTED
                    inv.updated_by = request.user
                    inv.save(update_fields=['status', 'updated_by', 'updated_at'])
                    InvoiceStatusLog.objects.create(
                        invoice=inv,
                        old_status=old_status,
                        new_status=Invoice.STATUS_ACCEPTED,
                        changed_by=request.user,
                        note=f'Cofnięto do zaakceptowana — reset paczki {file_name}',
                    )

            log_event(request.user, AuditLog.ACTION_PAYMENT_FILE, request=request,
                      detail={'action': 'reset', 'filename': file_name, 'count': len(items)})
            pf.delete()

        messages.success(request, f'Paczka {file_name} została zresetowana. {len(items)} faktur wróciło do statusu "Zaakceptowana".')
        return redirect('payments:list')
