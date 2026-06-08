import json
import logging

from django.contrib import messages
from django.core.paginator import Paginator
from django.http import HttpResponse, Http404, JsonResponse
from django.shortcuts import get_object_or_404, redirect
from django.template.response import TemplateResponse
from django.views.generic import View

from core.permissions import RoleRequiredMixin, company_filter, has_min_role
from .forms import OutgoingInvoiceForm, InvoiceItemFormSet, BuyerForm
from .models import OutgoingInvoice, InvoiceItem, Buyer
from .nip_lookup import fetch_nip_data

logger = logging.getLogger(__name__)


def _save_buyer_from_invoice(request, invoice) -> 'Buyer | None':
    """Tworzy lub aktualizuje Buyer na podstawie danych z faktury."""
    nip = invoice.buyer_nip
    if not nip:
        return None
    buyer, _ = Buyer.objects.get_or_create(
        company=request.user.company,
        nip=nip,
        defaults={'name': invoice.buyer_name, 'address': invoice.buyer_address},
    )
    return buyer


class OutgoingInvoiceListView(RoleRequiredMixin, View):
    min_role = 'viewer'
    template_name = 'outgoing/list.html'
    paginate_by = 50

    def get(self, request):
        base_qs = OutgoingInvoice.objects.filter(**company_filter(request.user))

        tab = request.GET.get('tab', 'drafts')
        status_filter = request.GET.get('status', '')

        if tab == 'ksef':
            qs = base_qs.filter(status__in=[
                OutgoingInvoice.STATUS_QUEUED,
                OutgoingInvoice.STATUS_SENDING,
                OutgoingInvoice.STATUS_ACCEPTED,
                OutgoingInvoice.STATUS_REJECTED,
            ])
            if status_filter:
                qs = qs.filter(status=status_filter)
        else:
            qs = base_qs.filter(status=OutgoingInvoice.STATUS_DRAFT)

        qs = qs.order_by('-created_at')
        paginator = Paginator(qs, self.paginate_by)
        page_obj = paginator.get_page(request.GET.get('page', 1))

        drafts_count = base_qs.filter(status=OutgoingInvoice.STATUS_DRAFT).count()
        ksef_count = base_qs.filter(status__in=[
            OutgoingInvoice.STATUS_QUEUED,
            OutgoingInvoice.STATUS_SENDING,
            OutgoingInvoice.STATUS_ACCEPTED,
            OutgoingInvoice.STATUS_REJECTED,
        ]).count()

        ksef_status_choices = [
            (OutgoingInvoice.STATUS_QUEUED,   'Oczekuje na wysyłkę'),
            (OutgoingInvoice.STATUS_SENDING,  'Wysyłanie'),
            (OutgoingInvoice.STATUS_ACCEPTED, 'Zaakceptowana przez KSeF'),
            (OutgoingInvoice.STATUS_REJECTED, 'Odrzucona przez KSeF'),
        ]

        return TemplateResponse(request, self.template_name, {
            'page_obj': page_obj,
            'tab': tab,
            'drafts_count': drafts_count,
            'ksef_count': ksef_count,
            'current_status': status_filter,
            'ksef_status_choices': ksef_status_choices,
        })

    def post(self, request):
        """Bulk: wyślij zaznaczone szkice do kolejki KSeF."""
        if not has_min_role(request.user, 'approver'):
            messages.error(request, 'Brak uprawnień.')
            return redirect('outgoing:list')
        ids = request.POST.getlist('invoice_ids')
        if not ids:
            messages.warning(request, 'Nie zaznaczono żadnych faktur.')
            return redirect('outgoing:list')
        queued, errors = 0, []
        qs = OutgoingInvoice.objects.filter(
            pk__in=ids,
            status=OutgoingInvoice.STATUS_DRAFT,
            **company_filter(request.user),
        )
        for inv in qs:
            if not inv.items.exists():
                errors.append(f'{inv.invoice_number}: brak pozycji')
                continue
            inv.status = OutgoingInvoice.STATUS_QUEUED
            inv.error_message = ''
            inv.save(update_fields=['status', 'error_message', 'updated_at'])
            queued += 1
        if queued:
            messages.success(request, f'Dodano {queued} faktur do kolejki wysyłki do KSeF.')
        if errors:
            messages.warning(request, 'Pominięto: ' + '; '.join(errors))
        return redirect(f"{request.build_absolute_uri(request.path)}?tab=ksef")


