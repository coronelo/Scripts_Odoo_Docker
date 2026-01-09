import subprocess
import os

NGINX_SITES_AVAILABLE = "/etc/nginx/sites-available"
NGINX_SITES_ENABLED = "/etc/nginx/sites-enabled"

def crear_config_nginx(dominio, puerto_odoo):
    config = f"""
server {{
    listen 80;
    server_name {dominio};

    location / {{
        proxy_pass http://127.0.0.1:{puerto_odoo};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }}
}}
"""
    config_path = os.path.join(NGINX_SITES_AVAILABLE, dominio)
    enabled_path = os.path.join(NGINX_SITES_ENABLED, dominio)

    # Escribir el archivo usando sudo tee
    print(f"🔑 Se solicitará la clave sudo para crear la configuración en {config_path}")
    proc = subprocess.run(
        ["sudo", "tee", config_path],
        input=config.encode(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    if proc.returncode != 0:
        print(f"❌ Error creando el archivo Nginx: {proc.stderr.decode()}")
        return

    # Crear el symlink usando sudo
    subprocess.run(["sudo", "ln", "-sf", config_path, enabled_path])

    print(f"✅ Configuración Nginx creada y activada para {dominio}")