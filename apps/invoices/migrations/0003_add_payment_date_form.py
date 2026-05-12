from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('invoices', '0002_add_invoice_type_description'),
    ]

    operations = [
        migrations.AddField(
            model_name='invoice',
            name='payment_date',
            field=models.DateField(blank=True, null=True, verbose_name='Data zapłaty (z XML)'),
        ),
        migrations.AddField(
            model_name='invoice',
            name='payment_form',
            field=models.CharField(blank=True, max_length=30, verbose_name='Forma płatności'),
        ),
    ]
