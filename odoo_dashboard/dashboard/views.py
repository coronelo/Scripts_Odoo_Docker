from django.shortcuts import render, redirect
from django.contrib.auth.decorators import login_required
import os
import docker
from .models import Project
from . import utils

@login_required
def index(request):
    # Conectar con Docker
    try:
        client = docker.from_env()
        containers = client.containers.list(all=True)
    except Exception as e:
        client = None
        containers = []
        docker_error = str(e)
    
    base_dir = os.path.expanduser('~/odoo_projects')
    projects_list = []
    
    if os.path.exists(base_dir):
        for name in os.listdir(base_dir):
            path = os.path.join(base_dir, name)
            if os.path.isdir(path) and 'docker-compose.yml' in os.listdir(path):
                # Auto-registro en DB si no existe
                project_db, created = Project.objects.get_or_create(
                    name=name,
                    defaults={'path': path, 'deploy_mode': 'local'}
                )
                
                # Buscar contenedores asociados a este proyecto
                project_containers = [c for c in containers if c.name.startswith(f"{name}_")]
                
                status = "OFFLINE"
                if any(c.status == 'running' for c in project_containers):
                    status = "RUNNING"
                elif project_containers:
                    status = "STOPPED"
                
                projects_list.append({
                    'id': project_db.id,
                    'name': name,
                    'path': path,
                    'status': status,
                    'container_count': len(project_containers),
                    'containers': project_containers
                })
    
    return render(request, 'dashboard/index.html', {
        'projects': projects_list,
        'docker_connected': client is not None,
    })

@login_required
def delete_project(request, pk):
    project = Project.objects.get(pk=pk)
    if request.method == 'POST':
        # Detener contenedores primero
        try:
            client = docker.from_env()
            project_containers = [c for c in client.containers.list(all=True) if c.name.startswith(f"{project.name}_")]
            for c in project_containers:
                c.remove(force=True)
        except:
            pass
            
        # Borrar archivos si se solicita
        if request.POST.get('delete_files') == 'yes':
            import subprocess
            try:
                subprocess.run(['sudo', 'rm', '-rf', project.path], check=True)
            except Exception as e:
                print(f"Error borrando archivos: {e}")
        
        project.delete()
        return redirect('index')
    
    return render(request, 'dashboard/delete_confirm.html', {'project': project})

@login_required
def projects(request):
    return index(request) # Por ahora usamos la misma lógica

@login_required
def logs_view(request):
    client = docker.from_env()
    containers = client.containers.list(all=True)
    return render(request, 'dashboard/logs.html', {'containers': containers})

@login_required
def project_logs(request, container_id):
    try:
        client = docker.from_env()
        container = client.containers.get(container_id)
        logs = container.logs(tail=100).decode('utf-8')
    except Exception as e:
        logs = f"Error al obtener logs: {e}"
        container = None
        
    return render(request, 'dashboard/project_logs.html', {
        'logs': logs,
        'container': container
    })

@login_required
def project_detail(request, pk):
    project = Project.objects.get(pk=pk)
    env_data = {}
    env_path = os.path.join(project.path, '.env')
    
    if os.path.exists(env_path):
        with open(env_path, 'r') as f:
            for line in f:
                if '=' in line:
                    key, value = line.strip().split('=', 1)
                    env_data[key] = value
                    
    return render(request, 'dashboard/project_detail.html', {
        'project': project,
        'env': env_data,
        'server_ip': utils.get_server_ip()
    })

@login_required
def trigger_backup(request, pk):
    project = Project.objects.get(pk=pk)
    try:
        client = docker.from_env()
        # Buscamos el contenedor de DB
        db_container = next((c for c in client.containers.list() if c.name.startswith(f"{project.name}_db")), None)
        
        if db_container:
            backup_dir = os.path.join(project.path, 'backups')
            os.makedirs(backup_dir, exist_ok=True)
            
            from datetime import datetime
            filename = f"backup_{project.name}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.sql"
            filepath = os.path.join(backup_dir, filename)
            
            # Ejecutar pg_dump
            # Nota: Esto es simplificado. En producción usaríamos un stream o manejaríamos credenciales mejor
            res = db_container.exec_run(f"pg_dump -U desarrollo {project.name}")
            with open(filepath, 'wb') as f:
                f.write(res.output)
                
            return render(request, 'dashboard/project_detail.html', {
                'project': project,
                'success_msg': f"Backup creado: {filename}"
            })
    except Exception as e:
        return render(request, 'dashboard/project_detail.html', {
            'project': project,
            'error_msg': f"Error en backup: {e}"
        })
    
    return redirect('project_detail', pk=pk)

@login_required
def settings(request):
    return render(request, 'dashboard/settings.html')


@login_required
def create_project(request):
    if request.method == 'POST':
        project_name = request.POST.get('name')
        odoo_version = request.POST.get('version', '19')
        deploy_mode = request.POST.get('deploy_mode', 'local')
        domain = request.POST.get('domain', '')
        
        base_dir = os.path.expanduser('~/odoo_projects')
        project_path = os.path.join(base_dir, project_name)
        
        try:
            # 1. Generar contraseñas
            admin_pass = utils.generate_password(24)
            pg_pass = utils.generate_password(16)
            pg_user = "desarrollo"
            
            # 2. Crear estructura de carpetas
            utils.create_project_structure(project_path, [odoo_version])
            
            # 3. Escribir .env
            env_data = {
                'PROJECT_NAME': project_name,
                'PROJECT_DIR': project_path,
                'DEPLOY_MODE': deploy_mode,
                'ODOO_USER': 'desarrollo',
                'ODOO_PASS': pg_pass,
                'PG_USER': pg_user,
                'PG_PASS': pg_pass,
                'ADMIN_PASS': admin_pass,
                'ODOO_VERSIONS': odoo_version,
                'MAIN_DOMAIN': domain if deploy_mode == 'online' else ''
            }
            utils.write_env_file(project_path, env_data)
            
            # 4. Escribir odoo.conf
            utils.write_odoo_conf(project_path, [odoo_version], admin_pass, pg_user, pg_pass, project_name)
            
            # 5. Escribir docker-compose.yml
            utils.write_docker_compose(project_path, project_name, [odoo_version], pg_user, pg_pass, deploy_mode, domain)
            
            # 6. Ejecutar despliegue (Docker Compose Up)
            import subprocess
            try:
                subprocess.run(['docker', 'compose', 'up', '-d'], cwd=project_path, check=True)
            except Exception as e:
                print(f"Error en despliegue inicial: {e}")
            
            # 7. Registrar en DB
            Project.objects.get_or_create(
                name=project_name,
                path=project_path,
                domain=domain,
                deploy_mode=deploy_mode
            )
            return redirect('index')
        except Exception as e:
            return render(request, 'dashboard/create_project.html', {'error': str(e)})
            
    return render(request, 'dashboard/create_project.html')

@login_required
def toggle_project(request, project_name, action):
    try:
        client = docker.from_env()
        # Filtramos contenedores que pertenecen al proyecto
        all_containers = client.containers.list(all=True)
        project_containers = [c for c in all_containers if c.name.startswith(f"{project_name}_")]
        
        for container in project_containers:
            if action == 'start':
                container.start()
            elif action == 'stop':
                container.stop()
            elif action == 'restart':
                container.restart()
                
    except Exception as e:
        print(f"Error en toggle_project: {e}")
        
    return redirect('index')
