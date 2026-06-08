from django.urls import path
from . import views

app_name = 'outgoing'

urlpatterns = [
    path('', views.OutgoingInvoiceListView.as_view(), name='list'),
    path('new/', views.OutgoingInvoiceCreateView.as_view(), name='create'),
    path('<int:pk>/', views.OutgoingInvoiceDetailView.as_view(), name='detail'),
    path('<int:pk>/edit/', views.OutgoingInvoiceEditView.as_view(), name='edit'),
    path('<int:pk>/queue/', views.OutgoingInvoiceQueueView.as_view(), name='queue'),
    path('<int:pk>/xml/', views.OutgoingInvoiceXmlDownloadView.as_view(), name='xml'),
    path('<int:pk>/upo/', views.OutgoingInvoiceUpoDownloadView.as_view(), name='upo'),

    # Nabywcy
    path('buyers/', views.BuyerListView.as_view(), name='buyer_list'),
    path('buyers/<int:pk>/edit/', views.BuyerUpdateView.as_view(), name='buyer_edit'),
    path('buyers/<int:pk>/delete/', views.BuyerDeleteView.as_view(), name='buyer_delete'),

    # API / HTMX endpointy
    path('api/buyers/search/', views.BuyerSearchView.as_view(), name='buyer_search'),
    path('api/nip-lookup/', views.NipLookupView.as_view(), name='nip_lookup'),
]
