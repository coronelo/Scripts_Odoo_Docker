#!/bin/bash
# Nginx Proxy Manager Integration for Odoo Docker Manager

check_npm_installed() {
    if docker ps --format '{{.Names}}' | grep -q "^${NPM_CONTAINER}$"; then
        return 0
    else
        return 1
    fi
}

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
    
    if check_npm_installed; then
        if ! docker network inspect "$COMMON_DOCKER_NETWORK" | grep -q "$NPM_CONTAINER"; then
            docker network connect "$COMMON_DOCKER_NETWORK" "$NPM_CONTAINER"
            ok "✅ NPM conectado a la red común"
        fi
    fi
}

install_npm() {
    say "🚀 Instalando Nginx Proxy Manager centralizado..." "$C_MAG"
    setup_common_network
    
    mkdir -p "${NPM_DATA_DIR}/data"
    mkdir -p "${NPM_DATA_DIR}/letsencrypt"
    mkdir -p "${NPM_DATA_DIR}/mysql"
    
    chown -R "$FIXED_UID:$FIXED_GID" "${NPM_DATA_DIR}"
    
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

    cd "${NPM_DATA_DIR}"
    docker compose up -d
    
    say "⏳ Esperando a que Nginx Proxy Manager se inicie..." "$C_BLU"
    sleep 10
    
    if check_npm_healthy; then
        ok "✅ Nginx Proxy Manager instalado correctamente"
        say "🌐 Panel de control: http://${NPM_PANEL_IP}:${NPM_PORT_WEB}" "$C_MAG"
        say "🔐 Credenciales por defecto: admin@example.com / changeme" "$C_BLU"
    else
        err "❌ No se pudo iniciar Nginx Proxy Manager"
    fi
}

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

setup_npm_proxy_host() {
    local domain="$1"
    local forward_host="$2"
    local forward_port="$3"
    local email="$4"
    
    say "🌐 Configurando proxy para ${domain}..." "$C_BLU"
    local token=$(get_npm_token "admin@example.com" "changeme")
    
    if [[ -z "$token" ]]; then
        warn "⚠️  Credenciales por defecto no funcionan. Necesito credenciales del panel NPM."
        read -p "Email del panel NPM: " npm_email
        read -sp "Password del panel NPM: " npm_password
        echo
        token=$(get_npm_token "$npm_email" "$npm_password")
        
        if [[ -z "$token" ]]; then
            warn "⚠️  No se pudo autenticar con NPM. Configura manualmente desde el panel."
            return 1
        fi
    fi
    
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
        
        say "🔐 Solicitando certificado SSL Let's Encrypt..." "$C_BLU"
        local cert_response=$(curl -s -X POST "http://${NPM_PANEL_IP}:${NPM_PORT_WEB}/api/nginx/proxy-hosts/${host_id}/certificate" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $token" \
            -d "{\"meta\":{\"letsencrypt_email\":\"${email}\",\"letsencrypt_agree\":true},\"provider\":\"letsencrypt\"}" 2>/dev/null)
        
        if echo "$cert_response" | jq -e '.success' >/dev/null 2>&1; then
            ok "✅ Certificado SSL solicitado."
        else
            warn "⚠️  No se pudo solicitar certificado automáticamente."
        fi
        return 0
    else
        warn "⚠️  No se pudo crear proxy host vía API."
        return 1
    fi
}

list_npm_projects() {
    say "📋 Proyectos registrados en Nginx Proxy Manager:" "$C_MAG"
    if ! check_npm_installed; then
        warn "Nginx Proxy Manager no está instalado"
        return 1
    fi
    
    local token=$(get_npm_token "admin@example.com" "changeme")
    if [[ -n "$token" ]]; then
        local response=$(curl -s "http://${NPM_PANEL_IP}:${NPM_PORT_WEB}/api/nginx/proxy-hosts" \
            -H "Authorization: Bearer $token" 2>/dev/null)
        if echo "$response" | jq -e '.[]' >/dev/null 2>&1; then
            echo "$response" | jq -r '.[] | "  🌐 \(.domain_names[0]) → \(.forward_host):\(.forward_port) [SSL: \(.ssl_forced)]"'
        else
            say "  ℹ️  No hay proxies configurados" "$C_BLU"
        fi
    fi
}

remove_from_npm() {
    local project_name="$1"
    if ! check_npm_installed; then return 0; fi
    
    local token=$(get_npm_token "admin@example.com" "changeme")
    if [[ -z "$token" ]]; then return 0; fi
    
    local response=$(curl -s "http://${NPM_PANEL_IP}:${NPM_PORT_WEB}/api/nginx/proxy-hosts" \
        -H "Authorization: Bearer $token" 2>/dev/null)
    local host_id=$(echo "$response" | jq -r '.[] | select(.forward_host | contains("'${project_name}'")) | .id' 2>/dev/null | head -1)
    
    if [[ -n "$host_id" ]]; then
        curl -s -X DELETE "http://${NPM_PANEL_IP}:${NPM_PORT_WEB}/api/nginx/proxy-hosts/${host_id}" \
            -H "Authorization: Bearer $token" >/dev/null 2>&1
        ok "✅ Proyecto removido del proxy NPM"
    fi
}

check_domain_in_use() {
    local domain="$1"
    if ! check_npm_installed; then return 1; fi
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

configure_npm_proxy() {
    local project_name="$1"
    local domain="$2"
    local email="$3"
    
    say "🌐 Configurando proxy en Nginx Proxy Manager..." "$C_MAG"
    if ! check_npm_healthy; then
        warn "⚠️  Nginx Proxy Manager no está disponible"
        return 1
    fi
    
    if setup_npm_proxy_host "$domain" "${project_name}_odoo${ODOO_VERSIONS[0]}" "8069" "$email"; then
        ok "✅ Proxy configurado exitosamente en NPM"
        return 0
    else
        warn "⚠️  No se pudo configurar el proxy automáticamente"
        return 1
    fi
}
