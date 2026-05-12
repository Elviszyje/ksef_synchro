from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('invoices', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='invoice',
            name='invoice_type',
            field=models.CharField(blank=True, max_length=20, verbose_name='Rodzaj faktury'),
        ),
        migrations.AddField(
            model_name='invoice',
            name='description',
            field=models.TextField(blank=True, verbose_name='Opis przedmiotu'),
        ),
    ]
