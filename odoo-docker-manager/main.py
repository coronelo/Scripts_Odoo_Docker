from app.docker_client import DockerClient
from app.odoo_config import OdooConfig
from config.settings import Config
from app.utils import Console, PasswordGenerator
from colorama import Fore, Style, init
from app.nginx_manager import crear_config_nginx
from app.certbot_manager import solicitar_certificado
from app.deploy_online import validar_https
from app.docker_nginx_manager import asegurar_nginx, recargar_nginx_docker
from app.docker_acme_manager import asegurar_certbot
import sys
import os
import shutil
import psycopg2
import subprocess

init(autoreset=True)

POSTGRES_ADMIN_PASSWORD = None  # Variable global para la contraseña

def crear_estructura_proyecto(nombre):
    base_dir = os.path.abspath(os.path.dirname(__file__))
    proyecto_dir = os.path.join(base_dir, "proyectos", nombre)
    subdirs = [
        "filestore",
        "python-packages",
        os.path.join("odoo-config"),
    ]
    for subdir in subdirs:
        os.makedirs(os.path.join(proyecto_dir, subdir), exist_ok=True)
    return proyecto_dir

def crear_postgres_compartido():
    global POSTGRES_ADMIN_PASSWORD
    Console.header("CREAR POSTGRESQL COMPARTIDO")
    
    docker_client = DockerClient()
    
    if docker_client.container_exists(Config.POSTGRES_CONTAINER):
        Console.success(f"PostgreSQL ya existe: {Config.POSTGRES_CONTAINER}")
        return True
    
    Console.info("Creando PostgreSQL compartido...")
    
    # Crear usuario admin por defecto
    admin_pass = PasswordGenerator.generate_secure_password()
    POSTGRES_ADMIN_PASSWORD = admin_pass
    # Guarda la contraseña en un archivo seguro
    with open("postgres_admin_password.txt", "w") as f:
        f.write(admin_pass)
    
    db_config = {
        'name': Config.POSTGRES_CONTAINER,
        'image': Config.POSTGRES_IMAGE,
        'ports': {f'5432/tcp': Config.POSTGRES_HOST_PORT},
        'environment': {
            'POSTGRES_USER': 'odoo_admin',
            'POSTGRES_PASSWORD': admin_pass,
            'POSTGRES_HOST_AUTH_METHOD': 'md5'
        }
    }
    
    container = docker_client.create_container(db_config, Config.NETWORK_NAME)
    if container:
        Console.success(f"PostgreSQL creado en puerto {Config.POSTGRES_HOST_PORT}")
        Console.info(f"Usuario admin: odoo_admin")
        Console.info(f"Contraseña admin: {admin_pass}")
        return True
    else:
        Console.error("Error al crear PostgreSQL")
        return False

