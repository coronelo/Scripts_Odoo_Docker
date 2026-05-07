from django.urls import path
from . import views

from django.contrib.auth import views as auth_views

urlpatterns = [
    path('login/', auth_views.LoginView.as_view(template_name='dashboard/login.html'), name='login'),
    path('logout/', auth_views.LogoutView.as_view(), name='logout'),
    path('', views.index, name='index'),
    path('projects/', views.projects, name='projects'),
    path('projects/<int:pk>/', views.project_detail, name='project_detail'),
    path('projects/<int:pk>/backup/', views.trigger_backup, name='trigger_backup'),
    path('logs/', views.logs_view, name='logs_view'),
    path('logs/<str:container_id>/', views.project_logs, name='project_logs'),
    path('settings/', views.settings, name='settings'),
    path('create/', views.create_project, name='create_project'),
    path('delete/<int:pk>/', views.delete_project, name='delete_project'),
    path('toggle/<str:project_name>/<str:action>/', views.toggle_project, name='toggle_project'),
]
