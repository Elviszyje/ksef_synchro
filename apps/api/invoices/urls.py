from django.urls import path
from .views import (
    InvoiceListView, InvoiceDetailView,
    InvoiceStatusChangeView, InvoiceBulkStatusView,
    InvoiceNoteUpdateView, InvoiceDashboardView,
)

urlpatterns = [
    path('', InvoiceListView.as_view(), name='api-invoice-list'),
    path('dashboard/', InvoiceDashboardView.as_view(), name='api-invoice-dashboard'),
    path('bulk-status/', InvoiceBulkStatusView.as_view(), name='api-invoice-bulk-status'),
    path('<int:pk>/', InvoiceDetailView.as_view(), name='api-invoice-detail'),
    path('<int:pk>/status/', InvoiceStatusChangeView.as_view(), name='api-invoice-status'),
    path('<int:pk>/notes/', InvoiceNoteUpdateView.as_view(), name='api-invoice-notes'),
]
