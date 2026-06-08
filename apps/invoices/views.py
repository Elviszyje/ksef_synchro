from datetime import date
from dateutil.relativedelta import relativedelta

from django.contrib import messages
from django.http import HttpResponse, JsonResponse
from django.shortcuts import get_object_or_404, redirect
from django.utils import timezone
from django.views.generic import DetailView, View
from django.views.generic.list import MultipleObjectMixin

from core.permissions import RoleRequiredMixin, CompanyAccessMixin, company_filter
from core.audit import log_event
from core.models import AuditLog
from .export import generate_excel
from .filters import InvoiceFilter
from .models import Invoice, InvoiceStatusLog

try:
    from dateutil.relativedelta import relativedelta
except ImportError:
    # fallback — oblicz ręcznie
    class relativedelta:
        def __init__(self, months=0):
            self.months = months


STATUS_TRANSITIONS = {
    Invoice.STATUS_NEW: [Invoice.STATUS_DISPUTED, Invoice.STATUS_ACCEPTED, Invoice.STATUS_PAID],
    Invoice.STATUS_DISPUTED: [Invoice.STATUS_NEW, Invoice.STATUS_ACCEPTED, Invoice.STATUS_PAID],
    Invoice.STATUS_ACCEPTED: [Invoice.STATUS_DISPUTED, Invoice.STATUS_SENT_FOR_PAYMENT, Invoice.STATUS_PAID],
    Invoice.STATUS_SENT_FOR_PAYMENT: [Invoice.STATUS_PAID],
    Invoice.STATUS_PAID: [],
}


class InvoiceListView(RoleRequiredMixin, View):
    min_role = 'viewer'
    template_name = 'invoices/invoice_list.html'
    paginate_by = 50

    def get(self, request):
        from django.core.paginator import Paginator
        from django.template.response import TemplateResponse

        qs = Invoice.objects.filter(**company_filter(request.user)).select_related('updated_by').order_by('-issue_date', '-synced_at')
        f = InvoiceFilter(request.GET, queryset=qs)
        paginator = Paginator(f.qs, self.paginate_by)
        page_number = request.GET.get('page', 1)
        page_obj = paginator.get_page(page_number)

        context = {
            'filter': f,
            'page_obj': page_obj,
            'total_count': f.qs.count(),
            'status_choices': Invoice.STATUS_CHOICES,
        }

        if request.htmx:
            return TemplateResponse(request, 'invoices/partials/invoice_table.html', context)
        return TemplateResponse(request, self.template_name, context)


class InvoiceDetailView(RoleRequiredMixin, CompanyAccessMixin, DetailView):
    min_role = 'viewer'
    model = Invoice
    template_name = 'invoices/invoice_detail.html'
    context_object_name = 'invoice'

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx['status_logs'] = self.object.status_logs.select_related('changed_by')
        ctx['allowed_transitions'] = STATUS_TRANSITIONS.get(self.object.status, [])
        ctx['status_labels'] = dict(Invoice.STATUS_CHOICES)
        ctx['status_colors'] = Invoice.STATUS_COLORS
        if self.object.raw_xml:
            from apps.ksef.parser import parse_line_items
            ctx['line_items'] = parse_line_items(self.object.raw_xml)
        else:
            ctx['line_items'] = []
        return ctx


class InvoiceStatusChangeView(RoleRequiredMixin, View):
    min_role = 'accountant'

    def post(self, request, pk):
        invoice = get_object_or_404(Invoice, pk=pk, **company_filter(request.user))
        new_status = request.POST.get('status')
        note = request.POST.get('note', '').strip()

        allowed = STATUS_TRANSITIONS.get(invoice.status, [])
        if new_status not in allowed:
            messages.error(request, f'Niedozwolona zmiana statusu: {invoice.status} → {new_status}')
            return redirect('invoices:detail', pk=pk)

        # Zmiana przekazano_do_oplacenia wymaga roli approver
        if new_status == Invoice.STATUS_SENT_FOR_PAYMENT:
            from core.permissions import has_min_role
            if not has_min_role(request.user, 'approver'):
                messages.error(request, 'Brak uprawnień do przekazania faktury do opłacenia.')
                return redirect('invoices:detail', pk=pk)

        old_status = invoice.status
        invoice.status = new_status
        invoice.updated_by = request.user
        invoice.save(update_fields=['status', 'updated_by', 'updated_at'])

        InvoiceStatusLog.objects.create(
            invoice=invoice,
            old_status=old_status,
            new_status=new_status,
            changed_by=request.user,
            note=note,
        )

        log_event(request.user, AuditLog.ACTION_INVOICE_STATUS, entity=invoice, request=request,
                  detail={'from': old_status, 'to': new_status, 'note': note})

        status_label = dict(Invoice.STATUS_CHOICES).get(new_status, new_status)
        messages.success(request, f'Status zmieniony na: {status_label}')
        return redirect('invoices:detail', pk=pk)


