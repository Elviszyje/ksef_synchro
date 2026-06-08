from django.urls import path
from .views import (
    BankStatementListCreateView,
    BankStatementDetailView,
    RunMatcherView,
    ToggleMatchView,
    ConfirmStatementView,
)

urlpatterns = [
    path('', BankStatementListCreateView.as_view(), name='api-bank-statement-list'),
    path('<int:pk>/', BankStatementDetailView.as_view(), name='api-bank-statement-detail'),
    path('<int:pk>/run-matcher/', RunMatcherView.as_view(), name='api-bank-statement-run-matcher'),
    path('<int:pk>/matches/<int:match_pk>/toggle/', ToggleMatchView.as_view(), name='api-bank-statement-toggle-match'),
    path('<int:pk>/confirm/', ConfirmStatementView.as_view(), name='api-bank-statement-confirm'),
]
