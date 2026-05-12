"""
Uzupełnia pola invoice_type i description z zapisanego raw_xml
dla faktur, które zostały zsynchronizowane przed dodaniem tych pól.

Użycie:
    python manage.py backfill_xml_fields
    python manage.py backfill_xml_fields --all   # nadpisz też już uzupełnione
"""
from django.core.management.base import BaseCommand


class Command(BaseCommand):
    help = 'Uzupełnia invoice_type i description z zapisanego raw_xml'

    def add_arguments(self, parser):
        parser.add_argument(
            '--all', action='store_true',
            help='Przetwarza wszystkie faktury (nie tylko z pustym description)',
        )

    def handle(self, *args, **options):
        from apps.invoices.models import Invoice
        from apps.ksef.parser import FA2Parser

        parser = FA2Parser()
        qs = Invoice.objects.exclude(raw_xml='')
        if not options['all']:
            qs = qs.filter(description='')

        total = qs.count()
        self.stdout.write(f'Faktury do przetworzenia: {total}')

        updated = 0
        errors = 0
        for inv in qs.iterator(chunk_size=100):
            try:
                parsed = parser.parse(inv.raw_xml.encode('utf-8'), inv.ksef_reference_number)
                fields = {}
                if parsed.invoice_type:
                    fields['invoice_type'] = parsed.invoice_type
                if parsed.description:
                    fields['description'] = parsed.description
                if parsed.seller_name and parsed.seller_name not in ('Nieznany sprzedawca',):
                    fields['seller_name'] = parsed.seller_name
                if fields:
                    Invoice.objects.filter(pk=inv.pk).update(**fields)
                    updated += 1
            except Exception as exc:
                self.stderr.write(f'Błąd {inv.ksef_reference_number}: {exc}')
                errors += 1

        self.stdout.write(self.style.SUCCESS(
            f'Zakończono: {updated} zaktualizowanych, {errors} błędów.'
        ))