class OutgoingInvoiceCreateView(RoleRequiredMixin, View):
    min_role = 'accountant'
    template_name = 'outgoing/form.html'

    def get(self, request):
        if not request.user.company:
            messages.error(request, 'Twoje konto nie jest przypisane do żadnej firmy. Skontaktuj się z administratorem.')
            return redirect('outgoing:list')
        from django.utils import timezone
        initial_number = OutgoingInvoice.generate_number(request.user.company)
        form = OutgoingInvoiceForm(initial={
            'invoice_number': initial_number,
            'issue_date': timezone.now().date(),
        })
        formset = InvoiceItemFormSet()
        return TemplateResponse(request, self.template_name, {
            'form': form,
            'formset': formset,
            'title': 'Nowa faktura wychodząca',
        })

    def post(self, request):
        if not request.user.company:
            messages.error(request, 'Twoje konto nie jest przypisane do żadnej firmy. Skontaktuj się z administratorem.')
            return redirect('outgoing:list')

        form = OutgoingInvoiceForm(request.POST)
        formset = InvoiceItemFormSet(request.POST)

        if form.is_valid() and formset.is_valid():
            from django.db import IntegrityError
            invoice = form.save(commit=False)
            invoice.company = request.user.company
            invoice.created_by = request.user
            invoice.status = OutgoingInvoice.STATUS_DRAFT

            # Obsługa FK nabywcy
            buyer_id = request.POST.get('buyer_id', '').strip()
            if buyer_id:
                try:
                    invoice.buyer = Buyer.objects.get(pk=buyer_id, **company_filter(request.user))
                except Buyer.DoesNotExist:
                    pass
            elif request.POST.get('save_buyer'):
                invoice.buyer = _save_buyer_from_invoice(request, invoice)

            # Unikalne nazewnictwo przy race condition
            try:
                invoice.save()
            except IntegrityError:
                invoice.invoice_number = OutgoingInvoice.generate_number(request.user.company)
                invoice.save()

            formset.instance = invoice
            items = formset.save(commit=False)
            for i, item in enumerate(items, start=1):
                if not item.lp:
                    item.lp = i
                item.save()
            for deleted in formset.deleted_objects:
                deleted.delete()

            # Renumeruj lp sekwencyjnie po zapisie
            for idx, item in enumerate(invoice.items.order_by('lp'), start=1):
                if item.lp != idx:
                    item.lp = idx
                    item.save(update_fields=['lp'])

            messages.success(request, f'Faktura {invoice.invoice_number} została utworzona.')
            return redirect('outgoing:detail', pk=invoice.pk)

        return TemplateResponse(request, self.template_name, {
            'form': form,
            'formset': formset,
            'title': 'Nowa faktura wychodząca',
        })


