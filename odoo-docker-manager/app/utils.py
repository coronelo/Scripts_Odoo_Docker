import secrets
import string
from colorama import Fore, Style, init

init(autoreset=True)

class PasswordGenerator:
    @staticmethod
    def generate_secure_password(length=16):
        alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
        return ''.join(secrets.choice(alphabet) for _ in range(length))

class Console:
    @staticmethod
    def success(message):
        print(f"{Fore.GREEN}✅ {message}")
    
    @staticmethod
    def error(message):
        print(f"{Fore.RED}❌ {message}")
    
    @staticmethod
    def warning(message):
        print(f"{Fore.YELLOW}⚠️  {message}")
    
    @staticmethod
    def info(message):
        print(f"{Fore.CYAN}ℹ️  {message}")
    
    @staticmethod
    def header(message):
        print(f"\n{Fore.MAGENTA}{'='*50}")
        print(f"{Fore.MAGENTA}{message}")
        print(f"{Fore.MAGENTA}{'='*50}")
    
    @staticmethod
    def input(prompt, default=None):
        if default:
            return input(f"{Fore.CYAN}{prompt} [{Fore.YELLOW}{default}{Fore.CYAN}]: ") or default
        else:
            return input(f"{Fore.CYAN}{prompt}: ")
    
    @staticmethod
    def confirm(message):
        return input(f"{Fore.CYAN}{message} (s/n): ").lower() == 's'
    
    @staticmethod
    def print_config(label, value):
        print(f"{Fore.WHITE}{label}: {Fore.GREEN}{value}")
    
    @staticmethod
    def print_secret(label, value):
        print(f"{Fore.WHITE}{label}: {Fore.YELLOW}{value}")
