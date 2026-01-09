import requests

def validar_https(dominio):
    url = f"https://{dominio}"
    try:
        r = requests.get(url, timeout=10)
        if r.status_code == 200:
            print(f"✅ El proyecto Odoo está accesible por HTTPS en {url}")
        else:
            print(f"⚠️ El proyecto responde pero no con código 200: {r.status_code}")
    except Exception as e:
        print(f"❌ No se pudo acceder a {url}: {e}")