class OutgoingInvoiceEditView(RoleRequiredMixin, View):
    min_role = 'accountant'
    template_name = 'outgoing/form.html'

    def _get_invoice(self, request, pk):
        inv = get_object_or_404(
            OutgoingInvoice,
            pk=pk,
            **company_filter(request.user),
        )
        if not inv.can_be_edited():
            messages.error(request, 'Tę fakturę można edytować tylko w statusie "Szkic".')
            return None, redirect('outgoing:detail', pk=pk)
        return inv, None

    def get(self, request, pk):
        inv, redir = self._get_invoice(request, pk)
        if redir:
            return redir
        form = OutgoingInvoiceForm(instance=inv)
        formset = InvoiceItemFormSet(instance=inv)
        return TemplateResponse(request, self.template_name, {
            'form': form,
            'formset': formset,
            'invoice': inv,
            'title': f'Edycja faktury {inv.invoice_number}',
        })

    def post(self, request, pk):
        inv, redir = self._get_invoice(request, pk)
        if redir:
            return redir
        form = OutgoingInvoiceForm(request.POST, instance=inv)
        formset = InvoiceItemFormSet(request.POST, instance=inv)

        if form.is_valid() and formset.is_valid():
            updated_inv = form.save(commit=False)

            # Obsługa FK nabywcy
            buyer_id = request.POST.get('buyer_id', '').strip()
            if buyer_id:
                try:
                    updated_inv.buyer = Buyer.objects.get(pk=buyer_id, **company_filter(request.user))
                except Buyer.DoesNotExist:
                    pass
            elif request.POST.get('save_buyer'):
                updated_inv.buyer = _save_buyer_from_invoice(request, updated_inv)

            updated_inv.save()
            items = formset.save(commit=False)
            for item in items:
                item.save()
            for deleted in formset.deleted_objects:
                deleted.delete()

            # Renumeruj lp
            for idx, item in enumerate(inv.items.order_by('lp'), start=1):
                if item.lp != idx:
                    item.lp = idx
                    item.save(update_fields=['lp'])

            messages.success(request, f'Faktura {inv.invoice_number} została zaktualizowana.')
            return redirect('outgoing:detail', pk=inv.pk)

        return TemplateResponse(request, self.template_name, {
            'form': form,
            'formset': formset,
            'invoice': inv,
            'title': f'Edycja faktury {inv.invoice_number}',
        })


class OutgoingInvoiceDetailView(RoleRequiredMixin, View):
    min_role = 'viewer'
    template_name = 'outgoing/detail.html'

    def get(self, request, pk):
        inv = get_object_or_404(
            OutgoingInvoice.objects.prefetch_related('items'),
            pk=pk,
            **company_filter(request.user),
        )
        return TemplateResponse(request, self.template_name, {'invoice': inv})


class OutgoingInvoiceQueueView(RoleRequiredMixin, View):
    """POST: wysyła fakturę do kolejki KSeF (draft/rejected → queued)."""
    min_role = 'approver'

    def post(self, request, pk):
        inv = get_object_or_404(
            OutgoingInvoice,
            pk=pk,
            **company_filter(request.user),
        )
        if not inv.can_be_queued():
            messages.error(request, 'Faktura nie może być wysłana w bieżącym statusie.')
            return redirect('outgoing:detail', pk=pk)

        # Sprawdź limit licencji
        try:
            lic = request.user.company.license
            if not lic.can_send_outgoing_invoice():
                limit = lic.outgoing_invoice_limit()
                messages.error(
                    request,
                    f'Osiągnięto limit planu ({limit} faktur/miesiąc). '
                    'Uaktualnij plan, aby wysyłać więcej faktur do KSeF.'
                )
                return redirect('outgoing:detail', pk=pk)
        except Exception:
            pass

        # Sprawdź konto bankowe (wymagane przy przelewie)
        company = request.user.company
        if inv.payment_form == 'przelew' and not company.bank_account:
            messages.error(
                request,
                'Brak numeru konta bankowego firmy. Uzupełnij dane firmy w ustawieniach przed wysyłką.'
            )
            return redirect('outgoing:detail', pk=pk)

        if not inv.items.exists():
            messages.error(request, 'Faktura nie ma żadnych pozycji.')
            return redirect('outgoing:detail', pk=pk)

        inv.status = OutgoingInvoice.STATUS_QUEUED
        inv.error_message = ''
        inv.save(update_fields=['status', 'error_message', 'updated_at'])

        messages.success(
            request,
            f'Faktura {inv.invoice_number} dodana do kolejki wysyłki do KSeF.'
        )
        return redirect('outgoing:detail', pk=pk)


class OutgoingInvoiceXmlDownloadView(RoleRequiredMixin, View):
    min_role = 'viewer'

    def get(self, request, pk):
        inv = get_object_or_404(
            OutgoingInvoice,
            pk=pk,
            **company_filter(request.user),
        )
        if not inv.generated_xml:
            raise Http404('Brak wygenerowanego XML dla tej faktury.')
        filename = f'faktura_{inv.invoice_number.replace("/", "_")}.xml'
        response = HttpResponse(inv.generated_xml.encode('utf-8'), content_type='application/xml')
        response['Content-Disposition'] = f'attachment; filename="{filename}"'
        return response


