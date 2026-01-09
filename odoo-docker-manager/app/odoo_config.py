from config.settings import Config

class OdooConfig:
    def __init__(self, version, name, port=8069, admin_db_password=None, master_password=None):
        self.version = version
        self.name = name
        self.port = port
        self.credentials = {
            'db_name': name,
            'db_user': 'odoo_admin',
            'db_password': admin_db_password if admin_db_password else 'admin',
            'master_password': master_password if master_password else 'admin'
        }
    
    def get_container_config(self):
        return {
            'image': Config.get_odoo_image(self.version),
            'name': self.name,
            'ports': {f'8069/tcp': self.port},
            'environment': {
                'DB_USER': self.credentials['db_user'],
                'DB_PASSWORD': self.credentials['db_password'],
                'DB_HOST': Config.POSTGRES_CONTAINER,
                'HOST': Config.POSTGRES_CONTAINER,
                'PGHOST': Config.POSTGRES_CONTAINER,
            },
            # ...volúmenes, etc...
        }

def obtener_addons_path():
    return "/var/lib/odoo/addons/19.0,/mnt/extra-addons,/custom_addons,/enterprise,/mnt/enterprise"