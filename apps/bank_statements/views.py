from django.contrib import messages
from django.shortcuts import get_object_or_404, redirect
from django.utils import timezone
from django.views.generic import ListView, View
from django.template.response import TemplateResponse

from core.permissions import RoleRequiredMixin, CompanyAccessMixin, company_filter
from core.audit import log_event
from core.models import AuditLog
from apps.invoices.models import Invoice, InvoiceStatusLog
from apps.accounts.models import CompanyBankAccount
from .models import BankStatement, BankTransaction, TransactionMatch
from .parsers.mt940 import InvoiceMatcher
from .parsers.detect import detect_and_parse


class BankStatementListView(RoleRequiredMixin, CompanyAccessMixin, ListView):
    min_role = 'accountant'
    model = BankStatement
    template_name = 'bank_statements/statement_list.html'
    context_object_name = 'statements'
    paginate_by = 20


class BankStatementUploadView(RoleRequiredMixin, View):
    min_role = 'accountant'
    template_name = 'bank_statements/upload_form.html'

    def get(self, request):
        return TemplateResponse(request, self.template_name, {})

    def post(self, request):
        uploaded_file = request.FILES.get('mt940_file')
        if not uploaded_file:
            messages.error(request, 'Nie wybrano pliku.')
            return TemplateResponse(request, self.template_name, {})

        # Odczytaj — MT940 zwykle w ISO-8859-1 lub UTF-8
        raw = None
        for enc in ('utf-8', 'iso-8859-1', 'windows-1250'):
            try:
                raw = uploaded_file.read().decode(enc)
                break
            except UnicodeDecodeError:
                uploaded_file.seek(0)

        if not raw:
            messages.error(request, 'Nie można odczytać pliku. Sprawdź kodowanie (UTF-8, ISO-8859-1, Windows-1250).')
            return TemplateResponse(request, self.template_name, {})

        preferred_keys = list(
            CompanyBankAccount.objects.filter(**company_filter(request.user))
            .values_list('bank_key', flat=True)
        )
        try:
            stmt_data = detect_and_parse(raw, preferred_bank_keys=preferred_keys)
        except ValueError as e:
            messages.error(request, str(e))
            return TemplateResponse(request, self.template_name, {})
        except Exception as e:
            messages.error(request, f'Błąd parsowania pliku: {e}')
            return TemplateResponse(request, self.template_name, {})

        stmt = BankStatement.objects.create(
            company=request.user.company if not request.user.is_superuser else None,
            file_name=uploaded_file.name,
            account_number=stmt_data.account_number,
            statement_date=stmt_data.statement_date,
            file_format=stmt_data.bank_key,
            raw_content=raw,
            uploaded_by=request.user,
        )

        for tx_data in stmt_data.transactions:
            BankTransaction.objects.create(
                statement=stmt,
                transaction_date=tx_data.transaction_date,
                value_date=tx_data.value_date,
                amount=tx_data.amount,
                currency=tx_data.currency,
                is_debit=not tx_data.is_credit,
                description=tx_data.description,
                counterparty=getattr(tx_data, 'counterparty', ''),
                reference=tx_data.reference,
            )

        log_event(request.user, AuditLog.ACTION_BANK_UPLOAD, entity=stmt, request=request,
                  detail={'filename': uploaded_file.name,
                          'transactions': len(stmt_data.transactions)})
        messages.success(request, f'Wyciąg załadowany: {len(stmt_data.transactions)} transakcji.')
        return redirect('bank_statements:review', pk=stmt.pk)