def crear_contenedor():
    global POSTGRES_ADMIN_PASSWORD
    # Cargar la contraseña si no está en memoria
    if not POSTGRES_ADMIN_PASSWORD:
        try:
            with open("postgres_admin_password.txt") as f:
                POSTGRES_ADMIN_PASSWORD = f.read().strip()
        except Exception:
            Console.error("No se pudo obtener la contraseña de PostgreSQL. Ejecuta primero la opción 1.")
            return
    
    Console.header("CREAR NUEVO ODOO")
    
    docker_client = DockerClient()
    
    if not docker_client.container_exists(Config.POSTGRES_CONTAINER):
        Console.error("Primero crea PostgreSQL compartido (Opción 1)")
        return
    
    name = input("Nombre del proyecto: ")
    version = input(f"{Fore.CYAN}Versión (18.0/19.0) [{Fore.YELLOW}19.0{Fore.CYAN}]: {Style.RESET_ALL}") or "19.0"
    port = input(f"{Fore.CYAN}Puerto [{Fore.YELLOW}8069{Fore.CYAN}]: {Style.RESET_ALL}") or "8069"
    
    if docker_client.container_exists(name):
        Console.error(f"El contenedor '{name}' ya existe")
        return
    
    # Generar credenciales seguras (incluyendo master_password)
    Console.info("Generando credenciales seguras...")
    try:
        port_int = int(port)
    except ValueError:
        Console.error("Puerto inválido, debe ser un número")
        return
    creds = Config.generate_credentials(name)
    config = OdooConfig(
        version, name, port_int,
        admin_db_password=POSTGRES_ADMIN_PASSWORD,
        master_password=creds['master_password']
    )
    
    # Mostrar configuración
    Console.header("CONFIGURACIÓN")
    print(f"{Fore.WHITE}Proyecto: {Fore.GREEN}{name}")
    print(f"{Fore.WHITE}Versión Odoo: {Fore.GREEN}{version}")
    print(f"{Fore.WHITE}Puerto: {Fore.GREEN}{port}")
    print(f"{Fore.WHITE}Base de datos: {Fore.GREEN}{config.credentials['db_name']}")
    print(f"{Fore.WHITE}Usuario DB: {Fore.GREEN}odoo_admin")
    print(f"{Fore.WHITE}Contraseña DB: {Fore.YELLOW}{POSTGRES_ADMIN_PASSWORD}")
    print(f"{Fore.WHITE}Contraseña Admin Odoo: {Fore.YELLOW}admin (por defecto)")
    
    confirm = input(f"\n{Fore.CYAN}¿Crear proyecto? (s/n): {Style.RESET_ALL}")
    if confirm.lower() != 's':
        Console.warning("Cancelado")
        return
    
    proyecto_dir = crear_estructura_proyecto(name)

    # Define rutas de addons según versión ANTES de crear odoo.conf
    if version == "18.0":
        custom_addons_host = "/home/odoo/custom_addonsV180"
        enterprise_addons_host = "/home/odoo/enterpriseV180"
        base_addons = "/var/lib/odoo/addons/18.0"
    elif version == "19.0":
        custom_addons_host = "/home/odoo/custom_addonsV190"
        enterprise_addons_host = "/home/odoo/enterpriseV190"
        base_addons = "/var/lib/odoo/addons/19.0"

    ruta_conf = os.path.join(proyecto_dir, "odoo-config", "odoo.conf")
    with open(ruta_conf, "w") as f:
        f.write(f"""[options]
db_host = {Config.POSTGRES_CONTAINER}
db_user = odoo_admin
db_password = {POSTGRES_ADMIN_PASSWORD}  # <-- Debe ser la contraseña real, no None
db_port = 5432
addons_path = {base_addons},/custom_addons,/enterprise
admin_passwd = {config.credentials['master_password']}
""")

    odoo_volumes = {
        custom_addons_host: {'bind': '/custom_addons', 'mode': 'rw'},
        enterprise_addons_host: {'bind': '/enterprise', 'mode': 'rw'},
        os.path.join(proyecto_dir, "odoo-config", "odoo.conf"): {'bind': '/etc/odoo/odoo.conf', 'mode': 'ro'},
        os.path.join(proyecto_dir, "odoo-config", "odoo.log"): {'bind': '/var/log/odoo/odoo.log', 'mode': 'rw'},
    }

    # 3. Crear contenedor Odoo con volúmenes y configuración
    odoo_config = config.get_container_config()
    odoo_config['volumes'] = odoo_volumes
    container = docker_client.create_container(odoo_config, Config.NETWORK_NAME)
    
    if not container:
        Console.error("Error creando contenedor")
        return
    
    # 4. Inicializar base de datos Odoo usando el superusuario de Postgres
    Console.info("Inicializando base de datos Odoo...")
    if docker_client.initialize_odoo_database(
        name,
        config.credentials['db_name'],
        db_user="odoo_admin",
        db_password=POSTGRES_ADMIN_PASSWORD,
    ):
        Console.header("✅ PROYECTO CREADO EXITOSAMENTE")
        print(f"{Fore.GREEN}URL: {Fore.WHITE}http://localhost:{port}")
        print(f"{Fore.GREEN}Usuario: {Fore.WHITE}admin")
        print(f"{Fore.GREEN}Contraseña: {Fore.YELLOW}admin (por defecto)")
        print(f"\n{Fore.CYAN}Credenciales PostgreSQL:")
        print(f"  DB: {config.credentials['db_name']}")
        print(f"  User: odoo_admin")
        print(f"  Password: {POSTGRES_ADMIN_PASSWORD}")
        print(f"{Fore.GREEN}Master Password: {Fore.YELLOW}{config.credentials['master_password']}")
    else:
        Console.warning("Proyecto creado pero requiere inicialización manual desde la web.")
        print(f"\nAccede a Odoo en http://localhost:{port} y crea la base de datos desde la interfaz web.")

    # Configuración de Nginx y Certbot
    dominio = input("Introduce el dominio para el proyecto Odoo: ")
    puerto_odoo = port  # Usa el puerto que asignaste al contenedor

    crear_config_nginx(dominio, puerto_odoo)
    os.system("sudo systemctl reload nginx")
    solicitar_certificado(dominio)
    validar_https(dominio)

