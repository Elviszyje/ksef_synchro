from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('outgoing', '0003_vat_exemption_and_catalog'),
    ]

    operations = [
        migrations.AlterField(
            model_name='outgoinginvoice',
            name='status',
            field=models.CharField(
                choices=[
                    ('draft', 'Szkic'),
                    ('queued', 'Oczekuje na wysyłkę'),
                    ('sending', 'Wysyłanie'),
                    ('accepted', 'Zaakceptowana przez KSeF'),
                    ('rejected', 'Odrzucona przez KSeF'),
                    ('imported', 'Zaimportowana z KSeF'),
                ],
                db_index=True, default='draft', max_length=20, verbose_name='Status',
            ),
        ),
    ]