class OutgoingInvoiceUpoDownloadView(RoleRequiredMixin, View):
    min_role = 'viewer'

    def get(self, request, pk):
        inv = get_object_or_404(
            OutgoingInvoice,
            pk=pk,
            **company_filter(request.user),
        )
        if not inv.upo_xml:
            raise Http404('Brak UPO dla tej faktury.')
        filename = f'upo_{inv.invoice_number.replace("/", "_")}.xml'
        response = HttpResponse(inv.upo_xml.encode('utf-8'), content_type='application/xml')
        response['Content-Disposition'] = f'attachment; filename="{filename}"'
        return response


# ── Nabywcy ────────────────────────────────────────────────────────────────

class BuyerListView(RoleRequiredMixin, View):
    min_role = 'accountant'
    template_name = 'outgoing/buyer_list.html'

    def get(self, request):
        buyers = Buyer.objects.filter(**company_filter(request.user)).prefetch_related('invoices')
        q = request.GET.get('q', '').strip()
        if q:
            buyers = buyers.filter(name__icontains=q) | buyers.filter(nip__icontains=q)
        return TemplateResponse(request, self.template_name, {'buyers': buyers, 'q': q})


class BuyerUpdateView(RoleRequiredMixin, View):
    min_role = 'accountant'
    template_name = 'outgoing/buyer_form.html'

    def _get_buyer(self, request, pk):
        return get_object_or_404(Buyer, pk=pk, **company_filter(request.user))

    def get(self, request, pk):
        buyer = self._get_buyer(request, pk)
        form = BuyerForm(instance=buyer)
        return TemplateResponse(request, self.template_name, {'form': form, 'buyer': buyer})

    def post(self, request, pk):
        buyer = self._get_buyer(request, pk)
        form = BuyerForm(request.POST, instance=buyer)
        if form.is_valid():
            form.save()
            messages.success(request, f'Nabywca {buyer.name} został zaktualizowany.')
            return redirect('outgoing:buyer_list')
        return TemplateResponse(request, self.template_name, {'form': form, 'buyer': buyer})


class BuyerDeleteView(RoleRequiredMixin, View):
    min_role = 'accountant'

    def post(self, request, pk):
        buyer = get_object_or_404(Buyer, pk=pk, **company_filter(request.user))
        if buyer.invoices.exists():
            messages.error(request, f'Nie można usunąć nabywcy {buyer.name} — ma powiązane faktury.')
            return redirect('outgoing:buyer_list')
        name = buyer.name
        buyer.delete()
        messages.success(request, f'Nabywca {name} został usunięty.')
        return redirect('outgoing:buyer_list')


class BuyerSearchView(RoleRequiredMixin, View):
    """HTMX endpoint — fragment HTML z wynikami wyszukiwania nabywców."""
    min_role = 'accountant'

    def get(self, request):
        q = request.GET.get('q', '').strip()
        buyers = []
        if len(q) >= 2:
            qs = Buyer.objects.filter(**company_filter(request.user))
            buyers = list(qs.filter(name__icontains=q) | qs.filter(nip__icontains=q))[:10]
        return TemplateResponse(request, 'outgoing/buyer_search_results.html', {
            'buyers': buyers, 'q': q,
        })


class NipLookupView(RoleRequiredMixin, View):
    """AJAX endpoint — zwraca dane firmy po NIP z Białej Listy MF."""
    min_role = 'accountant'

    def get(self, request):
        nip = request.GET.get('nip', '').strip().replace('-', '').replace(' ', '')
        if len(nip) != 10 or not nip.isdigit():
            return JsonResponse({'error': 'Nieprawidłowy NIP (wymagane 10 cyfr).'}, status=400)
        data = fetch_nip_data(nip)
        if data is None:
            return JsonResponse({'error': 'Nie znaleziono firmy o podanym NIP lub błąd połączenia.'}, status=404)
        return JsonResponse(data)