class InvoiceQuickStatusView(RoleRequiredMixin, View):
    min_role = 'accountant'

    def post(self, request, pk):
        from django.template.response import TemplateResponse
        invoice = get_object_or_404(Invoice, pk=pk, **company_filter(request.user))
        new_status = request.POST.get('status')

        allowed = STATUS_TRANSITIONS.get(invoice.status, [])
        if new_status in allowed:
            if new_status == Invoice.STATUS_SENT_FOR_PAYMENT:
                from core.permissions import has_min_role
                if not has_min_role(request.user, 'approver'):
                    return TemplateResponse(request, 'invoices/partials/invoice_row.html', {'inv': invoice})

            old_status = invoice.status
            invoice.status = new_status
            invoice.updated_by = request.user
            invoice.save(update_fields=['status', 'updated_by', 'updated_at'])
            InvoiceStatusLog.objects.create(
                invoice=invoice,
                old_status=old_status,
                new_status=new_status,
                changed_by=request.user,
                note='Zmiana z listy faktur.',
            )
            log_event(request.user, AuditLog.ACTION_INVOICE_STATUS, entity=invoice, request=request,
                      detail={'from': old_status, 'to': new_status})

        return TemplateResponse(request, 'invoices/partials/invoice_row.html', {'inv': invoice})


class InvoiceBulkStatusView(RoleRequiredMixin, View):
    min_role = 'accountant'

    def post(self, request):
        ids_raw = request.POST.get('ids', '')
        new_status = request.POST.get('status', '')

        if not ids_raw or not new_status:
            return JsonResponse({'changed': 0, 'error': 'Brak parametrów'}, status=400)

        try:
            ids = [int(i) for i in ids_raw.split(',') if i.strip()]
        except ValueError:
            return JsonResponse({'changed': 0, 'error': 'Nieprawidłowe ID'}, status=400)

        invoices = Invoice.objects.filter(pk__in=ids, **company_filter(request.user))
        changed = 0

        for invoice in invoices:
            allowed = STATUS_TRANSITIONS.get(invoice.status, [])
            if new_status not in allowed:
                continue
            if new_status == Invoice.STATUS_SENT_FOR_PAYMENT:
                from core.permissions import has_min_role
                if not has_min_role(request.user, 'approver'):
                    continue

            old_status = invoice.status
            invoice.status = new_status
            invoice.updated_by = request.user
            invoice.save(update_fields=['status', 'updated_by', 'updated_at'])
            InvoiceStatusLog.objects.create(
                invoice=invoice,
                old_status=old_status,
                new_status=new_status,
                changed_by=request.user,
                note='Zmiana zbiorcza z listy faktur.',
            )
            log_event(request.user, AuditLog.ACTION_INVOICE_STATUS, entity=invoice, request=request,
                      detail={'from': old_status, 'to': new_status, 'bulk': True})
            changed += 1

        status_label = dict(Invoice.STATUS_CHOICES).get(new_status, new_status)
        return JsonResponse({'changed': changed, 'status_label': status_label})


class InvoiceNoteUpdateView(RoleRequiredMixin, View):
    min_role = 'accountant'

    def post(self, request, pk):
        invoice = get_object_or_404(Invoice, pk=pk, **company_filter(request.user))
        invoice.notes = request.POST.get('notes', '')
        invoice.updated_by = request.user
        invoice.save(update_fields=['notes', 'updated_by', 'updated_at'])
        log_event(request.user, AuditLog.ACTION_INVOICE_NOTE, entity=invoice, request=request)
        messages.success(request, 'Notatka zapisana.')
        return redirect('invoices:detail', pk=pk)


class InvoiceXmlDownloadView(RoleRequiredMixin, View):
    min_role = 'viewer'

    def get(self, request, pk):
        invoice = get_object_or_404(Invoice, pk=pk, **company_filter(request.user))
        if not invoice.raw_xml:
            from django.http import Http404
            raise Http404
        response = HttpResponse(invoice.raw_xml.encode('utf-8'),
                                content_type='application/xml; charset=utf-8')
        safe_nr = invoice.invoice_number.replace('/', '_')
        response['Content-Disposition'] = f'attachment; filename="FA2_{safe_nr}.xml"'
        return response