def listar_contenedores():
    Console.header("LISTA DE CONTENEDORES")
    docker_client = DockerClient()
    try:
        containers = docker_client.client.containers.list(all=True)
    except Exception as e:
        Console.error(f"Error listando contenedores: {e}")
        return []

    if not containers:
        Console.info("No se encontraron contenedores")
        return []

    for idx, c in enumerate(containers, start=1):
        name = getattr(c, "name", "<sin-nombre>")
        image = ""
        try:
            image = c.image.tags[0] if getattr(c, "image", None) and c.image.tags else str(c.image)
        except Exception:
            image = str(getattr(c, "image", ""))

        status = getattr(c, "status", "")
        ports = c.attrs.get("NetworkSettings", {}).get("Ports", {}) if getattr(c, "attrs", None) else {}
        print(f"{Fore.CYAN}{idx}.{Style.RESET_ALL} {Fore.WHITE}{name}{Style.RESET_ALL} | {Fore.YELLOW}{image}{Style.RESET_ALL} | {Fore.GREEN}{status}{Style.RESET_ALL} | {ports}")
    return containers

def eliminar_proyecto_interactivo():
    """Versión interactiva de eliminación de proyecto"""
    Console.header("ELIMINAR PROYECTO / CONTENEDOR")
    containers = listar_contenedores()
    if not containers:
        return

    choice = input(f"\n{Fore.CYAN}Seleccione número o escriba nombre del contenedor a eliminar (q para cancelar): {Style.RESET_ALL}").strip()
    if choice.lower() == 'q' or not choice:
        Console.warning("Cancelado")
        return

    docker_client = DockerClient()
    target = None

    # selección por índice
    if choice.isdigit():
        idx = int(choice) - 1
        if idx < 0 or idx >= len(containers):
            Console.error("Índice fuera de rango")
            return
        target = containers[idx]
    else:
        # búsqueda por nombre exacto
        try:
            target = docker_client.get_container(choice)
            if not target:
                Console.error("Contenedor no encontrado con ese nombre")
                return
        except Exception as e:
            Console.error(f"Error buscando contenedor: {e}")
            return

    name = getattr(target, "name", "<sin-nombre>")
    confirm = input(f"{Fore.RED}¿Eliminar contenedor '{name}' y su base de datos relacionada? (s/n): {Style.RESET_ALL}").strip().lower()
    if confirm != 's':
        Console.warning("Operación cancelada")
        return

    # Detener y eliminar contenedor
    try:
        Console.info(f"Deteniendo contenedor {name}...")
        try:
            target.stop(timeout=10)
        except Exception:
            pass
        Console.info(f"Eliminando contenedor {name}...")
        target.remove(v=True, force=True)
        Console.success(f"Contenedor '{name}' eliminado")
    except Exception as e:
        Console.error(f"Error eliminando contenedor: {e}")
        return

    # Intentar eliminar DB y user en Postgres compartido
    postgres = docker_client.get_container(Config.POSTGRES_CONTAINER)
    if not postgres:
        Console.warning(f"Contenedor Postgres '{Config.POSTGRES_CONTAINER}' no encontrado. Saltando eliminación de BD.")
        return

    # Derivar db_name/db_user usando OdooConfig (se asume derivación determinista por nombre del proyecto)
    try:
        cfg = OdooConfig("19.0", name, 8069)
        db_name = cfg.credentials.get('db_name')
        db_user = cfg.credentials.get('db_user')
    except Exception:
        db_name = None
        db_user = None

    if not db_name or not db_user:
        Console.warning("No se pudo determinar db_name/db_user para este proyecto. Saltando eliminación de BD.")
        return

    # Obtener usuario y contraseña del contenedor Postgres
    env_list = postgres.attrs.get("Config", {}).get("Env", []) or []
    env = {}
    for e in env_list:
        if "=" in e:
            k, v = e.split("=", 1)
            env[k] = v

    env_user = env.get("POSTGRES_USER")
    env_pass = env.get("POSTGRES_PASSWORD", "")

    if not env_user:
        Console.error("No se encontró POSTGRES_USER en el contenedor Postgres.")
        return

    for sql in (f'DROP DATABASE IF EXISTS "{db_name}";', f'DROP USER IF EXISTS "{db_user}";'):
        Console.info(f"Ejecutando en Postgres: {sql}")
        try:
            cmd = ["bash", "-lc", f"PGPASSWORD={env_pass} psql -U {env_user} -v ON_ERROR_STOP=1 -c \"{sql}\""]
            res = postgres.exec_run(cmd, user="root", stream=False)
            exit_code = getattr(res, "exit_code", None)
            output = getattr(res, "output", b"")
            out_text = output.decode(errors="ignore") if isinstance(output, (bytes, bytearray)) else str(output)
            if exit_code not in (0, None):
                Console.error(f"Error ejecutando psql: {out_text}")
            else:
                Console.success("Comando ejecutado correctamente")
        except Exception as e:
            Console.error(f"Error al ejecutar psql: {e}")

    # Eliminar carpetas asociadas al proyecto
    # Pregunta la versión al usuario (puedes mejorar esto para detectar la versión automáticamente si lo deseas)
    version = input(f"{Fore.CYAN}Versión del proyecto a eliminar (18.0/19.0): {Style.RESET_ALL}") or "19.0"
    eliminar_proyecto_carpetas(name, version)

