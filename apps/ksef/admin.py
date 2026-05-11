from django.contrib import admin
from .models import KSeFConfig, KSeFSyncLog


@admin.register(KSeFConfig)
class KSeFConfigAdmin(admin.ModelAdmin):
    list_display = ('nip', 'environment', 'sync_interval_hours', 'last_sync_at')
    readonly_fields = ('token_expiry', 'last_sync_at', 'last_sync_reference_number')
    exclude = ('token_encrypted',)


@admin.register(KSeFSyncLog)
class KSeFSyncLogAdmin(admin.ModelAdmin):
    list_display = ('started_at', 'status', 'invoices_fetched', 'invoices_new', 'finished_at')
    list_filter = ('status',)
    readonly_fields = ('started_at', 'finished_at', 'celery_task_id')
