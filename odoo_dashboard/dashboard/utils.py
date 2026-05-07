import os
import random
import string
import socket

def get_server_ip():
    try:
        # Intenta obtener la IP de la interfaz principal
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return "127.0.0.1"

def generate_password(length=16):
    chars = string.ascii_letters + string.digits
    return ''.join(random.choice(chars) for _ in range(length))

def create_project_structure(project_path, versions):
    subdirs = [
        'logs',
        *[f'postgres_v{v}' for v in versions],
        *[f'filestore_v{v}' for v in versions],
        *[f'custom_v{v}' for v in versions],
        *[f'odoo-config_v{v}' for v in versions],
        *[f'python-packages_v{v}' for v in versions],
    ]
    for sd in subdirs:
        os.makedirs(os.path.join(project_path, sd), exist_ok=True)

def write_env_file(project_path, data):
    env_path = os.path.join(project_path, '.env')
    with open(env_path, 'w') as f:
        for key, value in data.items():
            f.write(f"{key}={value}\n")

def write_odoo_conf(project_path, versions, admin_pass, pg_user, pg_pass, project_name):
    for ver in versions:
        conf_dir = os.path.join(project_path, f'odoo-config_v{ver}')
        conf_path = os.path.join(conf_dir, 'odoo.conf')
        content = f"""[options]
admin_passwd = {admin_pass}
db_host = {project_name}_db{ver}
db_user = {pg_user}
db_password = {pg_pass}
db_port = 5432
addons_path = /usr/lib/python3/dist-packages/odoo/addons,/mnt/extra-addons
"""
        with open(conf_path, 'w') as f:
            f.write(content)

def write_docker_compose(project_path, project_name, versions, pg_user, pg_pass, deploy_mode, domain):
    compose_path = os.path.join(project_path, 'docker-compose.yml')
    
    services = ""
    for ver in versions:
        services += f"""
  {project_name}_db{ver}:
    image: postgres:15
    container_name: {project_name}_db{ver}
    environment:
      - POSTGRES_USER={pg_user}
      - POSTGRES_PASSWORD={pg_pass}
    volumes:
      - ./postgres_v{ver}:/var/lib/postgresql/data
    networks:
      - odoo-global-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U {pg_user}"]
      interval: 10s
      timeout: 5s
      retries: 5

  {project_name}_odoo{ver}:
    image: odoo:{ver}
    container_name: {project_name}_odoo{ver}
    depends_on:
      {project_name}_db{ver}:
        condition: service_healthy
    volumes:
      - ./odoo-config_v{ver}/odoo.conf:/etc/odoo/odoo.conf
      - ./filestore_v{ver}:/var/lib/odoo
      - ./custom_v{ver}:/mnt/extra-addons
      - ./python-packages_v{ver}:/opt/python-packages
    environment:
      - HOST={project_name}_db{ver}
      - USER={pg_user}
      - PASSWORD={pg_pass}
      - PYTHONPATH=/opt/python-packages:$PYTHONPATH
    networks:
      - odoo-global-network
"""
        if deploy_mode == 'local':
            services += f"    ports:\n      - \"{8069 if ver == '19' else 8079}:8069\"\n"
        else:
            services += "    expose:\n      - \"8069\"\n"

    content = f"""version: '3.8'
services:
{services}
networks:
  odoo-global-network:
    external: true
"""
    with open(compose_path, 'w') as f:
        f.write(content)
