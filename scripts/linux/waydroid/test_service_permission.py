#!/usr/bin/python3
"""Execute the actual polkit rule against allowed and forbidden action details."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import unittest

spec = importlib.util.spec_from_file_location('service_permission', Path(__file__).with_name('install-service-permission.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PermissionTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('node'), 'Node needed to execute polkit JavaScript')
    def test_rule_grants_only_local_active_user_start_and_stop_of_exact_unit(self):
        base = dict(action='org.freedesktop.systemd1.manage-units',
                    unit='waydroid-container.service', verb='start',
                    user='muness', local=True, active=True)
        cases = [base, dict(base, verb='stop')]
        for key, value in [('action', 'org.freedesktop.policykit.exec'),
                           ('action', 'org.freedesktop.systemd1.manage-unit-files'),
                           ('unit', 'sshd.service'), ('verb', 'restart'),
                           ('verb', 'enable'), ('user', 'other'),
                           ('local', False), ('active', False)]:
            cases.append(dict(base, **{key: value}))
        program = '''
const fs = require('fs'), vm = require('vm');
const data = JSON.parse(fs.readFileSync(0, 'utf8'));
let check;
vm.runInNewContext(data.rule, {polkit: {Result: {YES: 'yes'}, addRule: f => check=f}});
console.log(JSON.stringify(data.cases.map(c => check({id:c.action, lookup:k=>c[k]}, c) || null)));
'''
        result = subprocess.run(['node', '-e', program],
                                input=json.dumps(dict(rule=module.rule('muness'), cases=cases)),
                                capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(result.stdout), ['yes', 'yes'] + [None] * 8)

    def test_username_cannot_inject_javascript(self):
        for user in ('root;evil()', '" || true', '../other', ''):
            with self.assertRaises(ValueError):
                module.rule(user)


if __name__ == '__main__':
    unittest.main()
