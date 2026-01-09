from commands.base import BaseCommand
from app.docker_client import DockerClient
from app.odoo_config import OdooConfig

class CreateCommand(BaseCommand):
    @staticmethod
    def add_arguments(parser):
        parser.add_argument("name", help="Nombre del contenedor")
        parser.add_argument("--version", default="19.0", help="Versión de Odoo")
        parser.add_argument("--port", type=int, default=8069, help="Puerto host")
    
    def execute(self, args):
        docker_client = DockerClient()
        
        if docker_client.container_exists(args.name):
            print(f"❌ Contenedor '{args.name}' ya existe")
            return
        
        print(f"Creando Odoo {args.version}...")
        # Aquí implementaremos la creación real
        print(f"✅ Configuración lista para: {args.name}")