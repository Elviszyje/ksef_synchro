from django.urls import path
from . import views

app_name = 'invoices'

urlpatterns = [
    path('', views.InvoiceListView.as_view(), name='list'),
    path('<int:pk>/', views.InvoiceDetailView.as_view(), name='detail'),
    path('<int:pk>/status/', views.InvoiceStatusChangeView.as_view(), name='status_change'),
    path('<int:pk>/quick-status/', views.InvoiceQuickStatusView.as_view(), name='quick_status'),
    path('<int:pk>/notes/', views.InvoiceNoteUpdateView.as_view(), name='note_update'),
    path('bulk-status/', views.InvoiceBulkStatusView.as_view(), name='bulk_status'),
    path('<int:pk>/xml/', views.InvoiceXmlDownloadView.as_view(), name='xml_download'),
    path('export/', views.InvoiceExportView.as_view(), name='export'),
]