class BankStatementReviewView(RoleRequiredMixin, View):
    min_role = 'accountant'
    template_name = 'bank_statements/match_review.html'

    def get(self, request, pk):
        stmt = get_object_or_404(BankStatement, pk=pk, **company_filter(request.user))
        transactions = stmt.transactions.prefetch_related('matches__invoice').order_by('transaction_date')

        # Uruchom matcher jeśli brak dopasowań
        if not TransactionMatch.objects.filter(transaction__statement=stmt).exists():
            self._run_matcher(stmt, request)

        # Odśwież
        transactions = stmt.transactions.prefetch_related('matches__invoice').order_by('transaction_date')

        return TemplateResponse(request, self.template_name, {
            'statement': stmt,
            'transactions': transactions,
        })

    def _run_matcher(self, stmt: BankStatement, request):
        matcher = InvoiceMatcher()
        transactions = list(stmt.transactions.all())
        invoices_qs = Invoice.objects.filter(
            status=Invoice.STATUS_SENT_FOR_PAYMENT,
            **company_filter(request.user),
        )

        TX = type('TX', (), {})
        pseudo_txs = []
        for t in transactions:
            px = TX()
            px.amount = t.amount
            px.description = f"{t.description} {t.counterparty}".strip()
            px.is_credit = not t.is_debit
            px.reference = t.reference
            px.transaction_date = t.transaction_date
            pseudo_txs.append(px)

        tx_by_pseudo_id = {id(px): t for px, t in zip(pseudo_txs, transactions)}

        matches = matcher.match(pseudo_txs, invoices_qs)

        for match_data in matches:
            pseudo_tx = match_data['transaction']
            tx_obj = tx_by_pseudo_id.get(id(pseudo_tx))
            if not tx_obj:
                continue
            inv = match_data['invoice']
            TransactionMatch.objects.get_or_create(
                transaction=tx_obj,
                invoice=inv,
                defaults={
                    'match_type': match_data['match_type'],
                    'confidence': match_data['confidence'],
                },
            )


class ToggleMatchView(RoleRequiredMixin, View):
    min_role = 'accountant'

    def post(self, request, pk, match_pk):
        match = get_object_or_404(TransactionMatch, pk=match_pk, transaction__statement__pk=pk)
        match.is_confirmed = not match.is_confirmed
        if match.is_confirmed:
            match.confirmed_by = request.user
            match.confirmed_at = timezone.now()
        else:
            match.confirmed_by = None
            match.confirmed_at = None
        match.save()
        log_event(request.user, AuditLog.ACTION_BANK_MATCH, entity=match.invoice, request=request,
                  detail={'confirmed': match.is_confirmed,
                          'transaction_amount': str(match.transaction.amount)})
        if request.htmx:
            from django.template.loader import render_to_string
            from django.http import HttpResponse
            html = render_to_string(
                'bank_statements/partials/toggle_btn.html',
                {'match': match, 'stmt_pk': pk, 'request': request},
            )
            return HttpResponse(html)
        return redirect('bank_statements:review', pk=pk)


class BankStatementConfirmView(RoleRequiredMixin, View):
    min_role = 'accountant'

    def post(self, request, pk):
        stmt = get_object_or_404(BankStatement, pk=pk, **company_filter(request.user))
        confirmed_matches = TransactionMatch.objects.filter(
            transaction__statement=stmt,
            is_confirmed=True,
        ).select_related('invoice')

        count = 0
        for match in confirmed_matches:
            inv = match.invoice
            if inv.status != Invoice.STATUS_PAID:
                old_status = inv.status
                inv.status = Invoice.STATUS_PAID
                inv.updated_by = request.user
                inv.save(update_fields=['status', 'updated_by', 'updated_at'])
                InvoiceStatusLog.objects.create(
                    invoice=inv,
                    old_status=old_status,
                    new_status=Invoice.STATUS_PAID,
                    changed_by=request.user,
                    note=f'Automatycznie na podstawie wyciągu bankowego: {stmt.file_name}',
                )
                match.transaction.is_matched = True
                match.transaction.save(update_fields=['is_matched'])
                count += 1

        stmt.status = BankStatement.STATUS_CONFIRMED
        stmt.confirmed_by = request.user
        stmt.confirmed_at = timezone.now()
        stmt.save(update_fields=['status', 'confirmed_by', 'confirmed_at'])

        log_event(request.user, AuditLog.ACTION_BANK_CONFIRM, entity=stmt, request=request,
                  detail={'filename': stmt.file_name, 'invoices_paid': count})
        messages.success(request, f'{count} faktur oznaczono jako opłacone.')
        return redirect('bank_statements:list')


class BankStatementDeleteView(RoleRequiredMixin, View):
    min_role = 'accountant'

    def post(self, request, pk):
        stmt = get_object_or_404(BankStatement, pk=pk, **company_filter(request.user))
        file_name = stmt.file_name
        stmt.delete()
        log_event(request.user, AuditLog.ACTION_BANK_CONFIRM, entity=None, request=request,
                  detail={'action': 'delete', 'filename': file_name})
        messages.success(request, f'Wyciąg "{file_name}" został usunięty.')
        return redirect('bank_statements:list')
