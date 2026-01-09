#!/bin/bash
# =============================================================================
# Script: odoo_docker_manager_V2.sh
# Autor: Fran
# Fecha: 2025-11-15
# Versión: 2.1 - Corregida y Optimizada
# 
# Descripción:
#   Gestor maestro MEJORADO para entornos Odoo en Docker con Nginx Proxy Manager centralizado
#   - SISTEMA CENTRALIZADO: Un solo NPM para todos los proyectos
#   - MULTI-DOMINIO: Cada proyecto en su propio dominio (ej: dominio1.com, dominio2.net)
#   - CERTIFICADOS AUTOMÁTICOS: Let's Encrypt por dominio con renovación automática
#   - PANEL LOCAL: NPM accesible en http://192.168.18.205:81
#   - UID/GID FIJO 1001
#   - INCLUYE LIMPIEZA, BACKUPS, MONITORIZACIÓN, PLUGINS
#   - OPTIMIZADO PARA MÓDULOS PESADOS (ventas, IA, etc.)
#   - MEJORA: Rutas personalizadas para proyectos, addons y enterprise
#   - CORRECCIÓN: Manejo seguro de variables no definidas
# =============================================================================
set -euo pipefail

# ====== Verificar que se ejecute con sudo ======
if [[ $EUID -ne 0 ]]; then
    echo "Este script debe ejecutarse con sudo. Por favor ejecuta:"
    echo "sudo ./$0"
    exit 1
fi

# ====== Colores ANSI ======
C_RESET="\e[0m"; C_RED="\e[31m"; C_GRN="\e[32m"; C_YLW="\e[33m"; C_BLU="\e[34m"; C_CYN="\e[36m"; C_MAG="\e[35m"
say() { echo -e "${2:-$C_BLU}$1${C_RESET}"; }
ok()  { say "✅ $1" "$C_GRN"; }
warn(){ say "⚠️  $1" "$C_YLW"; }
err() { say "❌ $1" "$C_RED"; exit 1; }

# ====== Configuración global ======
CONFIG_FILE="$(dirname "$0")/.odoo_manager_env"
GLOBAL_PASSWORDS_FILE=""

# ====== Variables globales ======
BASE_DIR=""
CUSTOM_ADDONS_PATH=""
ENTERPRISE_PATH=""
COMMON_DOCKER_NETWORK="odoo-global-network"

# ====== CONFIGURACIÓN NGINX PROXY MANAGER CENTRAL ======
NPM_CONTAINER="odoo-npm"
NPM_DATA_DIR="/opt/odoo-npm"
NPM_PORT_WEB="81"
NPM_PORT_SSL="444"
NPM_PORT_HTTP="80"
NPM_PORT_HTTPS="443"
NPM_PANEL_IP="192.168.18.205"
NPM_NETWORK="$COMMON_DOCKER_NETWORK"  # Usar la red común

# ====== UID/GID FIJOS ======
FIXED_UID="1001"
FIXED_GID="1001"

# ====== MEJORAS VISUALES ======
print_header() {
    clear
    echo -e "${C_CYN}╔══════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_CYN}║                                                          ║${C_RESET}"
    echo -e "${C_CYN}║     ${C_MAG}🚀 ODOO DOCKER MANAGER PRO${C_CYN}                           ║${C_RESET}"
    echo -e "${C_CYN}║     ${C_BLU}Gestor profesional de entornos Odoo${C_CYN}                  ║${C_RESET}"
    echo -e "${C_CYN}║                                                          ║${C_RESET}"
    echo -e "${C_CYN}╚══════════════════════════════════════════════════════════╝${C_RESET}"
    echo ""
}

