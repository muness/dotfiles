import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location('install_host', Path(__file__).with_name('install-host.py'))
install_host = importlib.util.module_from_spec(spec)
spec.loader.exec_module(install_host)


class InstallTargetsTest(unittest.TestCase):
    @patch.object(install_host.subprocess, 'run')
    def test_installed_provider_is_not_replaced(self, run):
        run.return_value = subprocess.CompletedProcess([], 0)
        self.assertEqual(install_host.install_targets(['git', 'fprintd', 'grim']), ['git', 'grim'])
        run.assert_called_once_with(['/usr/bin/pacman', '-T', 'fprintd'],
                                    stdout=subprocess.DEVNULL, check=False)

    @patch.object(install_host.subprocess, 'run')
    def test_missing_provider_is_installed(self, run):
        run.return_value = subprocess.CompletedProcess([], 127)
        self.assertEqual(install_host.install_targets(['git', 'fprintd']), ['git', 'fprintd'])

    @patch.object(install_host.subprocess, 'run')
    def test_unrelated_dependencies_are_preserved(self, run):
        self.assertEqual(install_host.install_targets(['git', 'grim']), ['git', 'grim'])
        run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
