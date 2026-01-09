import os
from pathlib import Path

class Config:
    BASE_DIR = Path(__file__).parent.parent
    ODOO_VERSIONS = ["18.0", "19.0"]
    
    ODOO_IMAGES = {
        "18.0": "odoo:18.0",
        "19.0": "odoo:19.0"
    }
    
    POSTGRES_IMAGE = "pgvector/pgvector:pg15"
    NGINX_IMAGE = "nginx:alpine"
    
    # PostgreSQL compartido
    POSTGRES_USER = 'odoo_admin'
    POSTGRES_CONTAINER = "odoo-postgres"
    POSTGRES_HOST_PORT = 5432
    NETWORK_NAME = "odoo-network"
    # Rutas estandar
    ODOO_HOME = Path("/home/odoo")
    #AUTO_CREATE_DATABASE = False    

    @staticmethod
    def get_addons_paths(version):
        """Rutas: /home/odoo/enterpriseV180 y /home/odoo/custom_addonsV180"""
        version_suffix = version.replace(".", "")
        
        enterprise_path = Config.ODOO_HOME / f"enterpriseV{version_suffix}"
        custom_path = Config.ODOO_HOME / f"custom_addonsV{version_suffix}"
        
        return str(custom_path), str(enterprise_path)
    
    @staticmethod
    def get_odoo_image(version):
        return Config.ODOO_IMAGES.get(version, "odoo:19.0")
    
    @staticmethod
    def generate_credentials(project_name):
        """Genera credenciales únicas para el proyecto"""
        import secrets
        import string
        
        alphabet = string.ascii_letters + string.digits
        db_password = ''.join(secrets.choice(alphabet) for _ in range(12))
        admin_password = ''.join(secrets.choice(alphabet + "!@#$%^&*") for _ in range(16))
        master_password = ''.join(secrets.choice(alphabet + "!@#$%^&*") for _ in range(20))
        
        return {
            'db_user': 'odoo_admin',  # <-- SIEMPRE odoo_admin
            'db_password': db_password,
            'admin_password': admin_password,
            'master_password': master_password
        }


config = Config()

