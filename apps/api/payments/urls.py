from django.urls import path
from .views import (
    AcceptedInvoicesForPaymentView, PaymentFileListView,
    PaymentFileCreateView, PaymentFileDownloadView,
    CompanyBankAccountsView, CompanyBankAccountDetailView,
)

urlpatterns = [
    path('', PaymentFileListView.as_view(), name='api-payment-list'),
    path('accepted-invoices/', AcceptedInvoicesForPaymentView.as_view(), name='api-payment-accepted'),
    path('generate/', PaymentFileCreateView.as_view(), name='api-payment-generate'),
    path('bank-accounts/', CompanyBankAccountsView.as_view(), name='api-payment-bank-accounts'),
    path('bank-accounts/<int:pk>/', CompanyBankAccountDetailView.as_view(), name='api-payment-bank-account-detail'),
    path('<int:pk>/download/', PaymentFileDownloadView.as_view(), name='api-payment-download'),
]
