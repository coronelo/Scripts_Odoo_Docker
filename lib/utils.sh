#!/bin/bash
# Utility Functions for Odoo Docker Manager

# ====== Colores ANSI ======
C_RESET="\e[0m"; C_RED="\e[31m"; C_GRN="\e[32m"; C_YLW="\e[33m"; C_BLU="\e[34m"; C_CYN="\e[36m"; C_MAG="\e[35m"

say() { echo -e "${2:-$C_BLU}$1${C_RESET}"; }
ok()  { say "✅ $1" "$C_GRN"; }
warn(){ say "⚠️  $1" "$C_YLW"; }
err() { say "❌ $1" "$C_RED"; exit 1; }

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

calculate_optimal_resources() {
    local total_ram=$(free -b | awk '/^Mem:/{print $2}')
    local cpu_cores=$(nproc)
    
    local workers=$(( (cpu_cores * 2) + 1 ))
    
    if [[ $total_ram -lt 8589934592 ]]; then
        CUSTOM_LIMIT_MEM_HARD="2147483648"
        CUSTOM_LIMIT_MEM_SOFT="1073741824"
    elif [[ $total_ram -lt 17179869184 ]]; then
        CUSTOM_LIMIT_MEM_HARD="4294967296"
        CUSTOM_LIMIT_MEM_SOFT="2147483648"
    else
        CUSTOM_LIMIT_MEM_HARD="8589934592"
        CUSTOM_LIMIT_MEM_SOFT="4294967296"
    fi
    
    export CUSTOM_WORKERS=$workers
    export CUSTOM_LIMIT_MEM_HARD=$CUSTOM_LIMIT_MEM_HARD
    export CUSTOM_LIMIT_MEM_SOFT=$CUSTOM_LIMIT_MEM_SOFT
    
    say "🔧 Recursos calculados automáticamente:" "$C_MAG"
    say "   Workers: $workers" "$C_BLU"
    say "   Memoria por worker: $((CUSTOM_LIMIT_MEM_HARD / 1024 / 1024 / 1024))GB" "$C_BLU"
}
