from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        ('accounts', '0005_backfill_company_licenses'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='OutgoingInvoice',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('invoice_number', models.CharField(max_length=64, verbose_name='Numer faktury')),
                ('issue_date', models.DateField(verbose_name='Data wystawienia')),
                ('delivery_date', models.DateField(blank=True, null=True, verbose_name='Data dostawy/wykonania')),
                ('payment_due_date', models.DateField(verbose_name='Termin płatności')),
                ('payment_form', models.CharField(
                    choices=[('przelew', 'Przelew'), ('gotowka', 'Gotówka')],
                    default='przelew', max_length=20, verbose_name='Forma płatności')),
                ('currency', models.CharField(default='PLN', max_length=3, verbose_name='Waluta')),
                ('buyer_nip', models.CharField(max_length=10, verbose_name='NIP nabywcy')),
                ('buyer_name', models.CharField(max_length=255, verbose_name='Nazwa nabywcy')),
                ('buyer_address', models.TextField(verbose_name='Adres nabywcy')),
                ('notes', models.TextField(blank=True, verbose_name='Uwagi')),
                ('status', models.CharField(
                    choices=[
                        ('draft', 'Szkic'),
                        ('queued', 'Oczekuje na wysyłkę'),
                        ('sending', 'Wysyłanie'),
                        ('accepted', 'Zaakceptowana przez KSeF'),
                        ('rejected', 'Odrzucona przez KSeF'),
                    ],
                    db_index=True, default='draft', max_length=20, verbose_name='Status')),
                ('ksef_submission_reference', models.CharField(blank=True, max_length=255, verbose_name='Referencja wysyłki KSeF')),
                ('ksef_reference_number', models.CharField(blank=True, max_length=64, verbose_name='Numer referencyjny KSeF')),
                ('generated_xml', models.TextField(blank=True, verbose_name='Wygenerowany XML')),
                ('upo_xml', models.TextField(blank=True, verbose_name='UPO XML')),
                ('error_message', models.TextField(blank=True, verbose_name='Błąd')),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('company', models.ForeignKey(
                    db_index=True, on_delete=django.db.models.deletion.CASCADE,
                    related_name='outgoing_invoices', to='accounts.company', verbose_name='Firma')),
                ('created_by', models.ForeignKey(
                    null=True, on_delete=django.db.models.deletion.SET_NULL,
                    related_name='created_outgoing_invoices', to=settings.AUTH_USER_MODEL,
                    verbose_name='Utworzona przez')),
            ],
            options={
                'verbose_name': 'Faktura wychodząca',
                'verbose_name_plural': 'Faktury wychodzące',
                'ordering': ['-created_at'],
            },
        ),
        migrations.CreateModel(
            name='InvoiceItem',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('lp', models.PositiveSmallIntegerField(verbose_name='Lp.')),
                ('name', models.CharField(max_length=255, verbose_name='Nazwa towaru/usługi')),
                ('unit', models.CharField(default='szt.', max_length=30, verbose_name='Jednostka')),
                ('quantity', models.DecimalField(decimal_places=3, max_digits=10, verbose_name='Ilość')),
                ('unit_price_net', models.DecimalField(decimal_places=2, max_digits=15, verbose_name='Cena jedn. netto')),
                ('vat_rate', models.CharField(
                    choices=[
                        ('23', '23%'), ('8', '8%'), ('5', '5%'), ('0', '0%'),
                        ('zw', 'ZW (zwolniony)'), ('np', 'NP (nie podlega)'),
                    ],
                    default='23', max_length=5, verbose_name='Stawka VAT')),
                ('amount_net', models.DecimalField(decimal_places=2, max_digits=15, verbose_name='Wartość netto')),
                ('amount_vat', models.DecimalField(decimal_places=2, max_digits=15, verbose_name='Kwota VAT')),
                ('amount_gross', models.DecimalField(decimal_places=2, max_digits=15, verbose_name='Wartość brutto')),
                ('invoice', models.ForeignKey(
                    on_delete=django.db.models.deletion.CASCADE, related_name='items',
                    to='outgoing.outgoinginvoice', verbose_name='Faktura')),
            ],
            options={
                'verbose_name': 'Pozycja faktury',
                'verbose_name_plural': 'Pozycje faktury',
                'ordering': ['lp'],
            },
        ),
        migrations.AddConstraint(
            model_name='outgoinginvoice',
            constraint=models.UniqueConstraint(
                fields=['company', 'invoice_number'],
                name='unique_outgoing_invoice_number_per_company',
            ),
        ),
    ]
