from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('ksef', '0002_notificationconfig_pendingnotification_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='ksefsynclog',
            name='cancel_requested',
            field=models.BooleanField(default=False, verbose_name='Żądanie anulowania'),
        ),
        migrations.AddField(
            model_name='ksefsynclog',
            name='current_stage',
            field=models.CharField(blank=True, max_length=120, verbose_name='Etap'),
        ),
    ]
