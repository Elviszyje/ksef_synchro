from django.contrib import admin
from django.urls import path, include
from apps.accounts.views import landing

urlpatterns = [
    path('api/v1/', include('apps.api.urls')),
    path('admin/', admin.site.urls),
    path('accounts/', include('apps.accounts.urls')),
    path('invoices/', include('apps.invoices.urls')),
    path('ksef/', include('apps.ksef.urls')),
    path('payments/', include('apps.payments.urls')),
    path('bank-statements/', include('apps.bank_statements.urls')),
    path('outgoing/', include('apps.outgoing.urls')),
    path('audit/', include('core.urls')),
    path('', landing, name='landing'),
]