print_section() {
    local title="$1"
    local line_len=56
    local title_len=${#title}
    local padding=$((line_len - title_len))
    
    echo -e "${C_CYN}┌──────────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_CYN}│ ${C_YLW}${title}${C_CYN} $(printf '%*s' $padding)│${C_RESET}"
    echo -e "${C_CYN}└──────────────────────────────────────────────────────────┘${C_RESET}"
}

print_menu_item() {
    local num="$1"
    local text="$2"
    local color="${3:-$C_BLU}"
    printf "${C_CYN}│ ${C_GRN}%2s)${C_RESET} ${color}%-52s${C_CYN}│${C_RESET}\n" "$num" "$text"
}

print_menu() {
    local title="$1"
    shift
    local options=("$@")
    local line_len=56
    local title_len=${#title}
    local padding=$((line_len - title_len))
    
    echo -e "${C_CYN}┌──────────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_CYN}│ ${C_MAG}${title}${C_CYN} $(printf '%*s' $padding)│${C_RESET}"
    echo -e "${C_CYN}├──────────────────────────────────────────────────────────┤${C_RESET}"
    
    for i in "${!options[@]}"; do
        print_menu_item "$((i+1))" "${options[i]}"
    done
    
    echo -e "${C_CYN}└──────────────────────────────────────────────────────────┘${C_RESET}"
}

print_info_box() {
    local title="$1"
    local content="$2"
    local line_len=56
    local title_len=${#title}
    local padding=$((line_len - title_len))
    
    echo -e "${C_CYN}╔══════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_CYN}║ ${C_YLW}${title}${C_CYN} $(printf '%*s' $padding)║${C_RESET}"
    echo -e "${C_CYN}╠══════════════════════════════════════════════════════════╣${C_RESET}"
    
    # Dividir contenido en líneas de máximo 54 caracteres
    while IFS= read -r line; do
        local line_len=${#line}
        local padding=$((55 - line_len))
        echo -e "${C_CYN}║ ${C_BLU}${line}${C_CYN} $(printf '%*s' $padding)║${C_RESET}"
    done <<< "$(echo "$content" | fold -w 54)"
    
    echo -e "${C_CYN}╚══════════════════════════════════════════════════════════╝${C_RESET}"
}

print_success_box() {
    local title="$1"
    local content="$2"
    local line_len=56
    local title_len=${#title}
    # Restamos 2 porque añadimos "✅ " antes del título
    local padding=$((line_len - title_len - 2))
    
    echo -e "${C_GRN}╔══════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_GRN}║ ✅ ${C_YLW}${title}${C_GRN} $(printf '%*s' $padding)║${C_RESET}"
    echo -e "${C_GRN}╠══════════════════════════════════════════════════════════╣${C_RESET}"
    
    while IFS= read -r line; do
        local line_len=${#line}
        local padding=$((53 - line_len))
        echo -e "${C_GRN}║   ${C_BLU}${line}${C_GRN} $(printf '%*s' $padding)║${C_RESET}"
    done <<< "$(echo "$content" | fold -w 52)"
    
    echo -e "${C_GRN}╚══════════════════════════════════════════════════════════╝${C_RESET}"
}

# ====== Función para mostrar información del sistema ======
print_system_info() {
    echo -e "${C_CYN}┌──────────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_CYN}│ ${C_BLU}📊 INFORMACIÓN DEL SISTEMA${C_CYN}                              │${C_RESET}"
    echo -e "${C_CYN}├──────────────────────────────────────────────────────────┤${C_RESET}"
    
    # Ruta base con valor por defecto si no está definida
    local display_base="${BASE_DIR:-${HOME}/odoo_projects}"
    local base_info="📁 Ruta base: ${display_base}"
    local base_len=${#base_info}
    local base_padding=$((56 - base_len - 2))  # -2 por los caracteres "│ "
    if [[ $base_padding -lt 0 ]]; then base_padding=0; fi
    echo -e "${C_CYN}│ ${C_YLW}📁 Ruta base:${C_RESET} ${display_base}${C_CYN} $(printf '%*s' $base_padding)│${C_RESET}"
    
    # Panel NPM
    local npm_info="🌐 Panel NPM: http://${NPM_PANEL_IP}:${NPM_PORT_WEB}"
    local npm_len=${#npm_info}
    local npm_padding=$((56 - npm_len - 2))
    if [[ $npm_padding -lt 0 ]]; then npm_padding=0; fi
    echo -e "${C_CYN}│ ${C_YLW}🌐 Panel NPM:${C_RESET} http://${NPM_PANEL_IP}:${NPM_PORT_WEB}${C_CYN} $(printf '%*s' $npm_padding)│${C_RESET}"
    
    # Red Docker
    local net_info="🔗 Red Docker: ${COMMON_DOCKER_NETWORK}"
    local net_len=${#net_info}
    local net_padding=$((56 - net_len - 2))
    if [[ $net_padding -lt 0 ]]; then net_padding=0; fi
    echo -e "${C_CYN}│ ${C_YLW}🔗 Red Docker:${C_RESET} ${COMMON_DOCKER_NETWORK}${C_CYN} $(printf '%*s' $net_padding)│${C_RESET}"
    
    echo -e "${C_CYN}└──────────────────────────────────────────────────────────┘${C_RESET}"
}

# ====== Función para mostrar credenciales de manera segura ======
show_credentials() {
    local project_name="$1"
    local domain="${2:-}"
    
    print_section "📋 INSTRUCCIONES PARA EL PROYECTO"
    
    # Manejo seguro de ODOO_VERSIONS - compatible con proyectos existentes
    local versions_to_show=()
    
    # Opción 1: Usar variable ODOO_VERSIONS si existe y no está vacía
    if [[ -n "${ODOO_VERSIONS[@]+x}" ]] && [[ ${#ODOO_VERSIONS[@]} -gt 0 ]]; then
        versions_to_show=("${ODOO_VERSIONS[@]}")
    # Opción 2: Intentar obtener del .env del proyecto
    elif [[ -f "${PROJECT_DIR}/.env" ]]; then
        local env_versions=$(grep "^ODOO_VERSIONS=" "${PROJECT_DIR}/.env" 2>/dev/null | cut -d'=' -f2)
        if [[ -n "$env_versions" ]]; then
            IFS=' ' read -ra versions_to_show <<< "$env_versions"
        else
            # Valor por defecto para proyectos existentes sin versión explícita
            versions_to_show=("19")
        fi
    # Opción 3: Valor por defecto
    else
        versions_to_show=("19")
    fi
    
    if [[ -n "$domain" ]]; then
        print_info_box "🌐 ACCESO A ODOO" "URL: https://${domain}/\n\n🔑 Master Password: ${ADMIN_PASS}\n\n💡 Al acceder por primera vez:\n1. Usa el Master Password arriba\n2. Crea nueva base de datos\n3. Nombre: ${project_name}\n4. Usuario: ${ODOO_USER}\n5. Contraseña: ${ODOO_PASS}"
    else
        for ver in "${versions_to_show[@]}"; do
            # Obtener puerto dinámicamente con valor por defecto
            local port_var="ODOO_PORT_${ver}"
            local port="${!port_var:-8069}"
            
            print_info_box "🔵 ACCESO A ODOO v${ver}" "URL: http://${LOCAL_IP}:${port}\n\n🔑 Master Password: ${ADMIN_PASS}\n\n💡 Al acceder por primera vez:\n1. Usa el Master Password arriba\n2. Crea nueva base de datos\n3. Nombre: ${project_name}\n4. Usuario: ${ODOO_USER}\n5. Contraseña: ${ODOO_PASS}"
        done
    fi
    
    echo ""
    print_info_box "🔐 CREDENCIALES DE SEGURIDAD" "Master Password: ${ADMIN_PASS}\nUsuario Odoo: ${ODOO_USER}\nPassword Odoo: ${ODOO_PASS}\nUsuario PostgreSQL: ${PG_USER}\nPassword PostgreSQL: ${PG_PASS}"
    
    echo ""
    print_success_box "✅ CONFIGURACIÓN COMPLETA" "Proyecto: ${project_name}\nRuta: ${PROJECT_DIR}\nRed: ${COMMON_DOCKER_NETWORK}\n\n⚠️  Recuerda crear la BD al acceder por primera vez"
}

# ====== Cargar/Guardar configuración global ======
load_global_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        ok "✅ Configuración global cargada desde $CONFIG_FILE"
    else
        warn "⚠️  No hay configuración global guardada. Se usarán valores por defecto."
        # Valores por defecto compatibles con proyectos existentes
        BASE_DIR="${HOME}/odoo_projects"
        CUSTOM_ADDONS_PATH=""
        ENTERPRISE_PATH=""
        GLOBAL_PASSWORDS_FILE="${BASE_DIR}/.global_passwords.env"
    fi
    
    # Asegurar que BASE_DIR siempre tenga un valor para evitar errores
    export BASE_DIR="${BASE_DIR:-${HOME}/odoo_projects}"
}

save_global_config() {
    say "💾 Guardando configuración global..." "$C_CYN"
    cat > "$CONFIG_FILE" << EOF
# Configuración global de Odoo Docker Manager
# $(date)

BASE_DIR="${BASE_DIR}"
CUSTOM_ADDONS_PATH="${CUSTOM_ADDONS_PATH:-}"
ENTERPRISE_PATH="${ENTERPRISE_PATH:-}"
GLOBAL_PASSWORDS_FILE="${BASE_DIR}/.global_passwords.env"

# Panel NPM
NPM_PANEL_IP="192.168.18.205"
NPM_PORT_WEB="81"

# Red Docker común
COMMON_DOCKER_NETWORK="odoo-global-network"

# UID/GID fijos
FIXED_UID="1001"
FIXED_GID="1001"
EOF
    chmod 600 "$CONFIG_FILE"
    ok "✅ Configuración guardada en $CONFIG_FILE"
}

# ====== Gestión de contraseñas globales ======
init_global_passwords() {
    # Usar variable correcta con valor por defecto
    local passwords_file="${GLOBAL_PASSWORDS_FILE:-${BASE_DIR:-${HOME}/odoo_projects}/.global_passwords.env}"
    
    if [[ ! -f "$passwords_file" ]]; then
        say "🔐 Generando contraseñas globales..." "$C_CYN"
        
        # Generar contraseñas seguras
        local admin_pass=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9!@#$%^&*' | head -c 24)
        local odoo_pass=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 16)
        local pg_pass=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 16)
        
        # Crear directorio si no existe
        mkdir -p "$(dirname "$passwords_file")"
        
        cat > "$passwords_file" << EOF
# Contraseñas globales - Odoo Docker Manager
# $(date)
# ¡NO COMPARTIR ESTE ARCHIVO!

GLOBAL_ADMIN_PASS="${admin_pass}"
GLOBAL_ODOO_PASS="${odoo_pass}"
GLOBAL_PG_PASS="${pg_pass}"
BACKUP_ENCRYPTION_KEY="$(openssl rand -base64 32)"
EOF
        chmod 600 "$passwords_file"
        ok "✅ Contraseñas globales generadas y guardadas"
    fi
    
    # Cargar y exportar contraseñas
    if [[ -f "$passwords_file" ]]; then
        source "$passwords_file" 2>/dev/null || warn "⚠️  Error cargando contraseñas"
        export GLOBAL_ADMIN_PASS GLOBAL_ODOO_PASS GLOBAL_PG_PASS
        GLOBAL_PASSWORDS_FILE="$passwords_file"  # Actualizar variable global
    else
        warn "⚠️  No se encontró archivo de contraseñas: $passwords_file"
    fi
}

# ====== Configuración de rutas personalizadas ======
setup_custom_paths() {
    # Cargar configuración existente
    load_global_config
    
    # Si ya tenemos rutas válidas, usarlas
    if [[ -n "${BASE_DIR:-}" && -d "${BASE_DIR}" ]]; then
        return 0
    fi
    
    print_section "🗂️  CONFIGURACIÓN DE RUTAS"
    
    # Preguntar ruta base con valor por defecto
    local default_base="${HOME}/odoo_projects"
    read -p "Ruta base para proyectos [${default_base}]: " custom_base_dir
    BASE_DIR="${custom_base_dir:-$default_base}"
    BASE_DIR="${BASE_DIR/#\~/$HOME}"  # Expandir ~ si se usa
    
    # Validar y crear directorio
    mkdir -p "$BASE_DIR" || err "❌ No se pudo crear $BASE_DIR"
    
    # Inicializar contraseñas ANTES de guardar configuración
    init_global_passwords
    
    # Guardar configuración
    save_global_config
    
    export BASE_DIR
    ok "✅ Ruta base configurada: $BASE_DIR"
}

# ====== Función para actualizar rutas ======
update_paths_menu() {
    print_section "🔄 ACTUALIZAR RUTAS CONFIGURADAS"
    
    echo -e "${C_CYN}Rutas actuales:${C_RESET}"
    echo -e "  ${C_BLU}Base:${C_RESET} ${BASE_DIR:-No configurada}"
    echo -e "  ${C_BLU}Addons:${C_RESET} ${CUSTOM_ADDONS_PATH:-No configurado}"
    echo -e "  ${C_BLU}Enterprise:${C_RESET} ${ENTERPRISE_PATH:-No configurado}"
    echo ""
    
    local options=("Cambiar ruta base" "Cambiar ruta de addons" "Cambiar ruta enterprise" "Volver")
    print_menu "OPCIONES DE RUTAS" "${options[@]}"
    
    read -p "Selecciona opción [1-4]: " path_opt
    case "$path_opt" in
        1)
            read -p "Nueva ruta base: " new_base
            if [[ -n "$new_base" ]]; then
                BASE_DIR="${new_base/#\~/$HOME}"
                mkdir -p "$BASE_DIR"
                save_global_config
                ok "✅ Ruta base actualizada"
            fi
            ;;
        2)
            read -p "Nueva ruta de addons (vacío para eliminar): " new_addons
            CUSTOM_ADDONS_PATH="${new_addons/#\~/$HOME}"
            save_global_config
            ok "✅ Ruta de addons actualizada"
            ;;
        3)
            read -p "Nueva ruta enterprise (vacío para eliminar): " new_ent
            ENTERPRISE_PATH="${new_ent/#\~/$HOME}"
            save_global_config
            ok "✅ Ruta enterprise actualizada"
            ;;
        4)
            return
            ;;
    esac
}

# ====== Funciones para listar proyectos desde BASE_DIR ======
list_existing_projects() {
    local -n projects_array="$1"
    projects_array=()
    
    # Usar BASE_DIR con valor por defecto si no está definida
    local search_dir="${BASE_DIR:-${HOME}/odoo_projects}"
    
    if [[ -d "$search_dir" ]]; then
        for dir in "$search_dir"/*/; do
            if [[ -d "$dir" && -f "$dir/docker-compose.yml" ]]; then
                local proj_name=$(basename "$dir")
                projects_array+=("$proj_name")
            fi
        done
    fi
}

# ====== Función para seleccionar proyecto ======
select_project() {
    local prompt="$1"
    local -n selected_name="$2"
    local -n selected_dir="$3"
    
    local existing_projects=()
    list_existing_projects existing_projects
    
    if [[ ${#existing_projects[@]} -eq 0 ]]; then
        warn "No se encontraron proyectos en ${BASE_DIR:-${HOME}/odoo_projects}"
        return 1
    fi
    
    print_section "📋 PROYECTOS DISPONIBLES"
    echo -e "$prompt"
    local i=1
    for proj in "${existing_projects[@]}"; do
        echo -e "  ${C_GRN}$i)${C_RESET} ${C_BLU}$proj${C_RESET}"
        ((i++))
    done
    read -p "Selecciona el número del proyecto (0 para cancelar): " proj_num
    
    if [[ "$proj_num" -eq 0 ]]; then
        say "Operación cancelada." "$C_BLU"
        return 2
    fi
    
    local selected_proj_index=$((proj_num - 1))
    if [[ $selected_proj_index -lt 0 || $selected_proj_index -ge ${#existing_projects[@]} ]]; then
        warn "Número inválido."
        return 1
    fi
    
    selected_name="${existing_projects[$selected_proj_index]}"
    selected_dir="${BASE_DIR:-${HOME}/odoo_projects}/$selected_name"
    return 0
}

# ====== Dependencias ======
check_deps() {
    say "Verificando dependencias..." "$C_CYN"
    if ! command -v docker &>/dev/null; then
        err "Docker no está instalado. Instala con: sudo apt install docker.io -y"
    fi
    ok "Docker detectado"
    
    if ! docker compose version &>/dev/null; then
        err "Docker Compose plugin no disponible. Instala con: sudo apt install docker-compose-plugin -y"
    fi
    ok "Docker Compose detectado"
    
    if ! command -v curl &>/dev/null; then
        say "📦 Instalando curl para API NPM..." "$C_BLU"
        apt-get update >/dev/null
        apt-get install -y curl >/dev/null
    fi
    ok "curl detectado"
    
    if ! command -v jq &>/dev/null; then
        say "📦 Instalando jq para procesamiento JSON..." "$C_BLU"
        apt-get install -y jq >/dev/null
    fi
    ok "jq detectado"
}

# ====== FUNCIONES NGINX PROXY MANAGER ======

# Verificar si NPM está instalado
check_npm_installed() {
    if docker ps --format '{{.Names}}' | grep -q "^${NPM_CONTAINER}$"; then
        return 0
    else
        return 1
    fi
}

# Verificar si NPM está saludable
check_npm_healthy() {
    if ! check_npm_installed; then
        return 1
    fi
    
    local max_attempts=10
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s "http://${NPM_PANEL_IP}:${NPM_PORT_WEB}/api/" >/dev/null 2>&1; then
            return 0
        fi
        sleep 3
        ((attempt++))
    done
    return 1
}

# Función para configurar red común
setup_common_network() {
    say "🌐 Configurando red Docker común..." "$C_CYN"
    
    if ! docker network inspect "$COMMON_DOCKER_NETWORK" &>/dev/null; then
        docker network create \
            --driver bridge \
            --subnet=172.20.0.0/16 \
            --ip-range=172.20.1.0/24 \
            --gateway=172.20.0.1 \
            "$COMMON_DOCKER_NETWORK"
        ok "✅ Red común creada: $COMMON_DOCKER_NETWORK"
    else
        ok "✅ Red común ya existe: $COMMON_DOCKER_NETWORK"
    fi
    
    # Conectar NPM a la red común si está instalado
    if check_npm_installed; then
        if ! docker network inspect "$COMMON_DOCKER_NETWORK" | grep -q "$NPM_CONTAINER"; then
            docker network connect "$COMMON_DOCKER_NETWORK" "$NPM_CONTAINER"
            ok "✅ NPM conectado a la red común"
        fi
    fi
}

# Instalar Nginx Proxy Manager
install_npm() {
    say "🚀 Instalando Nginx Proxy Manager centralizado..." "$C_MAG"
    
    # Configurar red común primero
    setup_common_network
    
    # Crear directorios de datos
    mkdir -p "${NPM_DATA_DIR}/data"
    mkdir -p "${NPM_DATA_DIR}/letsencrypt"
    mkdir -p "${NPM_DATA_DIR}/mysql"
    
    # Configurar permisos
    chown -R "$FIXED_UID:$FIXED_GID" "${NPM_DATA_DIR}"
    
    # Crear docker-compose para NPM con red común
    cat > "${NPM_DATA_DIR}/docker-compose.yml" << EOF
version: '3.8'
services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    container_name: ${NPM_CONTAINER}
    restart: unless-stopped
    ports:
      - '${NPM_PORT_HTTP}:80'
      - '${NPM_PORT_HTTPS}:443'
      - '${NPM_PORT_WEB}:81'
      - '${NPM_PORT_SSL}:444'
    environment:
      DB_MYSQL_HOST: "db"
      DB_MYSQL_PORT: 3306
      DB_MYSQL_USER: "npm"
      DB_MYSQL_PASSWORD: "npm"
      DB_MYSQL_NAME: "npm"
      DISABLE_IPV6: "true"
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    networks:
      - ${COMMON_DOCKER_NETWORK}
    depends_on:
      - db

  db:
    image: 'jc21/mariadb-aria:latest'
    container_name: "${NPM_CONTAINER}-db"
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: 'npm'
      MYSQL_DATABASE: 'npm'
      MYSQL_USER: 'npm'
      MYSQL_PASSWORD: 'npm'
    volumes:
      - ./mysql:/var/lib/mysql
    networks:
      - ${COMMON_DOCKER_NETWORK}

networks:
  ${COMMON_DOCKER_NETWORK}:
    external: true
    name: ${COMMON_DOCKER_NETWORK}
EOF

    # Iniciar NPM
    cd "${NPM_DATA_DIR}"
    docker compose up -d
    
    # Esperar a que NPM esté listo
    say "⏳ Esperando a que Nginx Proxy Manager se inicie..." "$C_BLU"
    sleep 10
    
    if check_npm_healthy; then
        ok "✅ Nginx Proxy Manager instalado correctamente"
        say "🌐 Panel de control: http://${NPM_PANEL_IP}:${NPM_PORT_WEB}" "$C_MAG"
        say "🔐 Credenciales por defecto:" "$C_CYN"
        say "   Email:    admin@example.com" "$C_BLU"
        say "   Password: changeme" "$C_BLU"
        say "⚠️  Cambia las credenciales en tu primera entrada al panel" "$C_YLW"
    else
        err "❌ No se pudo iniciar Nginx Proxy Manager"
    fi
}

# Obtener token de autenticación NPM
get_npm_token() {
    local email="$1"
    local password="$2"
    
    local response=$(curl -s -X POST "http://${NPM_PANEL_IP}:${NPM_PORT_WEB}/api/tokens" \
        -H "Content-Type: application/json" \
        -d "{\"identity\":\"$email\",\"secret\":\"$password\"}" 2>/dev/null)
    
    if echo "$response" | jq -e '.token' >/dev/null 2>&1; then
        echo "$response" | jq -r '.token'
    else
        echo ""
    fi
}

# Configurar proxy host en NPM
setup_npm_proxy_host() {
    local domain="$1"
    local forward_host="$2"
    local forward_port="$3"
    local email="$4"
    
    say "🌐 Configurando proxy para ${domain}..." "$C_BLU"
    
    # Primero intentar con credenciales por defecto
    local token=$(get_npm_token "admin@example.com" "changeme")
    
    # Si falla, solicitar credenciales
    if [[ -z "$token" ]]; then
        warn "⚠️  Credenciales por defecto no funcionan. Necesito credenciales del panel NPM."
        read -p "Email del panel NPM: " npm_email
        read -sp "Password del panel NPM: " npm_password
        echo
        token=$(get_npm_token "$npm_email" "$npm_password")
        
        if [[ -z "$token" ]]; then
            warn "⚠️  No se pudo autenticar con NPM. Configura manualmente desde el panel:"
            say "   Panel: http://${NPM_PANEL_IP}:${NPM_PORT_WEB}" "$C_BLU"
            say "   Domain Names: ${domain}" "$C_BLU"
            say "   Forward Hostname/IP: ${forward_host}" "$C_BLU"
            say "   Forward Port: ${forward_port}" "$C_BLU"
            say "   ✅ Activar: Block Common Exploits, Websockets Support" "$C_BLU"
            say "   🔐 SSL: Request New SSL Certificate" "$C_BLU"
            return 1
        fi
    fi
    
    # Crear proxy host
    local proxy_data=$(cat << EOF
{
    "domain_names": ["${domain}"],
    "forward_scheme": "http",
    "forward_host": "${forward_host}",
    "forward_port": ${forward_port},
    "caching_enabled": false,
    "block_exploits": true,
    "allow_websocket_upgrade": true,
    "access_list_id": "0",
    "certificate_id": null,
    "ssl_forced": true,
    "http2_support": true,
    "hsts_enabled": true,
    "hsts_subdomains": false,
    "advanced_config": "",
    "locations": [],
    "meta": {
        "letsencrypt_email": "${email}",
        "letsencrypt_agree": true
    }
}
EOF
    )
    
    local response=$(curl -s -X POST "http://${NPM_PANEL_IP}:${NPM_PORT_WEB}/api/nginx/proxy-hosts" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $token" \
        -d "$proxy_data" 2>/dev/null)
    
    if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        local host_id=$(echo "$response" | jq -r '.id')
        ok "✅ Proxy host creado (ID: ${host_id})"
        
        # Solicitar certificado SSL
        say "🔐 Solicitando certificado SSL Let's Encrypt..." "$C_BLU"
        local cert_response=$(curl -s -X POST "http://${NPM_PANEL_IP}:${NPM_PORT_WEB}/api/nginx/proxy-hosts/${host_id}/certificate" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $token" \
            -d "{\"meta\":{\"letsencrypt_email\":\"${email}\",\"letsencrypt_agree\":true},\"provider\":\"letsencrypt\"}" 2>/dev/null)
        
        if echo "$cert_response" | jq -e '.success' >/dev/null 2>&1; then
            ok "✅ Certificado SSL solicitado. Puede tardar unos minutos en generarse."
        else
            warn "⚠️  No se pudo solicitar certificado automáticamente. Solicítalo manualmente desde el panel."
        fi
        
        return 0
    else
        warn "⚠️  No se pudo crear proxy host vía API. Configura manualmente desde el panel."
        say "   Panel: http://${NPM_PANEL_IP}:${NPM_PORT_WEB}" "$C_BLU"
        return 1
    fi
}

# Listar proyectos configurados en NPM
list_npm_projects() {
    say "📋 Proyectos registrados en Nginx Proxy Manager:" "$C_MAG"
    
    if ! check_npm_installed; then
        warn "Nginx Proxy Manager no está instalado"
        return 1
    fi
    
    # Intentar obtener lista vía API
    local token=$(get_npm_token "admin@example.com" "changeme")
    
    if [[ -n "$token" ]]; then
        local response=$(curl -s "http://${NPM_PANEL_IP}:${NPM_PORT_WEB}/api/nginx/proxy-hosts" \
            -H "Authorization: Bearer $token" 2>/dev/null)
        
        if echo "$response" | jq -e '.[]' >/dev/null 2>&1; then
            echo "$response" | jq -r '.[] | "  🌐 \(.domain_names[0]) → \(.forward_host):\(.forward_port) [SSL: \(.ssl_forced)]"'
        else
            say "  ℹ️  No hay proxies configurados o no se pudo obtener la lista" "$C_BLU"
        fi
    else
        say "  ℹ️  Accede al panel para ver los proyectos: http://${NPM_PANEL_IP}:${NPM_PORT_WEB}" "$C_BLU"
    fi
    
    # También listar proyectos desde directorio BASE_DIR
    say "📁 Proyectos en directorio base (${BASE_DIR:-${HOME}/odoo_projects}):" "$C_MAG"
    if [[ -d "${BASE_DIR:-${HOME}/odoo_projects}" ]]; then
        local count=0
        for dir in "${BASE_DIR:-${HOME}/odoo_projects}"/*/; do
            if [[ -d "$dir" && -f "$dir/docker-compose.yml" ]]; then
                local proj_name=$(basename "$dir")
                say "  📦 ${proj_name}" "$C_CYN"
                ((count++))
            fi
        done
        if [[ $count -eq 0 ]]; then
            say "  ℹ️  No hay proyectos creados" "$C_BLU"
        fi
    fi
}

# Remover proyecto de NPM (seguro - no falla si NPM no está instalado)
remove_from_npm() {
    local project_name="$1"
    
    if ! check_npm_installed; then
        say "ℹ️  Nginx Proxy Manager no está instalado, omitiendo eliminación de dominio" "$C_BLU"
        return 0
    fi
    
    say "🗑️  Buscando configuración para proyecto '${project_name}' en NPM..." "$C_YLW"
    
    local token=$(get_npm_token "admin@example.com" "changeme")
    
    if [[ -z "$token" ]]; then
        warn "⚠️  No se pudo autenticar. Elimina manualmente desde el panel si es necesario."
        say "   Panel: http://${NPM_PANEL_IP}:${NPM_PORT_WEB}" "$C_BLU"
        return 0
    fi
    
    local response=$(curl -s "http://${NPM_PANEL_IP}:${NPM_PORT_WEB}/api/nginx/proxy-hosts" \
        -H "Authorization: Bearer $token" 2>/dev/null)
    
    local host_id=$(echo "$response" | jq -r '.[] | select(.forward_host | contains("'${project_name}'")) | .id' 2>/dev/null | head -1)
    
    if [[ -n "$host_id" ]]; then
        local delete_response=$(curl -s -X DELETE "http://${NPM_PANEL_IP}:${NPM_PORT_WEB}/api/nginx/proxy-hosts/${host_id}" \
            -H "Authorization: Bearer $token" 2>/dev/null)
        
        if echo "$delete_response" | jq -e '.success' >/dev/null 2>&1; then
            ok "✅ Proyecto removido del proxy NPM"
        else
            warn "⚠️  No se pudo eliminar automáticamente. Elimina manualmente desde el panel si es necesario."
        fi
    else
        say "ℹ️  No se encontró configuración en NPM para el proyecto '${project_name}'" "$C_BLU"
    fi
    
    return 0
}

# Verificar si un dominio ya está en uso en NPM
check_domain_in_use() {
    local domain="$1"
    
    if ! check_npm_installed; then
        return 1
    fi
    
    local token=$(get_npm_token "admin@example.com" "changeme")
    
    if [[ -n "$token" ]]; then
        local response=$(curl -s "http://${NPM_PANEL_IP}:${NPM_PORT_WEB}/api/nginx/proxy-hosts" \
            -H "Authorization: Bearer $token" 2>/dev/null)
        
        if echo "$response" | jq -e '.[]' >/dev/null 2>&1; then
            local existing_domains=$(echo "$response" | jq -r '.[] | .domain_names[]' 2>/dev/null)
            if echo "$existing_domains" | grep -q "^${domain}$"; then
                return 0
            fi
        fi
    fi
    
    return 1
}

# ====== Funciones auxiliares ======
ask_secret() {
    local prompt="$1"; local varname="$2"; local def="desarrollo"
    read -s -p "$prompt (Enter para '$def'): " tmp
    echo
    tmp="${tmp:-$def}"
    eval "$varname=\"$tmp\""
}

ensure_port_free() {
    local port="$1"; local label="$2"
    local max_attempts=5
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]] && ss -ltn 2>/dev/null | awk '{print $4}' | grep -q ":${port}$"; do
        warn "El puerto ${port} para ${label} está en uso."
        if [[ $attempt -eq $max_attempts ]]; then
            err "No se pudo encontrar un puerto libre para ${label} después de ${max_attempts} intentos."
        fi
        read -p "Introduce otro puerto para ${label}: " port
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
            warn "Puerto inválido. Debe ser un número entre 1024 y 65535."
            continue
        fi
        ((attempt++))
    done
    
    echo "$port"
}

detect_ip() {
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [[ -z "${ip:-}" ]] && ip="127.0.0.1"
    echo "$ip"
}

print_containers_table() {
    local proj="$1"
    say "📊 Contenedores activos (filtro: ${proj}_*):" "$C_CYN"
    printf "%-32s %-12s %-20s\n" "CONTAINER NAME" "STATUS" "PORTS"
    printf -- "--------------------------------------------------------------\n"
    docker ps --format '{{.Names}}\t{{.Status}}\t{{.Ports}}' | grep "^${proj}_" || true
    echo
}

# ====== Gestión de Versiones de PostgreSQL ======
get_postgres_version() {
    local odoo_version="$1"
    case "$odoo_version" in
        "16"|"17") echo "13";;
        "18"|"19") echo "15";;
        "20"|"21") echo "16";;
        *) echo "15";;  # Por defecto para compatibilidad
    esac
}

