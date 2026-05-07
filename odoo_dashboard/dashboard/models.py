from django.db import models

class Project(models.Model):
    name = models.CharField(max_length=100, unique=True)
    path = models.CharField(max_length=255)
    domain = models.CharField(max_length=255, blank=True, null=True)
    deploy_mode = models.CharField(max_length=20, choices=[('local', 'Local'), ('online', 'Online')], default='local')
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.name
