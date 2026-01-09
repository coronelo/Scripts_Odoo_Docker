from app.docker_client import DockerClient
from config.settings import Config
import subprocess

NGINX_NAME = "nginx-proxy"
NGINX_IMAGE = "nginx:latest"

def asegurar_nginx():
    docker_client = DockerClient()
    if not docker_client.container_exists(NGINX_NAME):
        print("🔄 Levantando contenedor Nginx...")
        config = {
            'name': NGINX_NAME,
            'image': NGINX_IMAGE,
            'ports': {'80/tcp': 80, '443/tcp': 443},
            'volumes': {
                '/etc/nginx/conf.d': {'bind': '/etc/nginx/conf.d', 'mode': 'rw'},
                '/etc/nginx/sites-available': {'bind': '/etc/nginx/sites-available', 'mode': 'rw'},
                '/etc/nginx/sites-enabled': {'bind': '/etc/nginx/sites-enabled', 'mode': 'rw'},
                '/etc/letsencrypt': {'bind': '/etc/letsencrypt', 'mode': 'rw'},
                '/var/www/html': {'bind': '/var/www/html', 'mode': 'rw'},  # <-- ¡Asegúrate de que esta línea está!
            }
        }
        docker_client.create_container(config, Config.NETWORK_NAME)
        print("✅ Contenedor Nginx levantado")
    else:
        print("✅ Contenedor Nginx ya está corriendo")

def recargar_nginx_docker():
    print("🔄 Recargando configuración de Nginx en el contenedor...")
    result = subprocess.run(["docker", "exec", NGINX_NAME, "nginx", "-s", "reload"], capture_output=True)
    if result.returncode == 0:
        print("✅ Nginx recargado correctamente en el contenedor")
    else:
        print(f"❌ Error al recargar Nginx: {result.stderr.decode()}")