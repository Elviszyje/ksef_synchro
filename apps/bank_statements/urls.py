from django.urls import path
from . import views

app_name = 'bank_statements'

urlpatterns = [
    path('', views.BankStatementListView.as_view(), name='list'),
    path('upload/', views.BankStatementUploadView.as_view(), name='upload'),
    path('<int:pk>/review/', views.BankStatementReviewView.as_view(), name='review'),
    path('<int:pk>/confirm/', views.BankStatementConfirmView.as_view(), name='confirm'),
    path('<int:pk>/match/<int:match_pk>/toggle/', views.ToggleMatchView.as_view(), name='toggle_match'),
    path('<int:pk>/delete/', views.BankStatementDeleteView.as_view(), name='delete'),
]
