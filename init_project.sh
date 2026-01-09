#!/bin/bash

# Crear estructura de carpetas
mkdir -p odoo-docker-manager/{app,commands,config}

# Crear archivos principales
touch odoo-docker-manager/main.py
touch odoo-docker-manager/requirements.txt

# Crear __init__.py en subcarpetas
touch odoo-docker-manager/app/__init__.py
touch odoo-docker-manager/commands/__init__.py
touch odoo-docker-manager/config/__init__.py

echo "Estructura creada en odoo-docker-manager/"