class InvoiceExportView(RoleRequiredMixin, View):
    min_role = 'viewer'

    def get(self, request):
        period = request.GET.get('period', 'full')
        today = date.today()

        qs = Invoice.objects.filter(**company_filter(request.user)).order_by('-issue_date')

        # Filtr statusów z bieżących parametrów
        status_filter = request.GET.getlist('status')
        if status_filter:
            qs = qs.filter(status__in=status_filter)

        if period == 'current_month':
            qs = qs.filter(issue_date__year=today.year, issue_date__month=today.month)
            title = f'Faktury_{today.strftime("%Y_%m")}'
        elif period == 'prev_month':
            first_prev = today.replace(day=1) - __import__('datetime').timedelta(days=1)
            first_prev = first_prev.replace(day=1)
            qs = qs.filter(issue_date__year=first_prev.year, issue_date__month=first_prev.month)
            title = f'Faktury_{first_prev.strftime("%Y_%m")}'
        elif period == 'custom':
            date_from = request.GET.get('date_from')
            date_to = request.GET.get('date_to')
            if date_from:
                qs = qs.filter(issue_date__gte=date_from)
            if date_to:
                qs = qs.filter(issue_date__lte=date_to)
            title = f'Faktury_{date_from or ""}_{date_to or ""}'
        else:
            title = 'Faktury_kosztowe_wszystkie'

        xlsx = generate_excel(qs, title=title)
        filename = f'{title}.xlsx'
        response = HttpResponse(
            xlsx,
            content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        )
        response['Content-Disposition'] = f'attachment; filename="{filename}"'
        return response


class InvoiceDashboardView(RoleRequiredMixin, View):
    min_role = 'viewer'
    template_name = 'invoices/dashboard.html'

    _MONTHS_PL = ['', 'sty', 'lut', 'mar', 'kwi', 'maj', 'cze', 'lip', 'sie', 'wrz', 'paź', 'lis', 'gru']

    def get(self, request):
        import json
        from decimal import Decimal
        from collections import defaultdict
        from django.db.models import Sum, Count, Max
        from django.db.models.functions import TruncMonth
        from django.template.response import TemplateResponse

        today = date.today()
        date_from = today.replace(day=1) - relativedelta(months=11)

        monthly_qs = (
            Invoice.objects
            .filter(issue_date__gte=date_from, **company_filter(request.user))
            .annotate(month=TruncMonth('issue_date'))
            .values('month')
            .annotate(
                total_gross=Sum('amount_gross'),
                total_net=Sum('amount_net'),
                count=Count('id'),
            )
            .order_by('month')
        )

        # Grupowanie po (miesiąc, NIP) — jeden sprzedawca może wystawiać
        # faktury z nieznacznie różnymi nazwami; Max('seller_name') daje
        # deterministyczny wynik przy minimalnym koszcie zapytania.
        sellers_qs = (
            Invoice.objects
            .filter(issue_date__gte=date_from, **company_filter(request.user))
            .annotate(month=TruncMonth('issue_date'))
            .values('month', 'seller_nip')
            .annotate(
                total_gross=Sum('amount_gross'),
                count=Count('id'),
                seller_name=Max('seller_name'),
            )
            .order_by('month', '-total_gross')
        )

        top_by_month: dict[str, list] = defaultdict(list)
        for row in sellers_qs:
            key = row['month'].strftime('%Y-%m')
            if len(top_by_month[key]) < 5:
                top_by_month[key].append({
                    'seller_name': row['seller_name'],
                    'seller_nip': row['seller_nip'],
                    'total_gross': row['total_gross'] or Decimal('0'),
                    'count': row['count'],
                })

        monthly_totals = []
        for row in monthly_qs:
            m = row['month']
            key = m.strftime('%Y-%m')
            monthly_totals.append({
                'key': key,
                'label': f"{self._MONTHS_PL[m.month]} {m.year}",
                'total_gross': row['total_gross'] or Decimal('0'),
                'total_net': row['total_net'] or Decimal('0'),
                'count': row['count'],
                'top_sellers': top_by_month.get(key, []),
            })

        chart_data = json.dumps({
            'labels': [m['label'] for m in monthly_totals],
            'datasets': [{
                'label': 'Koszty brutto (PLN)',
                'data': [float(m['total_gross']) for m in monthly_totals],
                'backgroundColor': 'rgba(96, 165, 250, 0.7)',
                'borderColor': 'rgba(96, 165, 250, 1)',
                'borderWidth': 1,
                'borderRadius': 4,
                'hoverBackgroundColor': 'rgba(96, 165, 250, 0.9)',
            }]
        })

        total_gross = sum((m['total_gross'] for m in monthly_totals), Decimal('0'))
        total_count = sum(m['count'] for m in monthly_totals)
        months_with_data = sum(1 for m in monthly_totals if m['count'] > 0)
        avg_gross = (total_gross / months_with_data) if months_with_data else Decimal('0')

        return TemplateResponse(request, self.template_name, {
            'monthly_totals': monthly_totals,
            'months_for_tabs': list(reversed(monthly_totals)),
            'chart_data_json': chart_data,
            'total_gross_12m': total_gross,
            'total_count_12m': total_count,
            'avg_gross_12m': avg_gross,
        })
