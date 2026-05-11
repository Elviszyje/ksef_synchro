from django.contrib import admin
from django.urls import path, include
from django.views.generic import RedirectView

urlpatterns = [
    path('admin/', admin.site.urls),
    path('accounts/', include('apps.accounts.urls')),
    path('invoices/', include('apps.invoices.urls')),
    path('ksef/', include('apps.ksef.urls')),
    path('payments/', include('apps.payments.urls')),
    path('bank-statements/', include('apps.bank_statements.urls')),
    path('audit/', include('core.urls')),
    path('', RedirectView.as_view(url='/invoices/', permanent=False)),
]
