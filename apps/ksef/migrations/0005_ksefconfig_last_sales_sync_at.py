from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('ksef', '0004_add_company_fk'),
    ]

    operations = [
        migrations.AddField(
            model_name='ksefconfig',
            name='last_sales_sync_at',
            field=models.DateTimeField(
                blank=True, null=True, verbose_name='Ostatnia synchronizacja faktur sprzedażowych',
            ),
        ),
    ]
