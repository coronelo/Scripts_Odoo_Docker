#!/bin/bash

# docker-nuke.sh - Elimina TODO de Docker en el host
# Uso: ./docker-nuke.sh [--dry-run] [--help]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

DRY_RUN=false
CONFIRM=true

show_help() {
    echo "Uso: $0 [OPCIONES]"
    echo ""
    echo "Elimina todos los contenedores, imágenes, volúmenes y redes de Docker"
    echo ""
    echo "Opciones:"
    echo "  -y, --yes           No pedir confirmación"
    echo "  -d, --dry-run       Mostrar qué se eliminaría sin hacer cambios"
    echo "  -h, --help          Mostrar esta ayuda"
    echo ""
    echo "Ejemplos:"
    echo "  $0                 # Elimina con confirmación"
    echo "  $0 -y              # Elimina sin confirmación"
    echo "  $0 --dry-run       # Solo muestra qué se eliminaría"
    echo ""
}

print_section() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Error: Docker no está instalado o no está en el PATH${NC}"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        echo -e "${RED}Error: Docker daemon no está en ejecución o no tienes permisos${NC}"
        echo "Ejecuta con sudo o agrega tu usuario al grupo docker:"
        echo "  sudo usermod -aG docker \$USER"
        exit 1
    fi
}

print_summary() {
    print_section "RESUMEN DE LO QUE SE ELIMINARÁ"
    
    local containers=$(docker ps -aq 2>/dev/null | wc -l | tr -d ' ')
    local images=$(docker images -q 2>/dev/null | wc -l | tr -d ' ')
    local volumes=$(docker volume ls -q 2>/dev/null | wc -l | tr -d ' ')
    local networks=$(docker network ls -q 2>/dev/null | wc -l | tr -d ' ')
    
    echo -e "${YELLOW}Contenedores:${NC} $containers"
    echo -e "${YELLOW}Imágenes:${NC} $images"
    echo -e "${YELLOW}Volúmenes:${NC} $volumes"
    echo -e "${YELLOW}Redes:${NC} $networks"
    echo ""
}

confirm_action() {
    if [ "$CONFIRM" = true ] && [ "$DRY_RUN" = false ]; then
        echo -e "${RED}¡ADVERTENCIA! Esto eliminará TODO de Docker.${NC}"
        echo -e "${YELLOW}Se perderán todos los datos.${NC}"
        echo ""
        read -p "¿Estás seguro? (escribe 'SI' en mayúsculas para continuar): " respuesta
        
        if [ "$respuesta" != "SI" ]; then
            echo -e "${GREEN}Operación cancelada.${NC}"
            exit 0
        fi
        echo ""
    fi
}

docker_nuke() {
    print_section "INICIANDO LIMPIEZA DE DOCKER"
    
    # 1. Detener contenedores
    echo -e "${YELLOW}1. Deteniendo contenedores...${NC}"
    local running_containers=$(docker ps -q 2>/dev/null)
    if [ ! -z "$running_containers" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo "   (dry-run) Se detendrían: $(echo $running_containers | wc -w) contenedores"
        else
            docker stop $running_containers 2>/dev/null || true
            echo -e "   ${GREEN}✓${NC} Contenedores detenidos"
        fi
    else
        echo "   No hay contenedores en ejecución"
    fi
    
    # 2. Eliminar contenedores
    echo -e "${YELLOW}2. Eliminando contenedores...${NC}"
    local all_containers=$(docker ps -aq 2>/dev/null)
    if [ ! -z "$all_containers" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo "   (dry-run) Se eliminarían: $(echo $all_containers | wc -w) contenedores"
        else
            docker rm -f $all_containers 2>/dev/null || true
            echo -e "   ${GREEN}✓${NC} Contenedores eliminados"
        fi
    else
        echo "   No hay contenedores"
    fi
    
    # 3. Eliminar imágenes
    echo -e "${YELLOW}3. Eliminando imágenes...${NC}"
    local all_images=$(docker images -aq 2>/dev/null)
    if [ ! -z "$all_images" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo "   (dry-run) Se eliminarían: $(echo $all_images | wc -w) imágenes"
        else
            docker rmi -f $all_images 2>/dev/null || true
            echo -e "   ${GREEN}✓${NC} Imágenes eliminadas"
        fi
    else
        echo "   No hay imágenes"
    fi
    
    # 4. Eliminar volúmenes
    echo -e "${YELLOW}4. Eliminando volúmenes...${NC}"
    local all_volumes=$(docker volume ls -q 2>/dev/null)
    if [ ! -z "$all_volumes" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo "   (dry-run) Se eliminarían: $(echo $all_volumes | wc -w) volúmenes"
        else
            docker volume rm $all_volumes 2>/dev/null || true
            echo -e "   ${GREEN}✓${NC} Volúmenes eliminados"
        fi
    else
        echo "   No hay volúmenes"
    fi
    
    # 5. ELIMINAR REDES (MODIFICADO)
    echo -e "${YELLOW}5. Eliminando redes...${NC}"
    local all_networks=$(docker network ls -q 2>/dev/null | grep -v "^bridge$" | grep -v "^host$" | grep -v "^none$")
    if [ ! -z "$all_networks" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo "   (dry-run) Se eliminarían: $(echo $all_networks | wc -w) redes personalizadas"
            echo "   Redes a eliminar:"
            docker network ls --filter type=custom --format "table {{.ID}}\t{{.Name}}\t{{.Driver}}" 2>/dev/null || true
        else
            for network_id in $all_networks; do
                docker network rm $network_id 2>/dev/null || true
            done
            echo -e "   ${GREEN}✓${NC} Redes eliminadas"
        fi
    else
        echo "   No hay redes personalizadas"
    fi
    
    # 6. Limpieza final del sistema
    echo -e "${YELLOW}6. Limpieza final del sistema...${NC}"
    if [ "$DRY_RUN" = true ]; then
        echo "   (dry-run) Se ejecutaría: docker system prune -af"
    else
        docker system prune -af 2>/dev/null || true
        echo -e "   ${GREEN}✓${NC} Sistema limpiado"
    fi
    
    print_section "LIMPIEZA COMPLETADA"
    
    if [ "$DRY_RUN" = false ]; then
        echo -e "${GREEN}¡Todo limpiado!${NC}"
        echo ""
        echo "Estado actual:"
        docker ps -a
        echo ""
        docker images
        echo ""
        docker volume ls
    fi
}

# Parsear argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            CONFIRM=false
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            CONFIRM=false
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Argumento desconocido: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# Ejecutar
check_docker
print_summary

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}MODO DRY-RUN: No se harán cambios reales${NC}"
    echo ""
fi

confirm_action
docker_nuke

exit 0