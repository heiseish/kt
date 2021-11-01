
import json
import os
from kttool.logger import log
from pathlib import Path
import subprocess
from kttool.base import Action
from kttool.logger import color_cyan, color_green, color_red, log_green
from kttool.utils import MAP_TEMPLATE_TO_PLANG, ask_with_default

class Config(Action):
    def add_template(self) -> None:
        question = 'Which template would you like to add:\n'
        selectable_lang = {}
        idx = 1
        existed_templates = {}
        options = {}

        log_green('Adapted from xalanq\'s cf tool')
        log('''
Template will run 3 scripts in sequence when you run "kt test":
    - before_script   (execute once)
    - script          (execute the number of samples times)
    - after_script    (execute once)
You could set "before_script" or "after_script" to empty string, meaning not executing.
You have to run your program in "script" with standard input/output (no need to redirect).

You can insert some placeholders in your scripts. When execute a script,
cf will replace all placeholders by following rules:

$%path%$   Path to source file (Excluding $%full%$, e.g. "/home/user/")
$%full%$   Full name of source file (e.g. "a.cpp")
$%file%$   Name of source file (Excluding suffix, e.g. "a")
$%rand%$   Random string with 8 character (including "a-z" "0-9")
        ''')
        

        existed_templates = self.load_kt_config()

        for template_type, lang in MAP_TEMPLATE_TO_PLANG.items():
            if template_type not in existed_templates:
                temp = f'{idx} ({lang.extension}): {lang.full_name}\n'
                question += temp
                selectable_lang[idx] = (template_type, lang)
                idx += 1

        res = input(question)
        ret = int(res)
        assert 1 <= ret < idx, 'Invalid input'
        
        selected_lang = selectable_lang[ret][1]

        import readline, glob
        def complete(text, state):
            return (glob.glob(os.path.expanduser(text)+'*')+[None])[state]

        readline.set_completer_delims(' \t\n;')
        readline.parse_and_bind("tab: complete")
        readline.set_completer(complete)
        options['path'] = os.path.expanduser(input('Path to template file: '))
        options['pre_script'] = ask_with_default('Pre-script', selected_lang.pre_script)
        options['script'] = ask_with_default('Script', selected_lang.script)
        options['post_script'] = ask_with_default('Post-script', selected_lang.post_script)
        options['default'] = False if existed_templates else True

        existed_templates[selected_lang.alias] = options
        with open(self.kt_config, 'w') as kt_config:
            json.dump(existed_templates, kt_config, indent=2)
        log_green(f'Yosh, your configuration has been saved to {self.kt_config}')


    def remove_template(self) -> None:
        ''' Remove a template from ktconfig file'''
        existed_templates = self.load_kt_config()

        log(f'Which template would you like to {color_red("delete")} ? For eg cpp, cc, ...')
        for k in existed_templates.keys():
            log(k)
        res = input()

        assert res in existed_templates, f'Invalid template chosen. Template {res} is not in ur config file'

        move_default = existed_templates[res]['default']
        existed_templates.pop(res, None)
        if existed_templates and move_default: # move default to the first key of template
            existed_templates[next(iter(existed_templates))] = True
        with open(self.kt_config, 'w') as kt_config:
            json.dump(existed_templates, kt_config, indent=2)

    def update_default(self) -> None:
        default_key = ''
        existed_templates = self.load_kt_config()
        
        log(f'Which template would you like to gen as {color_cyan("default")} ? For eg cpp, cc, ...')
        
        for k, v in existed_templates.items():
            log(f'{k} {color_green("(default)") if v["default"] else ""}')
            if v["default"]:
                default_key = k
        res  = input()

        assert res in existed_templates, f'Invalid template chosen. Template {res} is not in ur config file'
        existed_templates[default_key]["default"] = False
        existed_templates[res]["default"] = True
        with open(self.kt_config, 'w') as kt_config:
            json.dump(existed_templates, kt_config, indent=2)
        log_green('Yosh, your configuration has been saved')

    def _act(self) -> None:
        question = color_cyan('Select an option:\n')
        question += """1: Add a template
2: Remove a template
3: Select a default template
"""
        res = input(question)
        opt = int(res)
        if opt == 1:
            self.add_template()
        elif opt == 2:
            self.remove_template()
        elif opt == 3:
            self.update_default()
        else:
            raise ValueError('Invalid option')