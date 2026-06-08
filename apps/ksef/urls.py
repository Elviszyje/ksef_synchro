from django.urls import path
from . import views

app_name = 'ksef'

urlpatterns = [
    path('config/', views.KSeFConfigView.as_view(), name='config'),
    path('config/company/<int:company_pk>/', views.KSeFConfigCompanyView.as_view(), name='config_company'),
    path('sync/', views.KSeFManualSyncView.as_view(), name='manual_sync'),
    path('logs/', views.KSeFSyncLogListView.as_view(), name='logs'),
    path('test-notification/', views.TestNotificationView.as_view(), name='test_notification'),
    path('sync/status/', views.KSeFSyncStatusView.as_view(), name='sync_status'),
    path('sync/cancel/', views.KSeFSyncCancelView.as_view(), name='sync_cancel'),
]