def eliminar_proyecto_carpetas(nombre, version):
    version_tag = version.replace('.', '')
    carpetas_a_eliminar = [
        f'./filestore/v{version}',
        f'./python-packages/v{version}',
        f'./odoo-{version}-enterprise',
        './odoo-addons',
        f'./odoo-config/v{version}',
        f'./custom_addonsV{version_tag}',
        f'./enterpriseV{version_tag}',
    ]
    for carpeta in carpetas_a_eliminar:
        try:
            shutil.rmtree(carpeta)
            print(f"Carpeta eliminada: {carpeta}")
        except FileNotFoundError:
            pass
        except Exception as e:
            print(f"Error eliminando {carpeta}: {e}")

def crear_odoo_conf(db_host, db_user, db_password, master_password, version, db_port=5432, ruta_conf=None):
    ruta_conf = ruta_conf or f"./odoo-config/v{version}/odoo.conf"
    carpeta = os.path.dirname(ruta_conf)
    os.makedirs(carpeta, exist_ok=True)  # <-- CREA LA CARPETA SI NO EXISTE
    addons_path = obtener_addons_path(version)
    with open(ruta_conf, "w") as f:
        f.write(f"""[options]
db_host = {db_host}
db_user = {db_user}
db_password = {db_password}
db_port = {db_port}
addons_path = {addons_path}
admin_passwd = {master_password}
""")
    return ruta_conf

def obtener_addons_path(version):
    base_addons = f"/var/lib/odoo/addons/{version}"
    extra_addons = "/mnt/extra-addons"
    custom_addons = "/custom_addons"
    enterprise_addons = "/enterprise"
    enterprise_mnt = "/mnt/enterprise"
    return f"{base_addons},{extra_addons},{custom_addons},{enterprise_addons},{enterprise_mnt}"

def eliminar_contenedor_docker(nombre):
    """Elimina un contenedor Docker específico"""
    result = subprocess.run(["docker", "rm", "-f", nombre], capture_output=True)
    if result.returncode == 0:
        Console.success(f"Contenedor {nombre} eliminado.")
    else:
        Console.error(f"Error eliminando {nombre}: {result.stderr.decode()}")

