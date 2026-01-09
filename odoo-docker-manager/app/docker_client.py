import docker
import logging
import shlex
import time
from typing import Optional, Dict, Any
from config.settings import Config

class DockerClient:
    def __init__(self, postgres_container: Optional[str] = None):
        self.client = docker.from_env()
        self.logger = logging.getLogger(__name__)
        self.postgres_container = postgres_container or Config.POSTGRES_CONTAINER
    
    def get_container(self, name):
        try:
            return self.client.containers.get(name)
        except docker.errors.NotFound:
            return None
    
    def container_exists(self, name):
        return self.get_container(name) is not None
    
    def create_network(self, name):
        """Crear red si no existe"""
        try:
            networks = self.client.networks.list(names=[name])
            if networks:
                return networks[0]
            return self.client.networks.create(name, driver="bridge")
        except Exception as e:
            self.logger.exception("Error creando red")
            return None
    
    def create_container(self, config: Dict[str, Any], network_name: Optional[str] = None):
        try:
            container = self.client.containers.run(
                image=config['image'],
                name=config['name'],
                ports=config.get('ports', {}),
                volumes=config.get('volumes', {}),  # validar formato en quien llama
                environment=config.get('environment', {}),
                detach=True
            )
            
            # Conectar a red si se especifica
            if network_name:
                network = self.create_network(network_name)
                if network:
                    network.connect(container)
            
            return container
        except Exception as e:
            self.logger.exception("Error creando contenedor")
            return None
    
    def create_database_user(self, db_config: Dict[str, str], postgres_container: Optional[str] = None) -> bool:
        """Crea usuario y base de datos en PostgreSQL ejecutando psql dentro del contenedor."""
        try:
            pg_name = postgres_container or self.postgres_container
            if not pg_name:
                self.logger.error("Nombre del contenedor Postgres no proporcionado")
                return False

            postgres = self.get_container(pg_name)
            if not postgres:
                self.logger.error("Contenedor Postgres no encontrado: %s", pg_name)
                return False

            # Extraer env del contenedor
            env_list = postgres.attrs.get("Config", {}).get("Env", []) or []
            env = {}
            for e in env_list:
                if "=" in e:
                    k, v = e.split("=", 1)
                    env[k] = v

            env_user = env.get("POSTGRES_USER")
            env_pass = env.get("POSTGRES_PASSWORD", "")

            if not env_user:
                self.logger.error("No se encontró POSTGRES_USER en el contenedor. No se puede conectar como superusuario.")
                return False

            db_user = db_config["db_user"]
            db_password = db_config["db_password"]
            db_name = db_config["db_name"]

            create_user_sql = f'CREATE USER "{db_user}" WITH PASSWORD \'{db_password}\';'
            create_db_sql = f'CREATE DATABASE "{db_name}" OWNER "{db_user}";'

            # Esperar a que Postgres esté listo
            ready = False
            for _ in range(15):
                try:
                    cmd_check = ["bash", "-lc", f"PGPASSWORD={shlex.quote(env_pass)} pg_isready -U {shlex.quote(env_user)} -h localhost -p 5432"]
                    res = postgres.exec_run(cmd_check, user="root", stream=False)
                    if getattr(res, "exit_code", None) == 0:
                        ready = True
                        break
                except Exception:
                    pass
                time.sleep(2)

            if not ready:
                self.logger.error("Postgres no respondió a pg_isready después de varios intentos")
                return False

            # Usar siempre el usuario y password definidos en el entorno
            for sql in (create_user_sql, create_db_sql):
                try:
                    cmd = ["bash", "-lc", f"PGPASSWORD={shlex.quote(env_pass)} psql -U {shlex.quote(env_user)} -v ON_ERROR_STOP=1 -c {shlex.quote(sql)}"]
                    res = postgres.exec_run(cmd, user="root", stream=False)
                    exit_code = getattr(res, "exit_code", None)
                    output = getattr(res, "output", b"")
                    out_text = output.decode(errors="ignore") if isinstance(output, (bytes, bytearray)) else str(output)
                    if exit_code == 0 or ("already exists" in out_text.lower()):
                        continue
                    self.logger.error("Error ejecutando psql (%s): %s", cmd, out_text.strip())
                    return False
                except Exception as e:
                    self.logger.error("Error ejecutando psql: %s", str(e))
                    return False

            return True
        except Exception as e:
            self.logger.exception("Error creando usuario/DB: %s", e)
            return False
    
    def initialize_odoo_database(self, container_name: str, db_name: str, admin_password: str, db_user: Optional[str] = None, db_password: Optional[str] = None) -> bool:
        """Inicializa DB Odoo con contraseña admin personalizada"""
        try:
            container = self.get_container(container_name)
            if not container:
                self.logger.error("Contenedor Odoo no encontrado: %s", container_name)
                return False

            db_user = db_user or db_name
            db_password = db_password or db_name

            cmd = [
                "odoo",
                "-d", db_name,
                "--db_host", self.postgres_container,
                "--db_user", db_user,
                "--db_password", db_password,
                "--admin-password", admin_password,  # <-- opción correcta
                "-i", "base",
                "--stop-after-init"
            ]

            exec_result = container.exec_run(cmd, stream=False)
            exit_code = getattr(exec_result, 'exit_code', None)
            output = getattr(exec_result, 'output', b'')
            if isinstance(output, (bytes, bytearray)):
                for line in output.decode(errors='ignore').splitlines():
                    if line:
                        print(line)

            if exit_code != 0:
                self.logger.error("Inicialización de Odoo falló, exit_code=%s", exit_code)
                return False

            return True
        except Exception as e:
            self.logger.exception("Error inicializando DB")
            return False

def crear_contenedor():
    docker_client = DockerClient()
    nombre_proyecto = input("Nombre del proyecto: ")
    db_name = nombre_proyecto
    admin_password = input("Contraseña de administrador Odoo: ")
    db_user = db_name  # O pide al usuario si quieres personalizar
    db_password = db_name  # O pide al usuario si quieres personalizar

    # Crear contenedor y base de datos como lo haces normalmente...
    # ...

    # Inicializar la base de datos Odoo correctamente:
    if docker_client.initialize_odoo_database(
        container_name=nombre_proyecto,
        db_name=db_name,
        admin_password=admin_password,
        db_user=db_user,
        db_password=db_password
    ):
        print("✅ Base de datos Odoo inicializada correctamente.")
    else:
        print("❌ Error inicializando la base de datos Odoo.")

