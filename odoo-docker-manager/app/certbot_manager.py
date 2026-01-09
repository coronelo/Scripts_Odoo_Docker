import subprocess

def solicitar_certificado(dominio):
    print(f"Solicitando certificado SSL para {dominio}...")
    result = subprocess.run([
        "docker", "run", "--rm",
        "-v", "/etc/letsencrypt:/etc/letsencrypt",
        "-v", "/var/lib/letsencrypt:/var/lib/letsencrypt",
        "-v", "/var/www/html:/var/www/html",
        "--network", "odoo-network",
        "certbot/certbot:latest", "certonly",
        "--webroot", "-w", "/var/www/html",
        "-d", dominio,
        "--agree-tos",
        "--register-unsafely-without-email",
        "--non-interactive",
        "-v"  # Muestra más detalles en la consola
    ], capture_output=True)
    print(result.stdout.decode())
    if result.returncode == 0:
        print("✅ Certificado SSL solicitado.")
    else:
        print(f"❌ Error solicitando certificado: {result.stderr.decode()}")