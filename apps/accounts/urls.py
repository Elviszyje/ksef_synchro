from django.urls import path
from . import views

app_name = 'accounts'

urlpatterns = [
    path('login/', views.CustomLoginView.as_view(), name='login'),
    path('logout/', views.CustomLogoutView.as_view(), name='logout'),
    path('users/', views.UserListView.as_view(), name='user_list'),
    path('users/create/', views.UserCreateView.as_view(), name='user_create'),
    path('users/<int:pk>/edit/', views.UserUpdateView.as_view(), name='user_edit'),
    path('users/<int:pk>/delete/', views.UserDeleteView.as_view(), name='user_delete'),
    path('users/<int:pk>/set-password/', views.UserSetPasswordView.as_view(), name='user_set_password'),
    path('companies/', views.CompanyListView.as_view(), name='company_list'),
    path('companies/create/', views.CompanyCreateView.as_view(), name='company_create'),
    path('companies/<int:pk>/edit/', views.CompanyUpdateView.as_view(), name='company_edit'),
    path('companies/<int:company_pk>/users/', views.CompanyUsersView.as_view(), name='company_users'),
    path('companies/<int:company_pk>/users/create/', views.UserCreateView.as_view(), name='company_user_create'),
    path('companies/<int:company_pk>/users/<int:pk>/edit/', views.UserUpdateView.as_view(), name='company_user_edit'),
    path('companies/<int:company_pk>/license/', views.LicenseUpdateView.as_view(), name='license_edit'),
    path('licenses/webhook/', views.StoreWebhookView.as_view(), name='store_webhook'),
    path('register/', views.RegisterView.as_view(), name='register'),
]
