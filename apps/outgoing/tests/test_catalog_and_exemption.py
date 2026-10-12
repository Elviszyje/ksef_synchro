from decimal import Decimal
from types import SimpleNamespace

from django.test import SimpleTestCase, TestCase

from apps.accounts.models import Company
from apps.api.outgoing.serializers import OutgoingInvoiceWriteSerializer
from apps.outgoing.forms import InvoiceItemFormSet, OutgoingInvoiceForm
from apps.outgoing.models import CatalogItem, InvoiceItem


def _post(items, basis=''):
    data = {
        'invoice_number': 'FV/2026/0001', 'issue_date': '2026-10-12', 'payment_due_date': '2026-10-26',
        'payment_form': 'przelew', 'currency': 'PLN',
        'buyer_nip': '6260181591', 'buyer_name': 'Klient', 'buyer_address': 'ul. Kupiecka 1',
        'notes': '', 'vat_exemption_type': 'ustawa', 'vat_exemption_basis': basis,
        'items-TOTAL_FORMS': str(len(items)), 'items-INITIAL_FORMS': '0',
        'items-MIN_NUM_FORMS': '1', 'items-MAX_NUM_FORMS': '1000',
    }
    for i, (rate, delete) in enumerate(items):
        data.update({f'items-{i}-name': f'Poz {i}', f'items-{i}-unit': 'szt.', f'items-{i}-quantity': '1',
                     f'items-{i}-unit_price_net': '100', f'items-{i}-vat_rate': rate})
        if delete:
            data[f'items-{i}-DELETE'] = 'on'
    return data


class ExemptionValidationTests(SimpleTestCase):
    def _validate(self, items, basis=''):
        data = _post(items, basis)
        form, formset = OutgoingInvoiceForm(data), InvoiceItemFormSet(data)
        self.assertTrue(form.is_valid(), form.errors)
        self.assertTrue(formset.is_valid(), formset.errors)
        return form.validate_exemption(formset), form

    def test_exempt_item_requires_basis(self):
        ok, form = self._validate([('zw', False)])
        self.assertFalse(ok)
        self.assertIn('vat_exemption_basis', form.errors)

    def test_exempt_item_with_basis(self):
        ok, _ = self._validate([('zw', False)], basis='art. 113 ust. 1 ustawy o VAT')
        self.assertTrue(ok)

    def test_deleted_exempt_item_is_ignored(self):
        ok, _ = self._validate([('23', False), ('zw', True)])
        self.assertTrue(ok)

    def test_no_exempt_items(self):
        ok, _ = self._validate([('23', False), ('8', False)])
        self.assertTrue(ok)

    def test_api_serializer_requires_basis(self):
        data = {k: v for k, v in _post([]).items() if not k.startswith('items-')}
        data['items'] = [{'lp': 1, 'name': 'Szkolenie', 'unit': 'h', 'quantity': '1', 'unit_price_net': '100', 'vat_rate': 'zw'}]
        serializer = OutgoingInvoiceWriteSerializer(data=data)
        self.assertFalse(serializer.is_valid())
        self.assertIn('vat_exemption_basis', serializer.errors)
        data['vat_exemption_basis'] = 'art. 113 ust. 1 ustawy o VAT'
        self.assertTrue(OutgoingInvoiceWriteSerializer(data=data).is_valid())