# ====== Cálculo Automático de Recursos ======
calculate_optimal_resources() {
    local total_ram=$(free -b | awk '/^Mem:/{print $2}')
    local cpu_cores=$(nproc)
    
    # Cálculos automáticos basados en recursos del sistema
    local workers=$(( (cpu_cores * 2) + 1 ))
    local ram_per_worker=$(( total_ram / workers / 2 ))  # 50% para Odoo
    
    # Límites basados en recursos disponibles
    if [[ $total_ram -lt 8589934592 ]]; then  # < 8GB
        CUSTOM_LIMIT_MEM_HARD="2147483648"    # 2GB
        CUSTOM_LIMIT_MEM_SOFT="1073741824"    # 1GB
    elif [[ $total_ram -lt 17179869184 ]]; then  # < 16GB
        CUSTOM_LIMIT_MEM_HARD="4294967296"    # 4GB
        CUSTOM_LIMIT_MEM_SOFT="2147483648"    # 2GB
    else
        CUSTOM_LIMIT_MEM_HARD="8589934592"    # 8GB
        CUSTOM_LIMIT_MEM_SOFT="4294967296"    # 4GB
    fi
    
    export CUSTOM_WORKERS=$workers
    export CUSTOM_LIMIT_MEM_HARD=$CUSTOM_LIMIT_MEM_HARD
    export CUSTOM_LIMIT_MEM_SOFT=$CUSTOM_LIMIT_MEM_SOFT
    
    say "🔧 Recursos calculados automáticamente:" "$C_MAG"
    say "   Workers: $workers" "$C_BLU"
    say "   Memoria por worker: $((CUSTOM_LIMIT_MEM_HARD / 1024 / 1024 / 1024))GB" "$C_BLU"
}

