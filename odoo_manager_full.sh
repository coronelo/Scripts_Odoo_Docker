#!/bin/bash
# =============================================================================
# Script: odoo_manager_full.sh
# Autor: Fran (Refactorizado por Antigravity)
# Fecha: 2026-05-07
# Descripción:
#   Gestor maestro MODULARIZADO para entornos Odoo en Docker.
# =============================================================================

set -euo pipefail

# ====== Verificar que se ejecute con sudo ======
if [[ $EUID -ne 0 ]]; then
    echo "Este script debe ejecutarse con sudo. Por favor ejecuta: sudo ./$0"
    exit 1
fi

# ====== Cargar Módulos ======
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

source "${LIB_DIR}/utils.sh"
source "${LIB_DIR}/ui.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/npm.sh"
source "${LIB_DIR}/odoo.sh"

# ====== Configuración global ======
CONFIG_FILE="${SCRIPT_DIR}/.odoo_manager_env"
GLOBAL_PASSWORDS_FILE=""

# ====== Variables globales ======
BASE_DIR=""
CUSTOM_ADDONS_PATH=""
ENTERPRISE_PATH=""
COMMON_DOCKER_NETWORK="odoo-global-network"

# ====== CONFIGURACIÓN NPM ======
NPM_CONTAINER="odoo-npm"
NPM_DATA_DIR="/opt/odoo-npm"
NPM_PORT_WEB="81"
NPM_PORT_SSL="444"
NPM_PORT_HTTP="80"
NPM_PORT_HTTPS="443"
NPM_PANEL_IP="192.168.18.205"
NPM_NETWORK="$COMMON_DOCKER_NETWORK"

# ====== UID/GID FIJOS ======
FIXED_UID="1001"
FIXED_GID="1001"

# ====== Flujo de instalación principal ======
install_flow() {
  check_deps
  prompt_config
  calculate_optimal_resources
  create_structure
  write_env
  write_odoo_conf
  write_compose
  fix_permissions_with_fixed_uids "$PROJECT_DIR"
  ensure_network
  
  setup_log_management "$PROJECT_DIR"
  create_backup_system "$PROJECT_DIR" "$PROJECT_NAME"
  add_update_system "$PROJECT_DIR"
  setup_plugin_system "$PROJECT_DIR"
  add_production_checks "$PROJECT_DIR"
  
  if ! deploy_containers; then
    warn "Despliegue normal falló"
    return 1
  fi
  
  if [[ "${DEPLOY_MODE}" == "online" ]]; then
    configure_npm_proxy "${PROJECT_NAME}" "${MAIN_DOMAIN}" "${SSL_EMAIL}"
  fi
  
  if [[ "${INITIALIZE_DB}" == "yes" ]]; then
    initialize_odoo_database
  fi
  return 0
}

# ====== Menú principal ======
main_menu() {
    load_global_config
    init_global_passwords
    
    while true; do
        print_header
        print_system_info
        
        local menu_options=(
            "Instalar nuevo entorno Odoo"
            "Eliminar proyecto existente"
            "Mantenimiento de proyecto"
            "Ver resumen de proyecto"
            "Gestión de Nginx Proxy Manager"
            "Gestión de rutas del sistema"
            "Herramientas avanzadas"
            "Salir"
        )
        
        print_menu "MENÚ PRINCIPAL" "${menu_options[@]}"
        read -p "Selecciona opción [1-8]: " opt
        
        case "$opt" in
            1) if install_flow; then show_credentials "$PROJECT_NAME" "${MAIN_DOMAIN:-}"; fi ;;
            2) cleanup_project ;;
            3) maintain_project ;;
            4) view_project_summary ;;
            5) npm_menu ;;
            6) update_paths_menu ;;
            7) tools_menu ;;
            8) print_success_box "👋 HASTA PRONTO" "Gracias por usar Odoo Docker Manager Pro"; exit 0 ;;
            *) warn "Opción no válida"; sleep 2 ;;
        esac
        
        if [[ "$opt" != "8" ]]; then
            read -p "Presiona Enter para continuar..."
        fi
    done
}

# ====== Arranque ======
setup_custom_paths
main_menu