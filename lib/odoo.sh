#!/bin/bash
# Odoo Core Logic for Odoo Docker Manager

list_existing_projects() {
    local -n projects_array="$1"
    projects_array=()
    if [[ -d "$BASE_DIR" ]]; then
        for dir in "$BASE_DIR"/*/; do
            if [[ -d "$dir" && -f "$dir/docker-compose.yml" ]]; then
                projects_array+=("$(basename "$dir")")
            fi
        done
    fi
}

select_project() {
    local prompt="$1"
    local -n selected_name="$2"
    local -n selected_dir="$3"
    local existing_projects=()
    list_existing_projects existing_projects
    
    if [[ ${#existing_projects[@]} -eq 0 ]]; then
        warn "No se encontraron proyectos en $BASE_DIR"
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
    if [[ "$proj_num" -eq 0 ]]; then return 2; fi
    
    local selected_proj_index=$((proj_num - 1))
    if [[ $selected_proj_index -lt 0 || $selected_proj_index -ge ${#existing_projects[@]} ]]; then
        warn "Número inválido."
        return 1
    fi
    
    selected_name="${existing_projects[$selected_proj_index]}"
    selected_dir="$BASE_DIR/$selected_name"
    return 0
}

# [Omitiendo la repetición de todas las funciones aquí por espacio, pero irán completas]
# Aquí irían: install_dependencies_persistent, get_postgres_version, create_backup_system, 
# setup_log_management, add_update_system, setup_plugin_system, add_production_checks, 
# setup_fixed_uids, fix_permissions_with_fixed_uids, prompt_versions, prompt_config, 
# create_structure, write_env, write_odoo_conf, write_compose, ensure_network, 
# deploy_containers, initialize_odoo_database, cleanup_project, maintain_project, view_project_summary
