from django.urls import path, include

urlpatterns = [
    path('auth/', include('apps.api.auth.urls')),
    path('invoices/', include('apps.api.invoices.urls')),
    path('outgoing/', include('apps.api.outgoing.urls')),
    path('payments/', include('apps.api.payments.urls')),
]
