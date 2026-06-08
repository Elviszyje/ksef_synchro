from django.utils import timezone
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status

from core.permissions import company_filter
from core.audit import log_event
from core.models import AuditLog
from apps.api.permissions import IsAccountant
from apps.accounts.models import CompanyBankAccount
from apps.bank_statements.models import BankStatement, BankTransaction, TransactionMatch
from apps.bank_statements.parsers.mt940 import InvoiceMatcher
from apps.bank_statements.parsers.detect import detect_and_parse
from apps.invoices.models import Invoice, InvoiceStatusLog

from .serializers import BankStatementSerializer, BankStatementDetailSerializer


class BankStatementListCreateView(APIView):
    permission_classes = [IsAccountant]

    def get(self, request):
        stmts = BankStatement.objects.filter(
            **company_filter(request.user)
        ).order_by('-uploaded_at')
        serializer = BankStatementSerializer(stmts, many=True)
        return Response(serializer.data)

    def post(self, request):
        uploaded_file = request.FILES.get('statement_file') or request.FILES.get('mt940_file')
        if not uploaded_file:
            return Response({'detail': 'Nie wybrano pliku (pole: statement_file).'}, status=status.HTTP_400_BAD_REQUEST)

        raw = None
        for enc in ('utf-8-sig', 'utf-8', 'iso-8859-1', 'windows-1250'):
            try:
                raw = uploaded_file.read().decode(enc)
                break
            except UnicodeDecodeError:
                uploaded_file.seek(0)

        if not raw:
            return Response(
                {'detail': 'Nie można odczytać pliku. Sprawdź kodowanie (UTF-8, ISO-8859-1, Windows-1250).'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        preferred_keys = list(
            CompanyBankAccount.objects.filter(**company_filter(request.user))
            .values_list('bank_key', flat=True)
        )
        try:
            stmt_data = detect_and_parse(raw, preferred_bank_keys=preferred_keys)
        except ValueError as e:
            return Response({'detail': str(e)}, status=status.HTTP_400_BAD_REQUEST)
        except Exception as e:
            return Response({'detail': f'Błąd parsowania pliku: {e}'}, status=status.HTTP_400_BAD_REQUEST)

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
                  detail={'filename': uploaded_file.name, 'transactions': len(stmt_data.transactions)})

        serializer = BankStatementSerializer(stmt)
        return Response(serializer.data, status=status.HTTP_201_CREATED)


class BankStatementDetailView(APIView):
    permission_classes = [IsAccountant]

    def _get_stmt(self, request, pk):
        try:
            return BankStatement.objects.prefetch_related(
                'transactions__matches__invoice'
            ).get(pk=pk, **company_filter(request.user))
        except BankStatement.DoesNotExist:
            return None

    def get(self, request, pk):
        stmt = self._get_stmt(request, pk)
        if not stmt:
            return Response({'detail': 'Nie znaleziono.'}, status=status.HTTP_404_NOT_FOUND)
        serializer = BankStatementDetailSerializer(stmt)
        return Response(serializer.data)


class RunMatcherView(APIView):
    permission_classes = [IsAccountant]

    def post(self, request, pk):
        try:
            stmt = BankStatement.objects.get(pk=pk, **company_filter(request.user))
        except BankStatement.DoesNotExist:
            return Response({'detail': 'Nie znaleziono.'}, status=status.HTTP_404_NOT_FOUND)

        transactions = list(stmt.transactions.all())
        invoices_qs = Invoice.objects.filter(
            status=Invoice.STATUS_SENT_FOR_PAYMENT,
            **company_filter(request.user),
        )

        matcher = InvoiceMatcher()

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

        created_count = 0
        for match_data in matches:
            pseudo_tx = match_data['transaction']
            tx_obj = tx_by_pseudo_id.get(id(pseudo_tx))
            if not tx_obj:
                continue
            _, created = TransactionMatch.objects.get_or_create(
                transaction=tx_obj,
                invoice=match_data['invoice'],
                defaults={
                    'match_type': match_data['match_type'],
                    'confidence': match_data['confidence'],
                },
            )
            if created:
                created_count += 1

        stmt.status = BankStatement.STATUS_REVIEWED
        stmt.save(update_fields=['status'])

        return Response({'matched_count': created_count})


class ToggleMatchView(APIView):
    permission_classes = [IsAccountant]

    def post(self, request, pk, match_pk):
        stmt_filter = company_filter(request.user)
        try:
            stmt = BankStatement.objects.get(pk=pk, **stmt_filter)
        except BankStatement.DoesNotExist:
            return Response({'detail': 'Nie znaleziono.'}, status=status.HTTP_404_NOT_FOUND)
        try:
            match = TransactionMatch.objects.select_related('invoice', 'transaction').get(
                pk=match_pk, transaction__statement=stmt
            )
        except TransactionMatch.DoesNotExist:
            return Response({'detail': 'Nie znaleziono.'}, status=status.HTTP_404_NOT_FOUND)

        match.is_confirmed = not match.is_confirmed
        if match.is_confirmed:
            match.confirmed_by = request.user
            match.confirmed_at = timezone.now()
        else:
            match.confirmed_by = None
            match.confirmed_at = None
        match.save()

        log_event(request.user, AuditLog.ACTION_BANK_MATCH, entity=match.invoice, request=request,
                  detail={'confirmed': match.is_confirmed, 'transaction_amount': str(match.transaction.amount)})

        return Response({'id': match.id, 'is_confirmed': match.is_confirmed})


class ConfirmStatementView(APIView):
    permission_classes = [IsAccountant]

    def post(self, request, pk):
        try:
            stmt = BankStatement.objects.get(pk=pk, **company_filter(request.user))
        except BankStatement.DoesNotExist:
            return Response({'detail': 'Nie znaleziono.'}, status=status.HTTP_404_NOT_FOUND)

        confirmed_matches = TransactionMatch.objects.filter(
            transaction__statement=stmt,
            is_confirmed=True,
        ).select_related('invoice', 'transaction')

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

        return Response({'confirmed_count': count})
