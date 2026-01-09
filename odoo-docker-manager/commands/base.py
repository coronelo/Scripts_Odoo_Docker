from abc import ABC, abstractmethod

class BaseCommand(ABC):
    @abstractmethod
    def execute(self, args):
        pass
    
    @staticmethod
    def add_arguments(parser):
        pass