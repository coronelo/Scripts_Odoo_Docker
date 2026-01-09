import argparse

class CLI:
    def __init__(self):
        self.parser = argparse.ArgumentParser(description="Odoo Docker Manager")
        self.subparsers = self.parser.add_subparsers(dest="command", required=True)
    
    def add_command(self, name, command_class):
        subparser = self.subparsers.add_parser(name)
        command_class.add_arguments(subparser)
        subparser.set_defaults(command_class=command_class)
    
    def run(self):
        args = self.parser.parse_args()
        command = args.command_class()
        command.execute(args)