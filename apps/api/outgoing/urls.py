from django.urls import path
from .views import (
    OutgoingInvoiceListView, OutgoingInvoiceCreateView,
    OutgoingInvoiceDetailView, OutgoingInvoiceUpdateView,
    OutgoingInvoiceQueueView, OutgoingInvoiceBulkQueueView,
    BuyerListView, BuyerSearchView, NipLookupView,
)

urlpatterns = [
    path('', OutgoingInvoiceListView.as_view(), name='api-outgoing-list'),
    path('new/', OutgoingInvoiceCreateView.as_view(), name='api-outgoing-create'),
    path('bulk-queue/', OutgoingInvoiceBulkQueueView.as_view(), name='api-outgoing-bulk-queue'),
    path('buyers/', BuyerListView.as_view(), name='api-outgoing-buyers'),
    path('buyers/search/', BuyerSearchView.as_view(), name='api-outgoing-buyers-search'),
    path('nip-lookup/', NipLookupView.as_view(), name='api-outgoing-nip-lookup'),
    path('<int:pk>/', OutgoingInvoiceDetailView.as_view(), name='api-outgoing-detail'),
    path('<int:pk>/edit/', OutgoingInvoiceUpdateView.as_view(), name='api-outgoing-update'),
    path('<int:pk>/queue/', OutgoingInvoiceQueueView.as_view(), name='api-outgoing-queue'),
]
