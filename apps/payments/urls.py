from django.urls import path
from . import views

app_name = 'payments'

urlpatterns = [
    path('', views.PaymentFileListView.as_view(), name='list'),
    path('create/', views.PaymentFileCreateView.as_view(), name='create'),
    path('<int:pk>/', views.PaymentFileDetailView.as_view(), name='detail'),
    path('<int:pk>/download/', views.PaymentFileDownloadView.as_view(), name='download'),
    path('<int:pk>/reset/', views.PaymentFileResetView.as_view(), name='reset'),
]