# ====== Sistema de Backup Automático ======
create_backup_system() {
    local project_dir="$1"
    local project_name="$2"
    
    say "🛡️  Creando sistema de backups automáticos..." "$C_CYN"
    
    cat > "${project_dir}/backup.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
BACKUP_DIR="/opt/backups/${PROJECT_NAME}"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=7

mkdir -p "$BACKUP_DIR"

echo "🛡️  Iniciando backup del proyecto: $PROJECT_NAME"
echo "📅 Fecha: $(date)"

# Backup de PostgreSQL
for ver in 16 17 18 19 20; do
    container_name="${PROJECT_NAME}_db${ver}"
    if docker ps | grep -q "$container_name"; then
        echo "🔍 Haciendo backup de PostgreSQL v${ver}..."
        if docker exec "$container_name" pg_dumpall -U desarrollo | gzip > "${BACKUP_DIR}/postgres_v${ver}_${DATE}.sql.gz"; then
            echo "✅ PostgreSQL v${ver} backup completado"
        else
            echo "❌ Error en backup de PostgreSQL v${ver}"
        fi
    fi
done

# Backup de filestore
if [ -d "./filestore" ]; then
    echo "📁 Haciendo backup de filestore..."
    if tar -czf "${BACKUP_DIR}/filestore_${DATE}.tar.gz" ./filestore_v*/ 2>/dev/null; then
        echo "✅ Filestore backup completado"
    else
        echo "❌ Error en backup de filestore"
    fi
fi

# Backup de configuración
echo "⚙️  Haciendo backup de configuración..."
tar -czf "${BACKUP_DIR}/config_${DATE}.tar.gz" ./.env ./docker-compose.yml ./odoo-config_v*/ 2>/dev/null || true

# Limpiar backups antiguos
echo "🧹 Limpiando backups antiguos (>${RETENTION_DAYS} días)..."
find "$BACKUP_DIR" -name "*.gz" -mtime +$RETENTION_DAYS -delete

# Informe final
BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
echo "✅ Backup completado: ${BACKUP_DIR}"
echo "📊 Tamaño total: $BACKUP_SIZE"
echo "💾 Archivos creados:"
find "$BACKUP_DIR" -name "*${DATE}*" -exec ls -lh {} \; | awk '{print "   " $9 " (" $5 ")"}'
EOF

    chmod +x "${project_dir}/backup.sh"
    
    # Agregar al crontab si no existe
    local cron_entry="0 2 * * * ${project_dir}/backup.sh"
    if ! crontab -l 2>/dev/null | grep -q "$cron_entry"; then
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
    fi
    
    # Crear script de restauración
    cat > "${project_dir}/restore_backup.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
BACKUP_DIR="/opt/backups/${PROJECT_NAME}"

echo "🔄 Script de restauración para: $PROJECT_NAME"
echo "📂 Backup directory: $BACKUP_DIR"

if [ ! -d "$BACKUP_DIR" ]; then
    echo "❌ No se encontró directorio de backups: $BACKUP_DIR"
    exit 1
fi

# Listar backups disponibles
echo "📋 Backups disponibles:"
ls -lt "$BACKUP_DIR"/*.gz 2>/dev/null | head -10 | awk '{print NR ". " $9}'

read -p "Selecciona el número del backup a restaurar: " backup_num

BACKUP_FILE=$(ls -t "$BACKUP_DIR"/*.gz | sed -n "${backup_num}p")

if [ -z "$BACKUP_FILE" ]; then
    echo "❌ Backup no válido"
    exit 1
fi

echo "🔍 Backup seleccionado: $BACKUP_FILE"
read -p "¿Continuar con la restauración? (s/n): " confirm

if [[ ! "$confirm" =~ ^[sS]$ ]]; then
    echo "❌ Restauración cancelada"
    exit 0
fi

# Parar contenedores
echo "🛑 Parando contenedores..."
docker compose down

# Restaurar
echo "🔄 Restaurando desde backup..."
tar -xzf "$BACKUP_FILE" -C /tmp/backup_restore/

echo "✅ Restauración completada. Iniciando contenedores..."
docker compose up -d

echo "🎉 Restauración finalizada. Verifica el estado con: docker compose ps"
EOF

    chmod +x "${project_dir}/restore_backup.sh"
    ok "Sistema de backups configurado (ejecución diaria a las 2 AM)"
}

# ====== Sistema de Logs Centralizado ======
setup_log_management() {
    local project_dir="$1"
    
    say "📊 Configurando gestión de logs..." "$C_CYN"
    
    # Configurar logrotate
    cat > "/etc/logrotate.d/odoo-${PROJECT_NAME}" << EOF
${project_dir}/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
    create 644 ${FIXED_UID} ${FIXED_GID}
}
EOF

    # Script para análisis de logs
    cat > "${project_dir}/log_analyzer.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
LOG_DIR="${PROJECT_DIR}/logs"

echo "📊 Análisis de Logs - Proyecto: $PROJECT_NAME"
echo "=============================================="

# Verificar si hay logs recientes
if [ ! -d "$LOG_DIR" ] || [ -z "$(find "$LOG_DIR" -name "*.log" -mtime -1)" ]; then
    echo "ℹ️  No hay logs recientes en las últimas 24h"
    exit 0
fi

# Errores en las últimas 24h
echo ""
echo "🚨 ERRORES RECIENTES (últimas 24h):"
echo "-----------------------------------"
find "$LOG_DIR" -name "*.log" -mtime -1 -exec grep -i "error\|exception\|traceback" {} \; | tail -20

# Rendimiento - consultas lentas
echo ""
echo "⏱️  CONSULTAS LENTAS (>1000ms):"
echo "------------------------------"
find "$LOG_DIR" -name "*.log" -mtime -1 -exec grep "DEBUG.*SELECT.*ms" {} \; | \
    awk '{$0 ~ /([0-9]+) ms/; if ($0 ~ /([0-9]{4,}) ms/) print}' | tail -10

# Uso de memoria y CPU
echo ""
echo "💾 ESTADO ACTUAL DE CONTENEDORES:"
echo "--------------------------------"
docker stats --no-stream ${PROJECT_NAME}_* --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" 2>/dev/null || \
    echo "⚠️  No se pudieron obtener estadísticas"

# Resumen de logs por nivel
echo ""
echo "📈 RESUMEN POR NIVEL DE LOG:"
echo "---------------------------"
for level in ERROR WARNING INFO DEBUG; do
    count=$(find "$LOG_DIR" -name "*.log" -mtime -1 -exec grep -c "$level" {} \; | awk '{sum+=$1} END {print sum}')
    echo "   $level: $count"
done

# Espacio en disco de logs
echo ""
echo "💿 USO DE DISCO EN LOGS:"
echo "-----------------------"
du -sh "$LOG_DIR"
find "$LOG_DIR" -name "*.log" -exec ls -lh {} \; | head -5 | awk '{print "   " $9 " (" $5 ")"}'
EOF

    chmod +x "${project_dir}/log_analyzer.sh"
    
    # Script de monitorización en tiempo real
    cat > "${project_dir}/monitor.sh" << 'EOF'
#!/bin/bash
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

echo "🔍 Monitorización en tiempo real - $PROJECT_NAME"
echo "Presiona Ctrl+C para salir"
echo ""

while true; do
    clear
    echo "🕐 $(date)"
    echo "=========================================="
    
    # Estado de contenedores
    echo "🐳 CONTENEDORES:"
    docker ps --filter "name=${PROJECT_NAME}_" --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}" 2>/dev/null || echo "   No hay contenedores"
    
    # Uso de recursos
    echo ""
    echo "📊 RECURSOS:"
    docker stats --no-stream --filter "name=${PROJECT_NAME}_" --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.PIDs}}" 2>/dev/null || echo "   No se pudieron obtener stats"
    
    # Logs recientes
    echo ""
    echo "📝 LOGS RECIENTES:"
    docker logs --tail 3 "${PROJECT_NAME}_odoo${1:-19}" 2>/dev/null | tail -3 || echo "   No se pudieron obtener logs"
    
    sleep 5
done
EOF

    chmod +x "${project_dir}/monitor.sh"
    ok "Sistema de logs y monitorización configurado"
}

# ====== Sistema de Actualización Automática ======
add_update_system() {
    local project_dir="$1"
    
    cat > "${project_dir}/update.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

echo "🔄 Iniciando actualización del proyecto: $PROJECT_NAME"
echo "⏰ $(date)"

# Backup antes de actualizar
echo "🛡️  Creando backup preventivo..."
if [ -f "./backup.sh" ]; then
    ./backup.sh
else
    echo "⚠️  Script de backup no encontrado, continuando sin backup..."
fi

# Parar servicios
echo "🛑 Parando servicios..."
docker compose down

# Actualizar imágenes
echo "📥 Actualizando imágenes Docker..."
docker compose pull

# Reconstruir servicios si es necesario
echo "🔨 Reconstruyendo servicios..."
docker compose up -d --build

# Limpiar
echo "🧹 Limpiando recursos no utilizados..."
docker image prune -f

# Verificar estado
echo "🔍 Verificando estado..."
sleep 10
docker compose ps

echo "✅ Actualización completada: $(date)"
echo "🌍 Verifica el funcionamiento en la URL de tu proyecto"
EOF

    chmod +x "${project_dir}/update.sh"
    ok "Sistema de actualización configurado"
}

# ====== Sistema de Plugins/Extensiones ======
setup_plugin_system() {
    local project_dir="$1"
    
    mkdir -p "${project_dir}/plugins"
    
    # Plugin para módulos de IA
    cat > "${project_dir}/plugins/ai_enhancements.sh" << 'EOF'
#!/bin/bash
# Plugin para mejorar módulos de IA
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

install_ai_dependencies() {
    echo "🧠 Instalando dependencias para IA..."
    
    for ver in 16 17 18 19 20; do
        container_name="${PROJECT_NAME}_odoo${ver}"
        if docker ps | grep -q "$container_name"; then
            echo "🔧 Instalando en Odoo v${ver}..."
            docker exec "$container_name" pip install torch transformers sentence-transformers scikit-learn pandas numpy || \
                echo "⚠️  Algunas dependencias no se pudieron instalar en v${ver}"
        fi
    done
}

configure_ai_settings() {
    echo "⚙️  Configurando parámetros para IA..."
    
    # Añadir configuraciones específicas para IA en odoo.conf
    for ver in 16 17 18 19 20; do
        conf_file="${PROJECT_DIR}/odoo-config_v${ver}/odoo.conf"
        if [ -f "$conf_file" ]; then
            if ! grep -q "\[ai_enhancements\]" "$conf_file"; then
                cat >> "$conf_file" << 'AI_CONFIG'

; === AI ENHANCEMENTS ===
[ai_enhancements]
; Configuración para módulos de IA
ai_timeout = 300
ai_max_tokens = 4000
ai_model = gpt-3.5-turbo
vector_search_limit = 100
AI_CONFIG
                echo "✅ Configuración IA añadida a v${ver}"
            fi
        fi
    done
}

enable_ai_features() {
    echo "🚀 Habilitando características de IA..."
    
    # PostgreSQL ya incluye pgvector en la imagen pgvector/pgvector
    for ver in 16 17 18 19 20; do
        db_container="${PROJECT_NAME}_db${ver}"
        if docker ps | grep -q "$db_container"; then
            echo "🔍 PostgreSQL v${ver} ya incluye pgvector (imagen: pgvector/pgvector)"
        fi
    done
}

case "${1:-}" in
    "install")
        install_ai_dependencies
        configure_ai_settings
        enable_ai_features
        ;;
    "update")
        install_ai_dependencies
        ;;
    *)
        echo "Uso: $0 {install|update}"
        exit 1
        ;;
esac

echo "✅ Plugin de IA configurado correctamente"
EOF

    # Plugin de optimización de rendimiento
    cat > "${project_dir}/plugins/performance_tuning.sh" << 'EOF'
#!/bin/bash
# Plugin para optimización de rendimiento
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

apply_performance_tuning() {
    echo "⚡ Aplicando optimizaciones de rendimiento..."
    
    # Optimizar configuración de PostgreSQL
    for ver in 16 17 18 19 20; do
        pg_dir="${PROJECT_DIR}/postgres_v${ver}"
        if [ -d "$pg_dir" ]; then
            mkdir -p "$pg_dir/conf"
            cat > "$pg_dir/conf/performance.conf" << 'PG_PERF'
# Optimizaciones de rendimiento PostgreSQL
effective_cache_size = 4GB
shared_buffers = 2GB
work_mem = 16MB
maintenance_work_mem = 1GB
random_page_cost = 1.1
effective_io_concurrency = 200
max_worker_processes = 8
max_parallel_workers_per_gather = 4
max_parallel_workers = 8
PG_PERF
            echo "✅ Configuración de rendimiento para PostgreSQL v${ver}"
        fi
    done
    
    # Optimizar configuración de Odoo
    for ver in 16 17 18 19 20; do
        conf_file="${PROJECT_DIR}/odoo-config_v${ver}/odoo.conf"
        if [ -f "$conf_file" ]; then
            # Añadir configuraciones de rendimiento si no existen
            if ! grep -q "\[performance\]" "$conf_file"; then
                cat >> "$conf_file" << 'ODOO_PERF'

; === PERFORMANCE OPTIMIZATIONS ===
[performance]
; Optimizaciones para alto rendimiento
preload_modules = base,web
workers = $(( $(nproc) * 2 + 1 ))
max_cron_threads = 2
limit_memory_hard = 10737418240
limit_memory_soft = 5368709120
limit_time_cpu = 600
limit_time_real = 1200
limit_time_real_cron = 1800
ODOO_PERF
                echo "✅ Optimizaciones aplicadas a Odoo v${ver}"
            fi
        fi
    done
}

case "${1:-}" in
    "apply")
        apply_performance_tuning
        ;;
    *)
        echo "Uso: $0 apply"
        exit 1
        ;;
esac

echo "✅ Optimizaciones de rendimiento aplicadas"
EOF

    # Hacer ejecutables los plugins
    chmod +x "${project_dir}/plugins/"*.sh
    
    # Script de gestión de plugins
    cat > "${project_dir}/manage_plugins.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGINS_DIR="${PROJECT_DIR}/plugins"

echo "🧩 Gestor de Plugins - $PROJECT_DIR"
echo "=================================="

list_plugins() {
    echo "📋 Plugins disponibles:"
    local i=1
    for plugin in "$PLUGINS_DIR"/*.sh; do
        if [ -f "$plugin" ]; then
            echo "  $i) $(basename "$plugin" .sh)"
            ((i++))
        fi
    done
}

install_plugin() {
    local plugin_name="$1"
    local plugin_file="$PLUGINS_DIR/${plugin_name}.sh"
    
    if [ ! -f "$plugin_file" ]; then
        echo "❌ Plugin no encontrado: $plugin_name"
        return 1
    fi
    
    echo "🚀 Instalando plugin: $plugin_name"
    "$plugin_file" install
}

update_plugin() {
    local plugin_name="$1"
    local plugin_file="$PLUGINS_DIR/${plugin_name}.sh"
    
    if [ ! -f "$plugin_file" ]; then
        echo "❌ Plugin no encontrado: $plugin_name"
        return 1
    fi
    
    echo "🔄 Actualizando plugin: $plugin_name"
    "$plugin_file" update
}

case "${1:-}" in
    "list")
        list_plugins
        ;;
    "install")
        if [ -z "${2:-}" ]; then
            echo "❌ Debes especificar el nombre del plugin"
            exit 1
        fi
        install_plugin "$2"
        ;;
    "update")
        if [ -z "${2:-}" ]; then
            echo "❌ Debes especificar el nombre del plugin"
            exit 1
        fi
        update_plugin "$2"
        ;;
    *)
        echo "Uso: $0 {list|install|update} [plugin_name]"
        echo ""
        list_plugins
        ;;
esac
EOF

    chmod +x "${project_dir}/manage_plugins.sh"
    ok "Sistema de plugins configurado"
}

# ====== Verificaciones para Producción ======
add_production_checks() {
    local project_dir="$1"
    
    cat > "${project_dir}/production_checklist.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

echo "🔍 Verificando configuración para producción: $PROJECT_NAME"
echo "=================================================="

ALL_CHECKS_PASSED=true

check_password_strength() {
    local pass="$1" type="$2"
    local score=0
    
    if [ ${#pass} -ge 12 ]; then ((score++)); fi
    if [[ "$pass" =~ [A-Z] ]]; then ((score++)); fi
    if [[ "$pass" =~ [a-z] ]]; then ((score++)); fi
    if [[ "$pass" =~ [0-9] ]]; then ((score++)); fi
    if [[ "$pass" =~ [!@#$%^&*] ]]; then ((score++)); fi
    
    case $score in
        5) echo "✅ $type: Excelente";;
        4) echo "✅ $type: Bueno";;
        3) echo "⚠️  $type: Moderado";;
        *) echo "❌ $type: Débil (score: $score/5)"; return 1;;
    esac
    return 0
}

check_ssl_certificates() {
    local cert_file="./nginx/ssl/cert.pem"
    local key_file="./nginx/ssl/key.pem"
    
    if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ]; then
        echo "❌ Certificados SSL: No encontrados"
        return 1
    fi
    
    # Verificar certificado
    if openssl x509 -in "$cert_file" -text -noout &>/dev/null; then
        local expiry=$(openssl x509 -in "$cert_file" -enddate -noout | cut -d= -f2)
        echo "✅ Certificados SSL: Válido (Expira: $expiry)"
    else
        echo "❌ Certificados SSL: Inválido"
        return 1
    fi
}

check_backups() {
    local backup_dir="/opt/backups/${PROJECT_NAME}"
    
    if [ ! -d "$backup_dir" ]; then
        echo "❌ Backups: Directorio no existe"
        return 1
    fi
    
    local recent_backups=$(find "$backup_dir" -name "*.gz" -mtime -1 | wc -l)
    if [ "$recent_backups" -gt 0 ]; then
        echo "✅ Backups: Recientes encontrados ($recent_backups)"
    else
        echo "❌ Backups: No hay backups recientes"
        return 1
    fi
}

check_container_health() {
    echo "🐳 Estado de contenedores:"
    
    local all_healthy=true
    while read -r container; do
        local status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "unknown")
        case "$status" in
            "healthy") echo "   ✅ $container: $status";;
            "unhealthy") 
                echo "   ❌ $container: $status"
                all_healthy=false
                ;;
            *) echo "   ⚠️  $container: $status";;
        esac
    done < <(docker ps --filter "name=${PROJECT_NAME}_" --format "{{.Names}}")
    
    if [ "$all_healthy" = false ]; then
        return 1
    fi
}

check_security_headers() {
    if [ -f "./nginx/nginx.conf" ] && grep -q "Strict-Transport-Security" "./nginx/nginx.conf"; then
        echo "✅ Headers de seguridad: Configurados"
    else
        echo "❌ Headers de seguridad: No configurados"
        return 1
    fi
}

# Ejecutar verificaciones
echo ""
echo "📋 EJECUTANDO VERIFICACIONES..."
echo ""

source ./.env 2>/dev/null || {
    echo "❌ No se pudo cargar el archivo .env"
    exit 1
}

check_password_strength "${ADMIN_PASS:-}" "Master Password" || ALL_CHECKS_PASSED=false
check_password_strength "${ODOO_PASS:-}" "Password Odoo" || ALL_CHECKS_PASSED=false
check_ssl_certificates || ALL_CHECKS_PASSED=false
check_backups || ALL_CHECKS_PASSED=false
check_container_health || ALL_CHECKS_PASSED=false
check_security_headers || ALL_CHECKS_PASSED=false

echo ""
echo "=================================================="
if [ "$ALL_CHECKS_PASSED" = true ]; then
    echo "🎉 TODAS LAS VERIFICACIONES PASARON"
    echo "✅ El entorno está listo para producción"
else
    echo "⚠️  ALGUNAS VERIFICACIONES FALLARON"
    echo "🔧 Revisa las configuraciones antes de pasar a producción"
fi
EOF

    chmod +x "${project_dir}/production_checklist.sh"
    ok "Verificaciones de producción configuradas"
}

# ====== Funciones originales del script (actualizadas y seguras) ======

setup_fixed_uids() {
    say "🔧 Configurando UID/GID fijos $FIXED_UID:$FIXED_GID..." "$C_CYN"
    
    # Solo crear si no existen
    if ! getent group "$FIXED_GID" >/dev/null; then
        say "  👥 Creando grupo con GID $FIXED_GID..." "$C_BLU"
        groupadd -g "$FIXED_GID" odoo_docker_group 2>/dev/null || true
    fi
    
    if ! getent passwd "$FIXED_UID" >/dev/null; then
        say "  👤 Creando usuario con UID $FIXED_UID..." "$C_BLU"
        useradd -u "$FIXED_UID" -g "$FIXED_GID" -r -s /bin/false -M -d /nonexistent odoo_docker_user 2>/dev/null || true
    fi
    
    # Exportar variables globalmente
    export ODOO_UID="$FIXED_UID"
    export PG_UID="$FIXED_UID"
    export FIXED_UID FIXED_GID
    
    ok "✅ UID/GID fijos configurados: $FIXED_UID:$FIXED_GID"
}

fix_permissions_with_fixed_uids() {
    local project_dir="$1"
    say "🔧 Aplicando permisos con UID/GID fijos $FIXED_UID:$FIXED_GID..." "$C_CYN"
    
    # Obtener variables del entorno del proyecto si existe
    local project_env="${project_dir}/.env"
    local odoo_versions=("19")  # Valor por defecto para compatibilidad
    
    if [[ -f "$project_env" ]]; then
        source "$project_env"
        
        # Intentar obtener ODOO_VERSIONS del .env
        if [[ -n "${ODOO_VERSIONS:-}" ]]; then
            IFS=' ' read -ra odoo_versions <<< "$ODOO_VERSIONS"
        fi
    fi
    
    # Usar variables globales como fallback
    local odoo_uid="${ODOO_UID:-$FIXED_UID}"
    local odoo_gid="${PG_UID:-$FIXED_GID}"
    
    for ver in "${odoo_versions[@]}"; do
        # Solo aplicar si el directorio existe
        [[ -d "${project_dir}/filestore_v${ver}" ]] && {
            chown -R "${odoo_uid}:${odoo_gid}" "${project_dir}/filestore_v${ver}" 2>/dev/null || true
            chmod -R 755 "${project_dir}/filestore_v${ver}" 2>/dev/null || true
        }
        
        [[ -d "${project_dir}/logs" ]] && {
            chown -R "${odoo_uid}:${odoo_gid}" "${project_dir}/logs" 2>/dev/null || true
            chmod -R 755 "${project_dir}/logs" 2>/dev/null || true
        }
        
        [[ -d "${project_dir}/odoo-config_v${ver}" ]] && {
            chown -R "${odoo_uid}:${odoo_gid}" "${project_dir}/odoo-config_v${ver}" 2>/dev/null || true
            chmod -R 755 "${project_dir}/odoo-config_v${ver}" 2>/dev/null || true
        }
        
        # Verificar INCLUDE_ENT
        if [[ "${INCLUDE_ENT:-no}" == "yes" ]] && [[ -d "${project_dir}/enterprise_v${ver}" ]]; then
            chown -R "${odoo_uid}:${odoo_gid}" "${project_dir}/enterprise_v${ver}" 2>/dev/null || true
            chmod -R 755 "${project_dir}/enterprise_v${ver}" 2>/dev/null || true
        fi
        
        [[ -d "${project_dir}/postgres_v${ver}" ]] && {
            chown -R "${odoo_uid}:${odoo_gid}" "${project_dir}/postgres_v${ver}" 2>/dev/null || true
            chmod -R 700 "${project_dir}/postgres_v${ver}" 2>/dev/null || true
        }
    done
    
    ok "✅ Permisos aplicados con UID/GID $odoo_uid:$odoo_gid"
}

prompt_versions() {
    print_section "📦 SELECCIÓN DE VERSIÓN"
    
    echo -e "Selecciona la versión de Odoo:"
    echo -e "  ${C_GRN}1)${C_RESET} ${C_BLU}18${C_RESET}"
    echo -e "  ${C_GRN}2)${C_RESET} ${C_BLU}19${C_RESET}"
    read -p "Opción [1-2]: " optv
    case "$optv" in
        1) ODOO_VERSIONS=("18");;
        2) ODOO_VERSIONS=("19");;
        *) err "Opción no válida";;
    esac
    
    # Inicializar variables de puertos para cada versión
    for ver in "${ODOO_VERSIONS[@]}"; do
        eval "ODOO_PORT_${ver}=\"\""
        eval "PG_PORT_${ver}=\"\""
    done
}

prompt_config() {
    print_section "🧭 CONFIGURACIÓN INICIAL"
    
    # Cargar rutas personalizadas si ya existen
    if [[ -z "${BASE_DIR:-}" ]]; then
        setup_custom_paths
    fi
    
    read -p "Nombre del proyecto (ej: odoo_docker_fran): " PROJECT_NAME
    while [[ -z "${PROJECT_NAME}" ]]; do read -p "Nombre del proyecto: " PROJECT_NAME; done
    PROJECT_DIR="${BASE_DIR}/${PROJECT_NAME}"
    
    if [[ -d "${PROJECT_DIR}" ]]; then
        read -p "El directorio ${PROJECT_DIR} ya existe. ¿Eliminarlo completamente y continuar? (s/n): " conf_del
        if [[ "$conf_del" =~ ^[sS]$ ]]; then
            say "  🧹 Eliminando directorio existente ${PROJECT_DIR} completamente..." "$C_YLW"
            if [[ -f "${PROJECT_DIR}/docker-compose.yml" ]]; then
                (cd "${PROJECT_DIR}" && docker compose down -v --remove-orphans) 2>/dev/null || true
            fi
            rm -rf "${PROJECT_DIR}" 2>/dev/null || true
            ok "Directorio eliminado completamente"
        else
            err "Instalación cancelada"
        fi
    fi
    
    read -p "Nombre de la red Docker [${COMMON_DOCKER_NETWORK}]: " DOCKER_NET
    DOCKER_NET="${DOCKER_NET:-$COMMON_DOCKER_NETWORK}"
    
    # Forzar red común si el usuario intenta cambiar
    if [[ "$DOCKER_NET" != "$COMMON_DOCKER_NETWORK" ]]; then
        warn "⚠️  Se usará la red común: $COMMON_DOCKER_NETWORK"
        DOCKER_NET="$COMMON_DOCKER_NETWORK"
    fi
    
    prompt_versions
    LOCAL_IP=$(detect_ip)
    
    read -p "Usar IP local detectada ${LOCAL_IP}? (S/n): " use_ip
    if [[ "${use_ip}" =~ ^[nN]$ ]]; then
        read -p "Introduce la IP local (ej: 192.168.18.205): " LOCAL_IP
    fi
    
    print_section "🌐 MODO DE DESPLIEGUE"
    echo -e "¿Modo de despliegue?"
    echo -e "  ${C_GRN}1)${C_RESET} ${C_BLU}Local (solo accesible desde esta máquina)${C_RESET}"
    echo -e "  ${C_GRN}2)${C_RESET} ${C_BLU}Online con Nginx Proxy Manager (centralizado)${C_RESET}"
    read -p "Opción [1-2]: " DEPLOY_MODE_OPTION
    case "${DEPLOY_MODE_OPTION}" in
        1) 
            DEPLOY_MODE="local"
            say "🔵 Modo Local seleccionado" "$C_BLU"
            ;;
        2) 
            DEPLOY_MODE="online"
            say "🌐 Modo Online seleccionado - Con Nginx Proxy Manager centralizado" "$C_MAG"
            
            # Verificar si NPM está instalado
            if ! check_npm_installed; then
                warn "⚠️  Nginx Proxy Manager no está instalado"
                echo -e "¿Quieres instalarlo ahora?"
                echo -e "  ${C_GRN}1)${C_RESET} ${C_BLU}Sí, instalar Nginx Proxy Manager${C_RESET}"
                echo -e "  ${C_GRN}2)${C_RESET} ${C_BLU}No, continuar en modo local${C_RESET}"
                read -p "Opción [1-2]: " npm_install_opt
                case "$npm_install_opt" in
                    1)
                        install_npm
                        ;;
                    2)
                        DEPLOY_MODE="local"
                        say "🔵 Cambiado a modo Local" "$C_BLU"
                        ;;
                    *)
                        DEPLOY_MODE="local"
                        say "🔵 Cambiado a modo Local" "$C_BLU"
                        ;;
                esac
            fi
            
            if [[ "${DEPLOY_MODE}" == "online" ]]; then
                # Solicitar dominio
                read -p "Dominio completo (ej: fornantonioboix.myddns.me): " MAIN_DOMAIN
                while [[ -z "${MAIN_DOMAIN}" ]]; do 
                    read -p "Dominio completo (requerido): " MAIN_DOMAIN
                done
                
                # Verificar si el dominio ya está en uso en NPM
                if check_domain_in_use "$MAIN_DOMAIN"; then
                    warn "⚠️  El dominio ${MAIN_DOMAIN} ya está en uso en Nginx Proxy Manager"
                    read -p "¿Continuar de todos modos? (s/n): " continue_domain
                    if [[ ! "$continue_domain" =~ ^[sS]$ ]]; then
                        err "Instalación cancelada"
                    fi
                fi
                
                read -p "Email para certificados SSL [franmoreno1982@gmail.com]: " SSL_EMAIL
                SSL_EMAIL="${SSL_EMAIL:-franmoreno1982@gmail.com}"
            fi
            ;;
        *) 
            err "Opción no válida"
            ;;
    esac
    
    # Usar contraseñas globales con valores por defecto seguros
    ODOO_USER="desarrollo"
    ODOO_PASS="${GLOBAL_ODOO_PASS:-Desarrollo123!}"
    PG_USER="desarrollo"  
    PG_PASS="${GLOBAL_PG_PASS:-Postgres123!}"
    ADMIN_PASS="${GLOBAL_ADMIN_PASS:-AdminOdoo123!}"
    
    say "✅ Usando contraseñas globales del sistema" "$C_GRN"
    
    print_section "⚙️  CONFIGURACIÓN ADICIONAL"
    
    echo -e "¿Incluir módulos Enterprise desde carpeta local?"
    echo -e "  ${C_GRN}1)${C_RESET} ${C_BLU}Sí${C_RESET}"
    echo -e "  ${C_GRN}2)${C_RESET} ${C_BLU}No${C_RESET}"
    read -p "Opción [1-2]: " ENT_OPTION
    case "${ENT_OPTION}" in
        1) INCLUDE_ENT="yes";;
        2) INCLUDE_ENT="no";;
        *) err "Opción no válida";;
    esac
    
    say "Configuración de puertos:" "$C_CYN"
    local base_odoo_port=8069
    local base_pg_port=5432
    for i in "${!ODOO_VERSIONS[@]}"; do
        ver="${ODOO_VERSIONS[$i]}"
        local def_odoo=$((base_odoo_port + i * 10))
        local def_pg=$((base_pg_port + i))
        
        while true; do
            read -p "Puerto Odoo v${ver} [${def_odoo}]: " tmp_port
            tmp_port="${tmp_port:-$def_odoo}"
            tmp_port=$(ensure_port_free "$tmp_port" "Odoo ${ver}")
            if [[ "$tmp_port" =~ ^[0-9]+$ ]] && [ "$tmp_port" -ge 1024 ] && [ "$tmp_port" -le 65535 ]; then
                eval "ODOO_PORT_${ver}=\"$tmp_port\""
                break
            else
                warn "Puerto inválido. Debe ser un número entre 1024 y 65535."
            fi
        done
        
        while true; do
            read -p "Puerto PostgreSQL v${ver} [${def_pg}]: " tmp_pg
            tmp_pg="${tmp_pg:-$def_pg}"
            tmp_pg=$(ensure_port_free "$tmp_pg" "PostgreSQL ${ver}")
            if [[ "$tmp_pg" =~ ^[0-9]+$ ]] && [ "$tmp_pg" -ge 1024 ] && [ "$tmp_pg" -le 65535 ]; then
                eval "PG_PORT_${ver}=\"$tmp_pg\""
                break
            else
                warn "Puerto inválido. Debe ser un número entre 1024 y 65535."
            fi
        done
        say "  ✅ Odoo v${ver}: puerto ${tmp_port}, PostgreSQL: puerto ${tmp_pg}" "$C_GRN"
    done
    
    INITIALIZE_DB="yes"
    say "ℹ️  Se creará e inicializará la base de datos automáticamente." "$C_BLU"
    
    print_section "⚡ NIVEL DE RENDIMIENTO"
    
    echo -e "¿Nivel de rendimiento?"
    echo -e "  ${C_GRN}1)${C_RESET} ${C_BLU}Base (funcionalidad original)${C_RESET}"
    echo -e "  ${C_GRN}2)${C_RESET} ${C_BLU}Alto (workers, PostgreSQL tuning, personalizable) - RECOMENDADO PARA MÓDULOS PESADOS${C_RESET}"
    read -p "Opción [1-2]: " PERF_LEVEL
    case "$PERF_LEVEL" in
        1) PERF_MODE="base";;
        2) PERF_MODE="high";;
        *) err "Opción no válida";;
    esac
    
    if [[ "${PERF_MODE}" == "high" ]]; then
        say "🔧 Configuración personalizada de Alto Rendimiento (OPTIMIZADO PARA MÓDULOS PESADOS)" "$C_MAG"
        read -p "Número de workers para Odoo (Enter para calcular automático): " CUSTOM_WORKERS
        if [[ -z "${CUSTOM_WORKERS}" ]]; then
            CUSTOM_WORKERS=$(( $(nproc) * 2 + 1 ))
            say "  Calculado: $CUSTOM_WORKERS workers" "$C_BLU"
        fi
        read -p "Límite de memoria duro (bytes, Enter para 10737418240 - 10GB): " CUSTOM_LIMIT_MEM_HARD
        CUSTOM_LIMIT_MEM_HARD="${CUSTOM_LIMIT_MEM_HARD:-10737418240}"
        read -p "Límite de memoria blando (bytes, Enter para 5368709120 - 5GB): " CUSTOM_LIMIT_MEM_SOFT
        CUSTOM_LIMIT_MEM_SOFT="${CUSTOM_LIMIT_MEM_SOFT:-5368709120}"
        read -p "Límite de peticiones por worker (Enter para 8192): " CUSTOM_LIMIT_REQUEST
        CUSTOM_LIMIT_REQUEST="${CUSTOM_LIMIT_REQUEST:-8192}"
        read -p "Tiempo CPU límite (segundos, Enter para 1800 - 30 minutos): " CUSTOM_LIMIT_TIME_CPU
        CUSTOM_LIMIT_TIME_CPU="${CUSTOM_LIMIT_TIME_CPU:-1800}"
        read -p "Tiempo real límite (segundos, Enter para 28800 - 8 horas): " CUSTOM_LIMIT_TIME_REAL
        CUSTOM_LIMIT_TIME_REAL="${CUSTOM_LIMIT_TIME_REAL:-28800}"
        export CUSTOM_WORKERS CUSTOM_LIMIT_MEM_HARD CUSTOM_LIMIT_MEM_SOFT CUSTOM_LIMIT_REQUEST CUSTOM_LIMIT_TIME_CPU CUSTOM_LIMIT_TIME_REAL
    else
        CUSTOM_WORKERS=$(( $(nproc) * 2 + 1 ))
        CUSTOM_LIMIT_MEM_HARD="10737418240"
        CUSTOM_LIMIT_MEM_SOFT="5368709120"
        CUSTOM_LIMIT_REQUEST="8192"
        CUSTOM_LIMIT_TIME_CPU="1800"
        CUSTOM_LIMIT_TIME_REAL="28800"
        export CUSTOM_WORKERS CUSTOM_LIMIT_MEM_HARD CUSTOM_LIMIT_MEM_SOFT CUSTOM_LIMIT_REQUEST CUSTOM_LIMIT_TIME_CPU CUSTOM_LIMIT_TIME_REAL
    fi
    
    print_section "📋 RESUMEN DE CONFIGURACIÓN"
    
    echo "  Proyecto:     ${PROJECT_NAME}"
    echo "  Ruta:         ${PROJECT_DIR}"
    echo "  Red Docker:   ${DOCKER_NET}"
    echo "  Modo:         ${DEPLOY_MODE}"
    if [[ "${DEPLOY_MODE}" == "online" ]]; then
        echo "  Dominio:      ${MAIN_DOMAIN}"
        echo "  Email SSL:    ${SSL_EMAIL}"
        echo "  NPM Panel:    http://${NPM_PANEL_IP}:${NPM_PORT_WEB}"
        echo "  Odoo v${ODOO_VERSIONS[0]}:  https://${MAIN_DOMAIN}/"
    else
        echo "  IP local:     ${LOCAL_IP}"
        for ver in "${ODOO_VERSIONS[@]}"; do
            eval "p_odoo=\"\$ODOO_PORT_${ver}\""
            echo "  Odoo v${ver}:  http://${LOCAL_IP}:${p_odoo}"
        done
    fi
    echo "  Versiones:    ${ODOO_VERSIONS[*]}"
    echo "  Enterprise:   ${INCLUDE_ENT}"
    echo "  Inicializar DB: ${INITIALIZE_DB}"
    echo "  Rendimiento:  ${PERF_MODE}"
    if [[ "${PERF_MODE}" == "high" ]]; then
        echo "    Workers: $CUSTOM_WORKERS"
        echo "    Límites Memoria: Duro=$CUSTOM_LIMIT_MEM_HARD, Blando=$CUSTOM_LIMIT_MEM_SOFT"
        echo "    Límite Peticiones: $CUSTOM_LIMIT_REQUEST"
        echo "    Límites Tiempo: CPU=$CUSTOM_LIMIT_TIME_CPU, Real=$CUSTOM_LIMIT_TIME_REAL"
    fi
    for ver in "${ODOO_VERSIONS[@]}"; do
        eval "p_odoo=\"\$ODOO_PORT_${ver}\""
        eval "p_pg=\"\$PG_PORT_${ver}\""
        echo "  v${ver}: Odoo=${p_odoo}  Postgres=${p_pg}"
    done
    echo
    read -p "¿Continuar con la instalación? (s/n): " go
    [[ "$go" =~ ^[sS]$ ]] || { err "Cancelado por el usuario."; }
}

create_structure() {
    say "📁 Creando estructura de directorios..." "$C_CYN"
    setup_fixed_uids
    mkdir -p "${PROJECT_DIR}"
    mkdir -p "${PROJECT_DIR}/logs"
    
    for ver in "${ODOO_VERSIONS[@]}"; do
        if [[ -d "${PROJECT_DIR}/postgres_v${ver}" ]]; then
            say "  🧹 Eliminando directorio PostgreSQL v${ver}..." "$C_YLW"
            rm -rf "${PROJECT_DIR}/postgres_v${ver}"
        fi
        mkdir -p "${PROJECT_DIR}/postgres_v${ver}"
        
        if [[ "${PERF_MODE}" == "high" ]]; then
            mkdir -p "${PROJECT_DIR}/postgres_v${ver}/conf"
            local pg_conf_path="${PROJECT_DIR}/postgres_v${ver}/conf/postgresql.conf"
            # Configuración PostgreSQL válida
            cat > "$pg_conf_path" <<EOF
listen_addresses = '*'
port = 5432
max_connections = 200
shared_buffers = 2GB
effective_cache_size = 6GB
work_mem = 16MB
maintenance_work_mem = 1GB
min_wal_size = 4GB
max_wal_size = 8GB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
wal_level = replica
random_page_cost = 1.1
effective_io_concurrency = 200
max_worker_processes = 8
max_parallel_workers_per_gather = 4
max_parallel_workers = 8
max_parallel_maintenance_workers = 4
log_statement = 'none'
log_duration = off
log_lock_waits = on
log_min_duration_statement = 1000
EOF
            # Establecer permisos correctos
            chmod 644 "$pg_conf_path"
            chown "$FIXED_UID:$FIXED_GID" "$pg_conf_path"
            ok "    postgresql.conf v${ver} generado"
        fi
        
        mkdir -p "${PROJECT_DIR}/filestore_v${ver}" \
                "${PROJECT_DIR}/custom_v${ver}" \
                "${PROJECT_DIR}/odoo-config_v${ver}"
        
        # Usar ruta personalizada si está configurada, o la ruta por defecto
        local custom_src="${CUSTOM_ADDONS_PATH:-/home/odoo/custom_addons_v${ver}}"
        if [[ -d "${custom_src}" ]]; then
            say "  Copiando módulos personalizados desde ${custom_src}..." "$C_BLU"
            cp -r "${custom_src}"/* "${PROJECT_DIR}/custom_v${ver}/" 2>/dev/null || true
            ok "    Módulos personalizados v${ver} copiados"
        else
            warn "    No se encontró ${custom_src}. Se deja custom_v${ver} vacío."
        fi
        
        if [[ "${INCLUDE_ENT}" == "yes" ]]; then
            mkdir -p "${PROJECT_DIR}/enterprise_v${ver}"
            # Usar ruta personalizada si está configurada, o la ruta por defecto
            local ent_src="${ENTERPRISE_PATH:-/home/odoo/enterprise_v${ver}}"
            if [[ -d "${ent_src}" ]]; then
                cp -r "${ent_src}"/* "${PROJECT_DIR}/enterprise_v${ver}/" 2>/dev/null || true
                ok "    Enterprise v${ver} copiado"
            else
                warn "    No se encontró ${ent_src}. Se deja enterprise_v${ver} vacío."
            fi
        fi
        ok "    Estructura v${ver} creada"
    done
    ok "Estructura completa creada en ${PROJECT_DIR}"
}

write_env() {
    say "🧩 Generando .env..." "$C_CYN"
    {
        echo "# ==============================="
        echo "# .env - ${PROJECT_NAME} ($(date))"
        echo "# ==============================="
        echo "BASE_DIR=${BASE_DIR}"
        echo "PROJECT_NAME=${PROJECT_NAME}"
        echo "PROJECT_DIR=${PROJECT_DIR}"
        # Guardar rutas personalizadas
        if [[ -n "${CUSTOM_ADDONS_PATH:-}" ]]; then
            echo "CUSTOM_ADDONS_PATH=${CUSTOM_ADDONS_PATH}"
        fi
        if [[ -n "${ENTERPRISE_PATH:-}" ]]; then
            echo "ENTERPRISE_PATH=${ENTERPRISE_PATH}"
        fi
        echo "DOCKER_NET=${DOCKER_NET}"
        echo "LOCAL_IP=${LOCAL_IP}"
        echo "DEPLOY_MODE=${DEPLOY_MODE}"
        if [[ "${DEPLOY_MODE}" == "online" ]]; then
            echo "MAIN_DOMAIN=${MAIN_DOMAIN}"
            echo "SSL_EMAIL=${SSL_EMAIL}"
            echo "NPM_PANEL_IP=${NPM_PANEL_IP}"
            echo "NPM_PORT_WEB=${NPM_PORT_WEB}"
        fi
        echo "ODOO_USER=${ODOO_USER}"
        echo "ODOO_PASS=${ODOO_PASS}"
        echo "PG_USER=${PG_USER}"
        echo "PG_PASS=${PG_PASS}"
        echo "ADMIN_PASS=${ADMIN_PASS}"
        echo "INCLUDE_ENT=${INCLUDE_ENT}"
        echo "INITIALIZE_DB=${INITIALIZE_DB}"
        echo "PERF_MODE=${PERF_MODE}"
        if [[ "${PERF_MODE}" == "high" ]]; then
            echo "CUSTOM_WORKERS=${CUSTOM_WORKERS}"
            echo "CUSTOM_LIMIT_MEM_HARD=${CUSTOM_LIMIT_MEM_HARD}"
            echo "CUSTOM_LIMIT_MEM_SOFT=${CUSTOM_LIMIT_MEM_SOFT}"
            echo "CUSTOM_LIMIT_REQUEST=${CUSTOM_LIMIT_REQUEST}"
            echo "CUSTOM_LIMIT_TIME_CPU=${CUSTOM_LIMIT_TIME_CPU}"
            echo "CUSTOM_LIMIT_TIME_REAL=${CUSTOM_LIMIT_TIME_REAL}"
        fi
        echo "ODOO_UID=${FIXED_UID}"
        echo "PG_UID=${FIXED_UID}"
        echo -n "ODOO_VERSIONS="
        printf "%s " "${ODOO_VERSIONS[@]}"
        echo
        for ver in "${ODOO_VERSIONS[@]}"; do
            eval "p_odoo=\"\$ODOO_PORT_${ver}\""
            eval "p_pg=\"\$PG_PORT_${ver}\""
            echo "ODOO_PORT_${ver}=${p_odoo}"
            echo "PG_PORT_${ver}=${p_pg}"
        done
    } > "${PROJECT_DIR}/.env"
    ok ".env creado"
}

write_odoo_conf() {
    say "🧾 Generando odoo.conf..." "$C_CYN"
    
    for ver in "${ODOO_VERSIONS[@]}"; do
        local confd="${PROJECT_DIR}/odoo-config_v${ver}"
        local logpath="/var/log/odoo/odoo${ver}.log"
        eval "dbport=\"\$PG_PORT_${ver}\""
        
        if [[ "${PERF_MODE}" == "high" ]]; then
            local WORKERS="${CUSTOM_WORKERS:-$(( $(nproc) * 2 + 1 ))}"
            local MAX_RAM_PER_WORKER="${CUSTOM_LIMIT_MEM_HARD:-10737418240}"
            local MAX_RAM_PER_WORKER_SOFT="${CUSTOM_LIMIT_MEM_SOFT:-5368709120}"
            local LIMIT_REQUEST_VAL="${CUSTOM_LIMIT_REQUEST:-8192}"
            local LIMIT_TIME_CPU_VAL="${CUSTOM_LIMIT_TIME_CPU:-1800}"
            local LIMIT_TIME_REAL_VAL="${CUSTOM_LIMIT_TIME_REAL:-28800}"
            
            cat > "${confd}/odoo.conf" <<EOF
[options]
admin_passwd = ${ADMIN_PASS}
db_host = ${PROJECT_NAME}_db${ver}
db_port = ${dbport}
db_user = ${PG_USER}
db_password = ${PG_PASS}
db_name = False
; ===== IMPORTANTE: Forzar creación manual de BD =====
db_template = template1
; ====================================================
addons_path = /usr/lib/python3/dist-packages/odoo/addons,/mnt/extra-addons$( [[ "${INCLUDE_ENT}" == "yes" ]] && echo ",/mnt/enterprise" )
logfile = ${logpath}
data_dir = /var/lib/odoo
without_demo = all
; === PROXY MODE ===
proxy_mode = $( [[ "${DEPLOY_MODE}" == "online" ]] && echo "True" || echo "False" )
; === RENDIMIENTO ===
workers = ${WORKERS}
max_cron_threads = 4
limit_memory_hard = ${MAX_RAM_PER_WORKER}
limit_memory_soft = ${MAX_RAM_PER_WORKER_SOFT}
limit_request = ${LIMIT_REQUEST_VAL}
limit_time_cpu = ${LIMIT_TIME_CPU_VAL}
limit_time_real = ${LIMIT_TIME_REAL_VAL}
limit_time_real_cron = ${LIMIT_TIME_REAL_VAL}
longpolling_timeout = 3600
x_sendfile = True
; === OPTIMIZACIÓN PARA MÓDULOS PESADOS ===
unaccent = True
EOF
            ok "odoo.conf v${ver} con optimización para módulos pesados (${WORKERS} workers)"
        else
            cat > "${confd}/odoo.conf" <<EOF
[options]
admin_passwd = ${ADMIN_PASS}
db_host = ${PROJECT_NAME}_db${ver}
db_port = ${dbport}
db_user = ${PG_USER}
db_password = ${PG_PASS}
db_name = False
; ===== IMPORTANTE: Forzar creación manual de BD =====
db_template = template1
; ====================================================
addons_path = /usr/lib/python3/dist-packages/odoo/addons,/mnt/extra-addons$( [[ "${INCLUDE_ENT}" == "yes" ]] && echo ",/mnt/enterprise" )
logfile = ${logpath}
data_dir = /var/lib/odoo
without_demo = all
; === PROXY MODE ===
proxy_mode = $( [[ "${DEPLOY_MODE}" == "online" ]] && echo "True" || echo "False" )
; === CONFIGURACIÓN PARA INSTALACIÓN DE MÓDULOS PESADOS ===
limit_time_real = 28800
limit_time_cpu = 1800
workers = $(( $(nproc) * 2 + 1 ))
limit_memory_hard = 10737418240
limit_memory_soft = 5368709120
max_cron_threads = 4
longpolling_timeout = 3600
unaccent = True
EOF
            ok "odoo.conf v${ver} (modo base con optimización para módulos pesados)"
        fi
    done
}

write_compose() {
    say "📦 Generando docker-compose.yml..." "$C_CYN"
    local f="${PROJECT_DIR}/docker-compose.yml"
    cat > "$f" <<EOF
# docker-compose.yml - ${PROJECT_NAME} ($(date))
services:
EOF

    for ver in "${ODOO_VERSIONS[@]}"; do
        local odoo_port_var="ODOO_PORT_${ver}"
        local pg_port_var="PG_PORT_${ver}"
        local odoo_port="${!odoo_port_var:-8069}"
        local pg_port="${!pg_port_var:-5432}"
        local pg_version=$(get_postgres_version "$ver")
        # PostgreSQL CON pgvector preinstalado
        local pg_image="pgvector/pgvector:pg${pg_version}"
        
        cat >> "$f" <<EOF
  ${PROJECT_NAME}_db${ver}:
    # Imagen de PostgreSQL CON pgvector preinstalado
    image: ${pg_image}
    container_name: ${PROJECT_NAME}_db${ver}
    restart: unless-stopped
    environment:
      - POSTGRES_USER=${PG_USER}
      - POSTGRES_PASSWORD=${PG_PASS}
      - POSTGRES_DB=postgres
      - PGDATA=/var/lib/postgresql/data/pgdata
    user: "${FIXED_UID}:${FIXED_GID}"
    volumes:
      - ${PROJECT_DIR}/postgres_v${ver}:/var/lib/postgresql/data
EOF
        if [[ "${PERF_MODE}" == "high" ]]; then
            cat >> "$f" <<EOF
      - ${PROJECT_DIR}/postgres_v${ver}/conf/postgresql.conf:/etc/postgresql/postgresql.conf
    command: postgres -c config_file=/etc/postgresql/postgresql.conf -c listen_addresses='*'
EOF
        else
            cat >> "$f" <<EOF
    command: postgres -c listen_addresses='*'
EOF
        fi
        cat >> "$f" <<EOF
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${PG_USER} -d postgres"]
      interval: 10s
      timeout: 10s
      retries: 12
      start_period: 60s
    networks:
      - ${DOCKER_NET}
    shm_size: '256m'
EOF
        if [[ "${DEPLOY_MODE}" == "local" ]]; then
            cat >> "$f" <<EOF
    ports:
      - "${pg_port}:5432"
EOF
        fi
        cat >> "$f" <<EOF
  ${PROJECT_NAME}_odoo${ver}:
    image: odoo:${ver}
    container_name: ${PROJECT_NAME}_odoo${ver}
    user: "${FIXED_UID}:${FIXED_GID}"
    depends_on:
      ${PROJECT_NAME}_db${ver}:
        condition: service_healthy
    restart: unless-stopped
    volumes:
      - ${PROJECT_DIR}/odoo-config_v${ver}/odoo.conf:/etc/odoo/odoo.conf
      - ${PROJECT_DIR}/filestore_v${ver}:/var/lib/odoo
      - ${PROJECT_DIR}/custom_v${ver}:/mnt/extra-addons
      - ${PROJECT_DIR}/logs:/var/log/odoo
EOF
        if [[ -d "${PROJECT_DIR}/enterprise_v${ver}" && "${INCLUDE_ENT}" == "yes" ]]; then
            echo "      - ${PROJECT_DIR}/enterprise_v${ver}:/mnt/enterprise" >> "$f"
        fi
        
        # Configuración de puertos para modo local vs online
        if [[ "${DEPLOY_MODE}" == "local" ]]; then
            cat >> "$f" <<EOF
    ports:
      - "${odoo_port}:8069"
EOF
        else
            # MODO ONLINE: Exponer el puerto 8069 en la red Docker para NPM
            cat >> "$f" <<EOF
    expose:
      - "8069"
EOF
        fi
        
        cat >> "$f" <<EOF
    networks:
      - ${DOCKER_NET}
    environment:
      - HOST=${PROJECT_NAME}_db${ver}
      - USER=${PG_USER}
      - PASSWORD=${PG_PASS}
    shm_size: '256m'
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8069/web"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF
    done
    
    cat >> "$f" <<EOF
networks:
  ${DOCKER_NET}:
    external: true
EOF
    ok "docker-compose.yml creado"
}

ensure_network() {
    say "🌐 Usando red Docker común '${COMMON_DOCKER_NETWORK}'..." "$C_CYN"
    setup_common_network
    DOCKER_NET="$COMMON_DOCKER_NETWORK"  # Forzar uso de red común
    export DOCKER_NET
}

deploy_containers() {
    local LOG_FILE="${PROJECT_DIR}/logs/setup.log"
    mkdir -p "${PROJECT_DIR}/logs"
    touch "${LOG_FILE}"
    say "🚀 Desplegando contenedores..." "$C_CYN"
    
    # NO eliminar directorios PostgreSQL si ya existen datos
    say "📁 Verificando directorios PostgreSQL..." "$C_CYN"
    for ver in "${ODOO_VERSIONS[@]}"; do
        local pg_dir="${PROJECT_DIR}/postgres_v${ver}"
        if [[ -d "$pg_dir" ]]; then
            if [[ -z "$(ls -A "$pg_dir" 2>/dev/null)" ]]; then
                say "  📂 Directorio postgres_v${ver} está vacío, configurando permisos..." "$C_BLU"
            else
                say "  ⚠️  Directorio postgres_v${ver} ya contiene datos, preservando..." "$C_YLW"
            fi
        else
            mkdir -p "$pg_dir"
        fi
        
        # Aplicar permisos
        chown -R "$FIXED_UID:$FIXED_GID" "$pg_dir" 2>/dev/null || true
        chmod 700 "$pg_dir" 2>/dev/null || true
    done
    
    # Iniciar solo PostgreSQL primero
    say "🐘 Iniciando solo PostgreSQL..." "$C_CYN"
    for ver in "${ODOO_VERSIONS[@]}"; do
        local db_service="${PROJECT_NAME}_db${ver}"
        say "  Iniciando PostgreSQL v${ver}..." "$C_BLU"
        
        # Detener si ya existe
        if docker ps -a --format '{{.Names}}' | grep -q "^${PROJECT_NAME}_db${ver}$"; then
            say "    ⚠️  Contenedor existente, eliminando..." "$C_YLW"
            docker rm -f "${PROJECT_NAME}_db${ver}" 2>/dev/null || true
            sleep 2
        fi
        
        # Iniciar solo PostgreSQL
        (cd "${PROJECT_DIR}" && docker compose up -d "$db_service") 2>&1 | tee -a "$LOG_FILE"
        if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
            err "❌ Error iniciando PostgreSQL v${ver}"
        fi
    done
    
    # Esperar a PostgreSQL
    say "⏳ Esperando a que PostgreSQL esté saludable (30s)..." "$C_YLW"
    sleep 30
    
    local max_attempts=15
    local attempt=1
    local all_healthy=false
    
    while [ $attempt -le $max_attempts ] && [ "$all_healthy" = false ]; do
        all_healthy=true
        for ver in "${ODOO_VERSIONS[@]}"; do
            local db_container="${PROJECT_NAME}_db${ver}"
            local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$db_container" 2>/dev/null || echo "unknown")
            
            if [[ "$health_status" != "healthy" ]]; then
                all_healthy=false
                say "   PostgreSQL v${ver}: $health_status ($attempt/$max_attempts)" "$C_YLW"
                
                # Mostrar logs de error en intentos avanzados
                if [[ $attempt -ge 10 ]]; then
                    say "     📝 Últimos logs:" "$C_RED"
                    docker logs "$db_container" --tail 5 2>&1 | while read line; do echo "       $line"; done
                fi
            else
                say "   ✅ PostgreSQL v${ver}: $health_status" "$C_GRN"
            fi
        done
        
        if [ "$all_healthy" = false ]; then
            sleep 10
            ((attempt++))
        fi
    done
    
    if [ "$all_healthy" = false ]; then
        err "❌ PostgreSQL no se pudo inicializar correctamente después de $max_attempts intentos"
    fi
    
    ok "✅ PostgreSQL listo y saludable"
    
    # Crear usuario y base de datos POR DEFECTO
    for ver in "${ODOO_VERSIONS[@]}"; do
        local db_container="${PROJECT_NAME}_db${ver}"
        
        say "  🗄️  Configurando usuario y base de datos por defecto en PostgreSQL v${ver}..." "$C_BLU"
        
        # Esperar un poco más
        sleep 5
        
        # Crear usuario si no existe
        docker exec "$db_container" psql -U postgres -c "CREATE USER ${PG_USER} WITH PASSWORD '${PG_PASS}' CREATEDB;" 2>/dev/null || \
            say "    ℹ️  Usuario ${PG_USER} ya existe o no se pudo crear" "$C_BLU"
        
        # Crear base de datos por defecto
        docker exec "$db_container" psql -U postgres -c "CREATE DATABASE ${PROJECT_NAME} WITH OWNER ${PG_USER} ENCODING 'UTF8' LC_COLLATE='C' LC_CTYPE='C' TEMPLATE=template0;" 2>/dev/null || \
            say "    ℹ️  Base de datos ${PROJECT_NAME} ya existe" "$C_BLU"
        
        # Crear base de datos con nombre de usuario también
        docker exec "$db_container" psql -U postgres -c "CREATE DATABASE ${PG_USER} WITH OWNER ${PG_USER} ENCODING 'UTF8' LC_COLLATE='C' LC_CTYPE='C' TEMPLATE=template0;" 2>/dev/null || \
            say "    ℹ️  Base de datos ${PG_USER} ya existe" "$C_BLU"
    done
    
    # Ahora iniciar Odoo
    say "🚀 Iniciando servicios Odoo..." "$C_CYN"
    (cd "${PROJECT_DIR}" && docker compose up -d) 2>&1 | tee -a "$LOG_FILE"
    
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        warn "⚠️  Algunos servicios pueden tener errores, continuando..."
    fi
    
    # Esperar a que Odoo inicie
    say "⏳ Esperando a que Odoo se inicie (20s)..." "$C_YLW"
    sleep 20
    
    # Verificar estado
    say "🔍 Verificando estado de contenedores..." "$C_CYN"
    for ver in "${ODOO_VERSIONS[@]}"; do
        local odoo_container="${PROJECT_NAME}_odoo${ver}"
        if docker ps --format '{{.Names}}' | grep -q "^${odoo_container}$"; then
            local odoo_status=$(docker inspect --format='{{.State.Status}}' "$odoo_container" 2>/dev/null || echo "unknown")
            say "   📦 Odoo v${ver}: $odoo_status" "$C_GRN"
        else
            warn "   ⚠️  Odoo v${ver} no está en ejecución"
        fi
    done
    
    ok "✅ Despliegue completado"
}

initialize_odoo_database() {
    say "🗄️  Inicializando base de datos Odoo..." "$C_CYN"
    
    # Usar la base de datos YA CREADA en deploy_containers
    for ver in "${ODOO_VERSIONS[@]}"; do
        local odoo_container="${PROJECT_NAME}_odoo${ver}"
        local odoo_port_var="ODOO_PORT_${ver}"
        local odoo_port="${!odoo_port_var:-8069}"
        
        say "  🧪 Verificando Odoo v${ver}..." "$C_BLU"
        
        # Esperar máximo 2 minutos
        local max_wait=120
        local waited=0
        local odoo_ready=false
        
        while [ $waited -lt $max_wait ]; do
            if curl -s -f "http://localhost:${odoo_port}/web/database/selector" >/dev/null 2>&1; then
                odoo_ready=true
                break
            fi
            
            # También verificar contenedor corriendo
            if ! docker ps --format '{{.Names}}' | grep -q "^${odoo_container}$"; then
                warn "    ❌ Contenedor ${odoo_container} no está en ejecución"
                docker logs "$odoo_container" --tail 10
                break
            fi
            
            say "    ⏳ Esperando Odoo... ($((max_wait - waited))s restantes)" "$C_YLW"
            sleep 10
            ((waited+=10))
        done
        
        if [ "$odoo_ready" = false ]; then
            warn "⚠️  Odoo v${ver} no responde después de $max_wait segundos"
            continue
        fi
        
        ok "    ✅ Odoo v${ver} listo"
        
        local db_container="${PROJECT_NAME}_db${ver}"
        local db_exists=$(docker exec "$db_container" psql -U "$PG_USER" -t -c "\l" 2>/dev/null | grep -c "${PROJECT_NAME}" || echo "0")
        
        if [[ "$db_exists" -gt 0 ]]; then
            say "    🎯 Base de datos '${PROJECT_NAME}' ya existe" "$C_GRN"
            
            # Inicializar Odoo en la base de datos existente
            say "    ⚙️  Inicializando Odoo en la base de datos existente..." "$C_BLU"
            
            local init_url
            if [[ "${DEPLOY_MODE}" == "online" ]]; then
                init_url="https://${MAIN_DOMAIN}/web"
            else
                init_url="http://${LOCAL_IP}:${odoo_port}/web"
            fi
            
            # Intentar acceso automático
            say "    🌐 Intenta acceder manualmente: ${init_url}" "$C_MAG"
            say "    🔑 Usa Master Password: ${ADMIN_PASS}" "$C_RED"
            
        else
            warn "    ❌ Base de datos '${PROJECT_NAME}' no encontrada"
            say "    💡 Creando base de datos manualmente..." "$C_BLU"
            
            # Crear base de datos de emergencia
            docker exec "$db_container" psql -U postgres -c "CREATE DATABASE ${PROJECT_NAME} WITH OWNER ${PG_USER} ENCODING 'UTF8' LC_COLLATE='C' LC_CTYPE='C' TEMPLATE=template0;" || \
                warn "    No se pudo crear la base de datos"
        fi
        
        # Informar sobre pgvector
        say "    ℹ️  PostgreSQL con pgvector incluido (imagen: pgvector/pgvector)" "$C_BLU"
    done
    
    # Mostrar resumen de acceso
    print_success_box "🎉 CONFIGURACIÓN COMPLETA" "Base de datos: ${PROJECT_NAME}\nMaster Password: ${ADMIN_PASS}\nUsuario: ${ODOO_USER}\nContraseña: ${ODOO_PASS}"
    
    if [[ "${DEPLOY_MODE}" == "online" ]]; then
        say "🌐 Accede en: https://${MAIN_DOMAIN}/" "$C_GRN"
    else
        for ver in "${ODOO_VERSIONS[@]}"; do
            eval "p_odoo=\"\$ODOO_PORT_${ver}\""
            say "🔵 Odoo v${ver}: http://${LOCAL_IP}:${p_odoo}" "$C_GRN"
        done
    fi
}

# ====== FUNCIÓN CORREGIDA PARA CONFIGURAR PROXY EN NPM ======
configure_npm_proxy() {
    local project_name="$1"
    local domain="$2"
    local email="$3"
    
    say "🌐 Configurando proxy en Nginx Proxy Manager..." "$C_MAG"
    
    # Obtener versión de Odoo de manera segura - compatible con proyectos existentes
    local odoo_version=""
    
    # Opción 1: Usar variable ODOO_VERSIONS si existe y no está vacía
    if [[ -n "${ODOO_VERSIONS[@]+x}" ]] && [[ ${#ODOO_VERSIONS[@]} -gt 0 ]]; then
        odoo_version="${ODOO_VERSIONS[0]}"
    # Opción 2: Intentar obtener del .env del proyecto si existe
    elif [[ -f "${PROJECT_DIR}/.env" ]]; then
        local env_versions=$(grep "^ODOO_VERSIONS=" "${PROJECT_DIR}/.env" 2>/dev/null | cut -d'=' -f2)
        if [[ -n "$env_versions" ]]; then
            # Tomar la primera versión
            odoo_version=$(echo "$env_versions" | awk '{print $1}')
        fi
    # Opción 3: Valor por defecto para compatibilidad
    else
        odoo_version="19"
    fi
    
    # Si aún no tenemos versión, usar 19
    odoo_version="${odoo_version:-19}"
    
    say "  📦 Usando Odoo v${odoo_version} para configuración del proxy" "$C_BLU"
    
    # Verificar que NPM esté funcionando
    if ! check_npm_healthy; then
        warn "⚠️  Nginx Proxy Manager no está disponible"
        say "💡 Accede al panel manualmente: http://${NPM_PANEL_IP}:${NPM_PORT_WEB}" "$C_BLU"
        say "   Configura un nuevo Proxy Host con:" "$C_BLU"
        say "   - Domain Names: ${domain}" "$C_BLU"
        say "   - Forward Hostname/IP: ${project_name}_odoo${odoo_version}" "$C_BLU"
        say "   - Forward Port: 8069" "$C_BLU"
        say "   - SSL: Request New SSL Certificate" "$C_BLU"
        return 1
    fi
    
    # Configurar proxy host usando la versión obtenida
    if setup_npm_proxy_host "$domain" "${project_name}_odoo${odoo_version}" "8069" "$email"; then
        ok "✅ Proxy configurado exitosamente en NPM"
        say "🔗 Tu Odoo estará disponible en: https://${domain}/" "$C_GRN"
        say "⏳ El certificado SSL puede tardar unos minutos en generarse..." "$C_YLW"
        return 0
    else
        warn "⚠️  No se pudo configurar el proxy automáticamente"
        say "💡 Configura manualmente desde el panel: http://${NPM_PANEL_IP}:${NPM_PORT_WEB}" "$C_BLU"
        return 1
    fi
}

# ====== Limpieza de Proyecto (seguro - no falla si NPM no está instalado) ======
cleanup_project() {
    print_section "🧹 LIMPIEZA DE PROYECTO"
    
    local proj_name=""
    local proj_dir=""
    
    if ! select_project "Proyectos disponibles para limpieza:" proj_name proj_dir; then
        return
    fi
    
    say "¿Estás seguro de eliminar completamente el proyecto '$proj_name'?" "$C_RED"
    say "Esto detendrá y eliminará contenedores, volúmenes, imágenes (si aplica) y toda la estructura de directorios." "$C_RED"
    read -p "Escribe el nombre del proyecto para confirmar: " confirm_name
    if [[ "$confirm_name" == "$proj_name" ]]; then
        # Remover del NPM primero (no falla si NPM no está instalado)
        remove_from_npm "$proj_name"
        
        say "Deteniendo y eliminando contenedores y volúmenes del proyecto '$proj_name'..." "$C_YLW"
        (cd "$proj_dir" && docker compose down -v --remove-orphans) 2>/dev/null || true
        say "Eliminando directorio $proj_dir..." "$C_YLW"
        rm -rf "$proj_dir"
        ok "✅ Proyecto '$proj_name' eliminado completamente."
    else
        say "Nombre no coincide. Limpieza cancelada." "$C_BLU"
    fi
}

# ====== Mantenimiento de Proyecto (CORREGIDA Y SEGURA) ======
maintain_project() {
    print_section "🔧 MANTENIMIENTO DE PROYECTO"
    
    local proj_name=""
    local proj_dir=""
    
    if ! select_project "Proyectos disponibles para mantenimiento:" proj_name proj_dir; then
        return
    fi
    
    if [[ ! -f "$proj_dir/docker-compose.yml" ]]; then
        warn "No se encontró docker-compose.yml en $proj_dir"
        return
    fi
    
    while true; do
        clear
        print_section "🔧 MANTENIMIENTO - ${proj_name}"
        
        local options=(
            "Ver contenedores activos"
            "Ver logs de un contenedor"
            "Reiniciar contenedores"
            "Verificar PostgreSQL"
            "Gestión de Nginx Proxy Manager"
            "Verificar certificados SSL"
            "Volver al menú principal"
        )
        
        print_menu "OPCIONES" "${options[@]}"
        
        read -p "Opción [1-7]: " maint_opt
        case "$maint_opt" in
            1)
                print_containers_table "$proj_name"
                read -p "Presiona Enter para continuar..."
                ;;
            2)
                echo -e "Contenedores disponibles:"
                docker compose -f "$proj_dir/docker-compose.yml" ps --format "table {{.Names}}\t{{.Status}}" | grep "^${proj_name}_" || echo "Ninguno"
                read -p "Nombre exacto del contenedor (ej: ${proj_name}_odoo19): " container_name
                if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
                    say "Logs del contenedor $container_name:" "$C_MAG"
                    docker logs "$container_name" --tail 50
                else
                    warn "Contenedor '$container_name' no encontrado."
                fi
                read -p "Presiona Enter para continuar..."
                ;;
            3)
                say "Reiniciando contenedores del proyecto '$proj_name'..." "$C_YLW"
                (cd "$proj_dir" && docker compose restart) || warn "Error reiniciando contenedores."
                ok "Contenedores reiniciados."
                read -p "Presiona Enter para continuar..."
                ;;
            4)
                say "🔍 Verificando PostgreSQL..." "$C_MAG"
                if [[ -f "$proj_dir/.env" ]]; then
                    source "$proj_dir/.env"
                    say "ℹ️  PostgreSQL con pgvector incluido (imagen: pgvector/pgvector)" "$C_BLU"
                    say "✅ No se necesita configuración adicional para pgvector" "$C_GRN"
                else
                    warn "⚠️  No se encontró archivo .env"
                fi
                read -p "Presiona Enter para continuar..."
                ;;
            5)
                print_section "🌐 GESTIÓN NPM"
                echo -e "Opciones NPM:"
                echo -e "  ${C_GRN}1)${C_RESET} ${C_BLU}Ver proyectos registrados${C_RESET}"
                echo -e "  ${C_GRN}2)${C_RESET} ${C_BLU}Remover este proyecto del proxy${C_RESET}"
                echo -e "  ${C_GRN}3)${C_RESET} ${C_BLU}Acceder al panel NPM${C_RESET}"
                read -p "Opción [1-3]: " npm_opt
                case "$npm_opt" in
                    1)
                        list_npm_projects
                        ;;
                    2)
                        remove_from_npm "$proj_name"
                        ;;
                    3)
                        say "🔗 Panel NPM: http://${NPM_PANEL_IP}:${NPM_PORT_WEB}" "$C_BLU"
                        say "📧 Credenciales por defecto: admin@example.com / changeme" "$C_CYN"
                        ;;
                    *)
                        warn "Opción no válida"
                        ;;
                esac
                read -p "Presiona Enter para continuar..."
                ;;
            6)
                say "🔐 Verificando certificados SSL..." "$C_MAG"
                if [[ -f "$proj_dir/.env" ]]; then
                    source "$proj_dir/.env"
                    if [[ -n "${MAIN_DOMAIN:-}" ]]; then
                        say "Dominio: ${MAIN_DOMAIN}" "$C_BLU"
                        # Verificar certificado con openssl
                        if command -v openssl &>/dev/null; then
                            if openssl s_client -connect "${MAIN_DOMAIN}:443" -servername "${MAIN_DOMAIN}" </dev/null 2>/dev/null | openssl x509 -noout -dates; then
                                ok "✅ Certificado SSL válido"
                            else
                                warn "⚠️  No se pudo verificar el certificado"
                            fi
                        else
                            warn "⚠️  OpenSSL no instalado"
                        fi
                    else
                        warn "⚠️  Este proyecto no tiene dominio configurado"
                    fi
                else
                    warn "⚠️  No se encontró archivo .env"
                fi
                read -p "Presiona Enter para continuar..."
                ;;
            7) 
                say "Volviendo al menú principal..." "$C_BLU"
                break
                ;;
            *) 
                warn "Opción no válida"
                sleep 2
                ;;
        esac
    done
}

# ====== Ver resumen de proyecto existente (CORREGIDA Y SEGURA) ======
view_project_summary() {
    print_section "🔍 RESUMEN DE PROYECTO"
    
    local proj_name=""
    local proj_dir=""
    
    if ! select_project "Proyectos disponibles:" proj_name proj_dir; then
        return
    fi
    
    if [[ ! -f "$proj_dir/.env" ]]; then
        err "No se encontró el archivo .env en $proj_dir"
    fi
    
    (
        source "$proj_dir/.env" 2>/dev/null || {
            echo -e "${C_RED}Error al cargar el archivo .env${C_RESET}"
            exit 1
        }
        
        PROJECT_NAME="$proj_name"
        PROJECT_DIR="$proj_dir"
        DEPLOY_MODE="${DEPLOY_MODE:-local}"
        PERF_MODE="${PERF_MODE:-base}"
        ODOO_UID="${ODOO_UID:-$FIXED_UID}"
        PG_UID="${PG_UID:-$FIXED_GID}"
        LOCAL_IP="${LOCAL_IP:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
        LOCAL_IP="${LOCAL_IP:-127.0.0.1}"
        
        # Manejo seguro de ODOO_VERSIONS - compatible con proyectos existentes
        if [[ -z "${ODOO_VERSIONS:-}" ]]; then
            ODOO_VERSIONS="19"  # Valor por defecto para compatibilidad
        fi
        
        IFS=' ' read -ra ODOO_VERSIONS_ARR <<< "$ODOO_VERSIONS"
        
        print_section "📋 RESUMEN - ${PROJECT_NAME}"
        
        print_info_box "📊 INFORMACIÓN GENERAL" "Ruta: ${PROJECT_DIR}\nRendimiento: ${PERF_MODE}\nUID/GID: ${ODOO_UID}:${PG_UID}\nRed: ${DOCKER_NET}"
        
        if [[ "${DEPLOY_MODE}" == "online" ]]; then
            print_info_box "🌐 ACCESO ONLINE" "Dominio: ${MAIN_DOMAIN}\nOdoo: https://${MAIN_DOMAIN}/\nEmail SSL: ${SSL_EMAIL}\nPanel NPM: http://${NPM_PANEL_IP}:${NPM_PORT_WEB}"
        else
            print_info_box "🔵 ACCESO LOCAL" "IP: ${LOCAL_IP}"
            for ver in "${ODOO_VERSIONS_ARR[@]}"; do
                local p_odoo_var="ODOO_PORT_${ver}"
                local p_pg_var="PG_PORT_${ver}"
                local p_odoo="${!p_odoo_var:-8069}"
                local p_pg="${!p_pg_var:-5432}"
                say "Odoo v${ver}: http://${LOCAL_IP}:${p_odoo}" "$C_GRN"
                say "PostgreSQL v${ver}: localhost:${p_pg}" "$C_GRN"
            done
        fi
        
        print_containers_table "${PROJECT_NAME}"
        
        print_info_box "🔧 COMANDOS ÚTILES" "cd ${PROJECT_DIR} && docker compose ps\ncd ${PROJECT_DIR} && docker compose logs -f ${PROJECT_NAME}_odoo${ODOO_VERSIONS_ARR[0]}\ncd ${PROJECT_DIR} && docker compose down"
        
        print_info_box "🔐 CREDENCIALES" "Usuario Odoo: ${ODOO_USER:-desarrollo}\nContraseña Odoo: ${ODOO_PASS}\nUsuario PostgreSQL: ${PG_USER:-desarrollo}\nContraseña PostgreSQL: ${PG_PASS}\nBase de datos: ${PROJECT_NAME}\nMaster Password: ${ADMIN_PASS}"
    )
}

# ====== Funciones auxiliares para opciones del menú ======
execute_project_function() {
    local function_name="$1"
    local description="$2"
    
    say "$description" "$C_CYN"
    
    local proj_name=""
    local proj_dir=""
    
    if ! select_project "Proyectos disponibles:" proj_name proj_dir; then
        return
    fi
    
    local script_path="$proj_dir/$function_name"
    if [[ -f "$script_path" ]]; then
        (cd "$proj_dir" && "./$function_name")
    else
        warn "El script $function_name no existe en el proyecto $proj_name"
    fi
}

# ====== Menú de herramientas avanzadas ======
tools_menu() {
    while true; do
        print_header
        print_section "🛠️  HERRAMIENTAS AVANZADAS"
        
        local tools_options=(
            "Monitorización en tiempo real"
            "Análisis de rendimiento"
            "Verificación de producción"
            "Gestión de plugins"
            "Sistema de backups"
            "Actualizar proyecto"
            "Volver al menú principal"
        )
        
        print_menu "HERRAMIENTAS" "${tools_options[@]}"
        
        read -p "Selecciona opción [1-7]: " tool_opt
        
        case "$tool_opt" in
            1)
                execute_project_function "monitor.sh" "🔍 Monitorización en tiempo real"
                ;;
            2)
                execute_project_function "log_analyzer.sh" "📊 Análisis de rendimiento"
                ;;
            3)
                execute_project_function "production_checklist.sh" "🔍 Verificación producción"
                ;;
            4)
                execute_project_function "manage_plugins.sh" "🧩 Gestión de plugins"
                ;;
            5)
                execute_project_function "backup.sh" "🧹 Gestión de Backups"
                ;;
            6)
                execute_project_function "update.sh" "🔄 Actualizar proyecto"
                ;;
            7)
                return
                ;;
            *)
                warn "Opción no válida"
                ;;
        esac
        
        read -p "Presiona Enter para continuar..."
    done
}

# ====== Menú de gestión de NPM ======
npm_menu() {
    while true; do
        print_header
        print_section "🌐 GESTIÓN NGINX PROXY MANAGER"
        
        local npm_options=(
            "Instalar Nginx Proxy Manager"
            "Ver proyectos registrados"
            "Ver estado del servicio"
            "Acceder al panel NPM"
            "Reiniciar NPM"
            "Ver logs de NPM"
            "Volver al menú principal"
        )
        
        print_menu "GESTIÓN NPM" "${npm_options[@]}"
        
        read -p "Selecciona opción [1-7]: " npm_menu_opt
        
        case "$npm_menu_opt" in
            1)
                if check_npm_installed; then
                    warn "Nginx Proxy Manager ya está instalado"
                    say "Panel: http://${NPM_PANEL_IP}:${NPM_PORT_WEB}" "$C_BLU"
                else
                    install_npm
                fi
                ;;
            2)
                list_npm_projects
                ;;
            3)
                if check_npm_installed; then
                    if check_npm_healthy; then
                        ok "✅ Nginx Proxy Manager está funcionando correctamente"
                        say "Panel: http://${NPM_PANEL_IP}:${NPM_PORT_WEB}" "$C_BLU"
                    else
                        warn "⚠️  Nginx Proxy Manager no responde"
                    fi
                else
                    warn "⚠️  Nginx Proxy Manager no está instalado"
                fi
                ;;
            4)
                say "🔗 Panel NPM: http://${NPM_PANEL_IP}:${NPM_PORT_WEB}" "$C_BLU"
                say "📧 Credenciales por defecto: admin@example.com / changeme" "$C_CYN"
                ;;
            5)
                if check_npm_installed; then
                    say "🔄 Reiniciando Nginx Proxy Manager..." "$C_YLW"
                    docker restart "$NPM_CONTAINER"
                    ok "✅ NPM reiniciado"
                else
                    warn "⚠️  Nginx Proxy Manager no está instalado"
                fi
                ;;
            6)
                if check_npm_installed; then
                    say "📝 Logs de Nginx Proxy Manager:" "$C_MAG"
                    docker logs "$NPM_CONTAINER" --tail 50
                else
                    warn "⚠️  Nginx Proxy Manager no está instalado"
                fi
                ;;
            7)
                return
                ;;
            *)
                warn "Opción no válida"
                ;;
        esac
        read -p "Presiona Enter para continuar..."
    done
}

# ====== Flujo de instalación principal MEJORADO Y SEGURO ======
install_flow() {
    check_deps
    prompt_config
    
    # Verificar que ODOO_VERSIONS esté definida antes de continuar
    if [[ -z "${ODOO_VERSIONS[@]+x}" ]] || [[ ${#ODOO_VERSIONS[@]} -eq 0 ]]; then
        err "❌ No se definieron versiones de Odoo. La instalación no puede continuar."
    fi
    
    calculate_optimal_resources
    
    create_structure
    write_env
    write_odoo_conf
    write_compose
    fix_permissions_with_fixed_uids "$PROJECT_DIR"
    ensure_network
    
    # Configurar sistemas adicionales
    local LOG_FILE="${PROJECT_DIR}/logs/setup.log"
    mkdir -p "${PROJECT_DIR}/logs"
    touch "${LOG_FILE}"
    exec > >(tee -a "$LOG_FILE") 2>&1
    say "Registro en: ${LOG_FILE}" "$C_CYN"
    
    setup_log_management "$PROJECT_DIR"
    create_backup_system "$PROJECT_DIR" "$PROJECT_NAME"
    add_update_system "$PROJECT_DIR"
    setup_plugin_system "$PROJECT_DIR"
    add_production_checks "$PROJECT_DIR"
    
    # Despliegue normal
    if ! deploy_containers; then
        warn "Despliegue normal falló"
        return 1
    fi
    
    # Configurar proxy en NPM si es modo online
    if [[ "${DEPLOY_MODE}" == "online" ]]; then
        configure_npm_proxy "${PROJECT_NAME}" "${MAIN_DOMAIN}" "${SSL_EMAIL}"
    fi
    
    if [[ "${INITIALIZE_DB}" == "yes" ]]; then
        initialize_odoo_database
    fi
    
    return 0
}

# ====== Menú principal MEJORADO Y SEGURO ======
main_menu() {
    # Cargar configuración al inicio
    load_global_config
    init_global_passwords
    
    # Asegurar que BASE_DIR esté definida antes de mostrar el menú
    if [[ -z "${BASE_DIR:-}" ]]; then
        setup_custom_paths
    fi
    
    while true; do
        print_header
        
        # Mostrar información del sistema de manera segura
        echo -e "${C_CYN}┌──────────────────────────────────────────────────────────┐${C_RESET}"
        echo -e "${C_CYN}│ ${C_BLU}📊 INFORMACIÓN DEL SISTEMA${C_CYN}                               │${C_RESET}"
        echo -e "${C_CYN}├──────────────────────────────────────────────────────────┤${C_RESET}"
        
        # Ruta base con valor por defecto
        local display_base="${BASE_DIR:-${HOME}/odoo_projects}"
        local base_padding=$((38-${#display_base}))
        if [[ $base_padding -lt 0 ]]; then base_padding=0; fi
        echo -e "${C_CYN}│ ${C_YLW}📁 Ruta base:${C_RESET} ${display_base}${C_CYN}$(printf '%*s' "$base_padding" "")     │${C_RESET}"
        
        # Panel NPM
        local npm_url="http://${NPM_PANEL_IP}:${NPM_PORT_WEB}"
        local npm_padding=$((38-${#npm_url}))
        if [[ $npm_padding -lt 0 ]]; then npm_padding=0; fi
        echo -e "${C_CYN}│ ${C_YLW}🌐 Panel NPM:${C_RESET} ${npm_url}${C_CYN}$(printf '%*s' "$npm_padding" "")     │${C_RESET}"
        
        # Red Docker
        local network="${COMMON_DOCKER_NETWORK:-odoo-global-network}"
        local net_padding=$((38-${#network}))
        if [[ $net_padding -lt 0 ]]; then net_padding=0; fi
        echo -e "${C_CYN}│ ${C_YLW}🔗 Red Docker:${C_RESET} ${network}${C_CYN}$(printf '%*s' "$net_padding" "")      │${C_RESET}"
        
        echo -e "${C_CYN}└──────────────────────────────────────────────────────────┘${C_RESET}"
        echo ""
        
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
            1)
                if install_flow; then
                    show_credentials "$PROJECT_NAME" "${MAIN_DOMAIN:-}"
                fi
                ;;
            2)
                cleanup_project
                ;;
            3)
                maintain_project
                ;;
            4)
                view_project_summary
                ;;
            5)
                npm_menu
                ;;
            6)
                update_paths_menu
                ;;
            7)
                tools_menu
                ;;
            8)
                print_success_box "👋 HASTA PRONTO" "Gracias por usar Odoo Docker Manager Pro"
                exit 0
                ;;
            *)
                warn "Opción no válida"
                sleep 2
                ;;
        esac
        
        if [[ "$opt" != "8" ]]; then
            read -p "Presiona Enter para continuar..."
        fi
    done
}

# ====== Arranque ======
# Configurar rutas al inicio de manera segura
setup_custom_paths
main_menu