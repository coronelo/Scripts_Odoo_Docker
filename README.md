# Odoo Docker Manager Scripts

Este repositorio contiene un conjunto de herramientas avanzadas para la gestión automatizada de entornos Odoo utilizando Docker. Diseñado para simplificar el despliegue, mantenimiento y configuración de instancias Odoo con soporte para múltiples versiones, dominios personalizados y certificados SSL automáticos.

## Características Principales

*   **Gestión Centralizada**: Utiliza **Nginx Proxy Manager** (NPM) como único punto de entrada para todos los proyectos, permitiendo múltiples dominios y gestión SSL simplificada.
*   **Multi-Versión**: Soporte para desplegar diferentes versiones de Odoo.
*   **Automatización**:
    *   Generación automática de `docker-compose.yml`.
    *   Configuración automática de dominios y proxys reversos en NPM.
    *   Gestión de certificados SSL (Let's Encrypt).
*   **Gestión de Dependencias**: Sistema robusto para instalar y persistir dependencias de Python externas en volúmenes compartidos.
*   **Backup y Mantenimiento**: Herramientas integradas para realizar copias de seguridad y limpieza de contenedores.
*   **Entorno de Desarrollo**: Facilita la configuración de rutas locales para `custom_addons` y `enterprise`.

## Scripts Incluidos

### 1. `odoo_manager_full.sh`
Es el script principal y más completo. Actúa como un "Maestro" para la orquestación de todos los entornos.

**Funcionalidades:**
*   Instalación y configuración de Nginx Proxy Manager.
*   Creación de nuevos proyectos Odoo (DB + Odoo Container).
*   Gestión de redes Docker (`odoo-global-network`).
*   Menú interactivo para:
    *   Crear/Eliminar proyectos.
    *   Ver logs.
    *   Reiniciar servicios.
    *   Instalar librerías Python adicionales.
    *   Gestionar rutas de addons.

### 2. `odoo_docker_manager_V2.sh`
Versión anterior o alternativa del gestor de Docker, mantenida por compatibilidad o como referencia.

### 3. `delete_dockers.sh`
Herramienta de utilidad para limpieza rápida de contenedores y volúmenes Docker (¡Usar con precaución!).

### 4. `odoo-docker-manager/` (Python)
Una aplicación Python (en desarrollo) modularizada para gestionar la lógica de Docker de forma más estructurada que los scripts de bash. Incluye gestión de configuraciones y comandos.

## Requisitos

*   Linux (Ubuntu/Debian recomendado).
*   Docker y Docker Compose plugin instalados.
*   Permisos de `sudo`.

## Uso Rápido

Para iniciar el gestor principal:

```bash
sudo ./odoo_manager_full.sh
```

Sigue las instrucciones en pantalla para configurar tu directorio de trabajo y comenzar a desplegar instancias.

## Estructura del Proyecto

```
.
├── odoo_manager_full.sh        # Script principal de gestión
├── odoo_docker_manager_V2.sh   # Versión V2
├── delete_dockers.sh           # Script de limpieza
├── init_project.sh             # Inicializador rápido
└── odoo-docker-manager/        # CLI en Python (Backend logic)
    ├── main.py
    └── ...
```

## Autor

**Fran Moreno**
_Gestor profesional de entornos Odoo_