def eliminar_proyecto_completo(nombre_proyecto):
    """
    Elimina el contenedor Docker, la carpeta del proyecto y la base de datos asociada.
    """
    Console.header(f"ELIMINANDO PROYECTO: {nombre_proyecto}")
    
    # 1. Eliminar contenedor Docker
    print(f"\nEliminando contenedor Docker '{nombre_proyecto}'...")
    result = subprocess.run(["docker", "rm", "-f", nombre_proyecto], capture_output=True)
    if result.returncode == 0:
        Console.success(f"Contenedor Docker '{nombre_proyecto}' eliminado.")
    else:
        Console.info(f"Contenedor Docker '{nombre_proyecto}' no existe o ya estaba eliminado.")

    # 2. Eliminar carpeta del proyecto
    base_dir = os.path.abspath(os.path.dirname(__file__))
    ruta = os.path.join(base_dir, "proyectos", nombre_proyecto)
    print(f"Eliminando carpeta del proyecto '{nombre_proyecto}'...")
    try:
        if os.path.exists(ruta):
            shutil.rmtree(ruta)
            Console.success(f"Carpeta del proyecto '{nombre_proyecto}' eliminada.")
        else:
            Console.info(f"Carpeta del proyecto '{nombre_proyecto}' no existe.")
    except Exception as e:
        Console.error(f"Error eliminando carpeta: {e}")

    # 3. Eliminar base de datos
    print(f"Eliminando base de datos '{nombre_proyecto}'...")
    try:
        # Usa los datos de conexión de tu configuración si existen
        db_user = getattr(Config, "POSTGRES_USER", "odoo_admin")
        db_password = POSTGRES_ADMIN_PASSWORD or getattr(Config, "POSTGRES_PASSWORD", "")
        db_host = getattr(Config, "POSTGRES_CONTAINER", "localhost")
        db_port = getattr(Config, "POSTGRES_PORT", "5432")
        
        conn = psycopg2.connect(
            dbname="postgres",
            user=db_user,
            password=db_password,
            host=db_host,
            port=db_port
        )
        conn.autocommit = True
        cur = conn.cursor()
        cur.execute(f'DROP DATABASE IF EXISTS "{nombre_proyecto}";')
        Console.success(f"Base de datos '{nombre_proyecto}' eliminada.")
        cur.close()
        conn.close()
    except Exception as e:
        Console.error(f"Error eliminando base de datos: {e}")

# Ejemplo de integración en tu menú principal:
def mostrar_menu():
    Console.header("ODOO DOCKER MANAGER")
    print(f"{Fore.CYAN}1.{Style.RESET_ALL} Crear PostgreSQL compartido")
    print(f"{Fore.CYAN}2.{Style.RESET_ALL} Crear nuevo proyecto Odoo")
    print(f"{Fore.CYAN}3.{Style.RESET_ALL} Listar contenedores")
    print(f"{Fore.CYAN}4.{Style.RESET_ALL} Eliminar proyecto interactivo")
    print(f"{Fore.CYAN}5.{Style.RESET_ALL} Eliminar proyecto por nombre")
    print(f"{Fore.CYAN}6.{Style.RESET_ALL} Configurar Nginx para proyecto")
    print(f"{Fore.CYAN}7.{Style.RESET_ALL} Solicitar certificado SSL (ACME)")
    print(f"{Fore.CYAN}8.{Style.RESET_ALL} Validar acceso HTTPS")
    print(f"{Fore.CYAN}9.{Style.RESET_ALL} Eliminar contenedor Nginx")
    print(f"{Fore.CYAN}10.{Style.RESET_ALL} Eliminar contenedor Certbot (ACME)")
    print(f"{Fore.CYAN}11.{Style.RESET_ALL} {Fore.RED}Salir{Style.RESET_ALL}")

def main():
    global POSTGRES_ADMIN_PASSWORD
    
    # Intentar cargar la contraseña de PostgreSQL al inicio
    try:
        with open("postgres_admin_password.txt") as f:
            POSTGRES_ADMIN_PASSWORD = f.read().strip()
    except Exception:
        pass
    
    while True:
        mostrar_menu()
        opcion = input(f"\n{Fore.YELLOW}Seleccione opción (1-11): {Style.RESET_ALL}")
        
        if opcion == "1":
            crear_postgres_compartido()
        elif opcion == "2":
            crear_contenedor()
        elif opcion == "3":
            listar_contenedores()
        elif opcion == "4":
            eliminar_proyecto_interactivo()
        elif opcion == "5":
            nombre = input("Nombre del proyecto a eliminar: ")
            eliminar_proyecto_completo(nombre)
        elif opcion == "6":
            asegurar_nginx()
            dominio = input("Dominio del proyecto: ")
            puerto = input("Puerto Odoo: ")
            crear_config_nginx(dominio, puerto)
            recargar_nginx_docker()
        elif opcion == "7":
            from app.docker_acme_manager import asegurar_certbot
            from app.certbot_manager import solicitar_certificado

            asegurar_certbot()  # Esto crea el contenedor si no existe
            dominio = input("Dominio para el certificado SSL: ")
            solicitar_certificado(dominio)  # Esto ejecuta certbot dentro del contenedor
        elif opcion == "8":
            dominio = input("Dominio para validar HTTPS: ")
            validar_https(dominio)
        elif opcion == "9":
            eliminar_contenedor_docker("nginx-proxy")
        elif opcion == "10":
            eliminar_contenedor_docker("certbot")
        elif opcion == "11":
            Console.info("¡Hasta luego!")
            break
        else:
            Console.error("Opción no válida")

if __name__ == "__main__":
    main()