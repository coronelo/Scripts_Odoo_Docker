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

### 1. `odoo_manager_full.sh` (Script Maestro Modular)
Es el script principal y más completo. Ahora utiliza una arquitectura **modular** para mejorar la mantenibilidad y la legibilidad.

**Cómo funciona:**
El script actúa como un cargador. Al ejecutarse, importa automáticamente los módulos situados en la carpeta `lib/`:
*   `lib/utils.sh`: Utilidades del sistema, colores y verificación de dependencias.
*   `lib/ui.sh`: Componentes visuales (encabezados, menús, cajas de éxito/error).
*   `lib/config.sh`: Gestión de configuración global y variables de entorno.
*   `lib/npm.sh`: Orquestación de Nginx Proxy Manager y certificados SSL.
*   `lib/odoo.sh`: Lógica core para desplegar instancias Odoo, PostgreSQL y Docker Compose.

**Funcionalidades del Menú:**
*   Instalación y configuración de Nginx Proxy Manager.
*   Creación de nuevos proyectos Odoo (DB + Odoo Container).
*   Gestión de redes Docker (`odoo-global-network`).
*   Menú interactivo para gestionar logs, reiniciar servicios e instalar dependencias Python.

### 2. `delete_dockers.sh`
Herramienta de utilidad para limpieza rápida de contenedores y volúmenes Docker (¡Usar con precaución, es destructiva!).

### 3. `odoo-docker-manager/` (Python)
Una aplicación Python (en desarrollo) para gestionar la lógica de Docker de forma más estructurada que los scripts de bash.

## Requisitos

*   Linux (Ubuntu/Debian recomendado).
*   Docker y Docker Compose plugin instalados.
*   Permisos de `sudo`.

## Uso Rápido

Para iniciar el gestor principal:

```bash
sudo ./odoo_manager_full.sh
```

## Estructura del Proyecto

```
.
├── odoo_manager_full.sh    # Script principal (Cargador de módulos)
├── lib/                    # Módulos lógicos (Lógica separada)
│   ├── config.sh
│   ├── npm.sh
│   ├── odoo.sh
│   ├── ui.sh
│   └── utils.sh
├── archive/                # Versiones antiguas y archivadas
├── backups_scripts/        # Copias de seguridad preventivas
├── delete_dockers.sh       # Script de limpieza total
├── init_project.sh         # Inicializador rápido de estructura
└── odoo-docker-manager/    # CLI en Python (En desarrollo)
```

## Autor

**Fran Moreno**
_Gestor profesional de entornos Odoo_