class CatalogRememberTests(TestCase):
    def setUp(self):
        self.company = Company.objects.create(name='Firma', nip='1111111111')
        self.other = Company.objects.create(name='Inna', nip='6260181591')

    def _items(self, *specs):
        return [InvoiceItem(name=n, unit=u, unit_price_net=Decimal(p), vat_rate=r) for n, u, p, r in specs]

    def test_new_items_are_saved(self):
        CatalogItem.remember(self.company, self._items(('Konsultacje', 'h', '200.00', '23'), ('  ', 'szt.', '1', '23')))
        item = CatalogItem.objects.get(company=self.company)
        self.assertEqual((item.name, item.unit, item.unit_price_net, item.vat_rate, item.use_count),
                         ('Konsultacje', 'h', Decimal('200.00'), '23', 1))

    def test_reuse_updates_price_and_counter(self):
        CatalogItem.remember(self.company, self._items(('Konsultacje', 'h', '200.00', '23')))
        CatalogItem.remember(self.company, self._items(('Konsultacje', 'h', '250.00', '8')))
        item = CatalogItem.objects.get(company=self.company, name='Konsultacje')
        self.assertEqual((item.unit_price_net, item.vat_rate, item.use_count), (Decimal('250.00'), '8', 2))

    def test_same_name_other_unit_is_separate(self):
        CatalogItem.remember(self.company, self._items(('Papier', 'ryza', '20', '23'), ('Papier', 'karton', '90', '23')))
        self.assertEqual(CatalogItem.objects.filter(company=self.company).count(), 2)

    def test_catalog_is_per_company(self):
        CatalogItem.remember(self.company, self._items(('Konsultacje', 'h', '200', '23')))
        CatalogItem.remember(self.other, self._items(('Konsultacje', 'h', '300', '23')))
        self.assertEqual(CatalogItem.objects.get(company=self.other).unit_price_net, Decimal('300'))
        self.assertEqual(CatalogItem.objects.get(company=self.company).use_count, 1)


class InvoiceFormViewTests(TestCase):
    """Przebieg w przeglądarce: formularz → zapis → katalog."""

    def setUp(self):
        from django.contrib.auth import get_user_model
        self.company = Company.objects.create(name='Firma', nip='1111111111', bank_account='61109010140000071219812874')
        self.user = get_user_model().objects.create_user(
            username='ksiegowa', password='x', role='accountant', company=self.company)
        self.client.force_login(self.user)

    def test_create_with_exemption_and_reuse_catalog(self):
        from django.urls import reverse
        from apps.outgoing.models import OutgoingInvoice

        page = self.client.get(reverse('outgoing:create'))
        self.assertEqual(page.status_code, 200)
        self.assertContains(page, 'id="exemption-card"')
        self.assertContains(page, 'list="catalog-names"')

        missing = self.client.post(reverse('outgoing:create'), _post([('zw', False)]))
        self.assertEqual(missing.status_code, 200)
        self.assertContains(missing, 'wymagają podania podstawy prawnej')
        self.assertFalse(OutgoingInvoice.objects.exists())

        saved = self.client.post(reverse('outgoing:create'), _post([('zw', False)], basis='art. 113 ust. 1 ustawy o VAT'))
        self.assertEqual(saved.status_code, 302)
        invoice = OutgoingInvoice.objects.get()
        self.assertEqual(invoice.vat_exemption_basis, 'art. 113 ust. 1 ustawy o VAT')
        self.assertTrue(CatalogItem.objects.filter(company=self.company, name='Poz 0').exists())

        detail = self.client.get(reverse('outgoing:detail', args=[invoice.pk]))
        self.assertContains(detail, 'art. 113 ust. 1 ustawy o VAT')

        page = self.client.get(reverse('outgoing:create'))
        self.assertContains(page, '<option value="Poz 0">')
        self.assertContains(page, '<option value="art. 113 ust. 1 ustawy o VAT">')

        catalog = self.client.get(reverse('outgoing:catalog_list'))
        self.assertContains(catalog, 'Poz 0')
        item = CatalogItem.objects.get(company=self.company)
        self.assertEqual(self.client.get(reverse('outgoing:catalog_edit', args=[item.pk])).status_code, 200)
        self.client.post(reverse('outgoing:catalog_delete', args=[item.pk]))
        self.assertFalse(CatalogItem.objects.exists())
        self.assertEqual(invoice.items.count(), 1)

    def test_catalog_of_other_company_is_hidden(self):
        from django.urls import reverse
        other = Company.objects.create(name='Inna', nip='6260181591')
        foreign = CatalogItem.objects.create(company=other, name='Cudze', unit='szt.', unit_price_net=1, vat_rate='23')
        self.assertNotContains(self.client.get(reverse('outgoing:catalog_list')), 'Cudze')
        self.assertEqual(self.client.get(reverse('outgoing:catalog_edit', args=[foreign.pk])).status_code, 404)
