#!/bin/bash
# UI Functions for Odoo Docker Manager
# Separated from main script for better maintainability

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
    done <<< "$(echo -e "$content" | fold -w 54)"
    
    echo -e "${C_CYN}╚══════════════════════════════════════════════════════════╝${C_RESET}"
}

print_success_box() {
    local title="$1"
    local content="$2"
    local line_len=56
    local title_len=${#title}
    local padding=$((line_len - title_len - 2))
    
    echo -e "${C_GRN}╔══════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_GRN}║ ✅ ${C_YLW}${title}${C_GRN} $(printf '%*s' $padding)║${C_RESET}"
    echo -e "${C_GRN}╠══════════════════════════════════════════════════════════╣${C_RESET}"
    
    while IFS= read -r line; do
        local line_len=${#line}
        local padding=$((53 - line_len))
        echo -e "${C_GRN}║   ${C_BLU}${line}${C_GRN} $(printf '%*s' $padding)║${C_RESET}"
    done <<< "$(echo -e "$content" | fold -w 52)"
    
    echo -e "${C_GRN}╚══════════════════════════════════════════════════════════╝${C_RESET}"
}

print_system_info() {
    echo -e "${C_CYN}┌──────────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_CYN}│ ${C_BLU}📊 INFORMACIÓN DEL SISTEMA${C_CYN}                              │${C_RESET}"
    echo -e "${C_CYN}├──────────────────────────────────────────────────────────┤${C_RESET}"
    
    local base_info="📁 Ruta base: ${BASE_DIR}"
    local base_len=${#base_info}
    local base_padding=$((56 - base_len - 2))
    echo -e "${C_CYN}│ ${C_YLW}📁 Ruta base:${C_RESET} ${BASE_DIR}${C_CYN} $(printf '%*s' $base_padding)│${C_RESET}"
    
    local npm_info="🌐 Panel NPM: http://${NPM_PANEL_IP}:${NPM_PORT_WEB}"
    local npm_len=${#npm_info}
    local npm_padding=$((56 - npm_len - 2))
    echo -e "${C_CYN}│ ${C_YLW}🌐 Panel NPM:${C_RESET} http://${NPM_PANEL_IP}:${NPM_PORT_WEB}${C_CYN} $(printf '%*s' $npm_padding)│${C_RESET}"
    
    local net_info="🔗 Red Docker: ${COMMON_DOCKER_NETWORK}"
    local net_len=${#net_info}
    local net_padding=$((56 - net_len - 2))
    echo -e "${C_CYN}│ ${C_YLW}🔗 Red Docker:${C_RESET} ${COMMON_DOCKER_NETWORK}${C_CYN} $(printf '%*s' $net_padding)│${C_RESET}"
    
    echo -e "${C_CYN}└──────────────────────────────────────────────────────────┘${C_RESET}"
}

show_credentials() {
    local proj="$1"
    local domain="${2:-}"
    
    print_section "🔐 CREDENCIALES DE ACCESO"
    
    local content="Proyecto: ${proj}\n"
    content+="Usuario: ${ODOO_USER:-desarrollo}\n"
    content+="Contraseña: ${ODOO_PASS}\n"
    content+="Master Pass: ${ADMIN_PASS}\n"
    
    if [[ -n "$domain" ]]; then
        content+="\n🌐 URL: https://${domain}/"
    else
        content+="\n🔵 URL: http://$(detect_ip):8069"
    fi
    
    print_success_box "ACCESO CREADO" "$content"
}
