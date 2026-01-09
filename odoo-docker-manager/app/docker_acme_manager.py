from app.docker_client import DockerClient
from config.settings import Config

def asegurar_certbot():
    docker_client = DockerClient()
    certbot_name = "certbot"
    certbot_image = "certbot/certbot:latest"
    if not docker_client.container_exists(certbot_name):
        print("🔄 Levantando contenedor Certbot...")
        config = {
            'name': certbot_name,
            'image': certbot_image,
            'volumes': {
                '/etc/letsencrypt': {'bind': '/etc/letsencrypt', 'mode': 'rw'},
                '/var/lib/letsencrypt': {'bind': '/var/lib/letsencrypt', 'mode': 'rw'},
            }
        }
        docker_client.create_container(config, Config.NETWORK_NAME)
        print("✅ Contenedor Certbot levantado")
    else:
        print("✅ Contenedor Certbot ya está corriendo")