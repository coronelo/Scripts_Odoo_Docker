#!/bin/bash
# Configuration Management for Odoo Docker Manager

load_global_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        ok "✅ Configuración global cargada desde $CONFIG_FILE"
    else
        warn "⚠️  No hay configuración global guardada. Se usarán valores por defecto."
        BASE_DIR="${HOME}/odoo_projects"
        CUSTOM_ADDONS_PATH=""
        ENTERPRISE_PATH=""
        GLOBAL_PASSWORDS_FILE="${BASE_DIR}/.global_passwords.env"
    fi
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

init_global_passwords() {
    local passwords_file="${GLOBAL_PASSWORDS_FILE:-${BASE_DIR}/.global_passwords.env}"
    
    if [[ ! -f "$passwords_file" ]]; then
        say "🔐 Generando contraseñas globales..." "$C_CYN"
        local admin_pass=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9!@#$%^&*' | head -c 24)
        local odoo_pass=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 16)
        local pg_pass=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 16)
        
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
    
    source "$passwords_file" 2>/dev/null || warn "⚠️  Error cargando contraseñas"
    export GLOBAL_ADMIN_PASS GLOBAL_ODOO_PASS GLOBAL_PG_PASS
    GLOBAL_PASSWORDS_FILE="$passwords_file"
}

setup_custom_paths() {
  load_global_config
  
  if [[ -n "${BASE_DIR:-}" && -d "${BASE_DIR}" ]]; then
    return 0
  fi
  
  print_section "🗂️  CONFIGURACIÓN DE RUTAS"
  local default_base="${HOME}/odoo_projects"
  read -p "Ruta base para proyectos [${default_base}]: " custom_base_dir
  BASE_DIR="${custom_base_dir:-$default_base}"
  BASE_DIR="${BASE_DIR/#\~/$HOME}"
  
  mkdir -p "$BASE_DIR" || err "❌ No se pudo crear $BASE_DIR"
  init_global_passwords
  save_global_config
  
  export BASE_DIR
  ok "✅ Ruta base configurada: $BASE_DIR"
}

update_paths_menu() {
    print_section "🔄 ACTUALIZAR RUTAS CONFIGURADAS"
    
    echo -e "${C_CYN}Rutas actuales:${C_RESET}"
    echo -e "  ${C_BLU}Base:${C_RESET} ${BASE_DIR}"
    echo -e "  ${C_BLU}Addons:${C_RESET} ${CUSTOM_ADDONS_PATH:-No configurado}"
    echo -e "  ${C_BLU}Enterprise:${C_RESET} ${ENTERPRISE_PATH:-No configurado}"
    echo ""
    
    local options=("Cambiar ruta base" "Cambir ruta de addons" "Cambiar ruta enterprise" "Volver")
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
