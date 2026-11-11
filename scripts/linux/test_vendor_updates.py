"""Exercise app coverage, unattended mode, cancellation, and native metadata."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('extra', HERE / 'vendor-extra-metadata.py')
extra = importlib.util.module_from_spec(spec)
spec.loader.exec_module(extra)


class RoutingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / 'home'
        self.home.mkdir()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.log = self.root / 'calls'
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(self.bin) + ':' + os.environ['PATH'],
                        CALL_LOG=str(self.log), FAKE_EXIT='0')
        # Isolate the OS as well as the package database; tests run on any Linux.
        script = (HERE / 'vendor-apps.sh').read_text().replace('. /etc/os-release', 'ID=arch; ID_LIKE=')
        (self.root / 'vendor-apps.sh').write_text(script)
        for name in ['vendor-packaged-apps', 'vendor-rpm-apps', 'tether', 'zed', '1password', 'bazecor', 'foyer', 'wine-arm64ec', 'omarchy']:
            (self.root / (name + '.sh')).write_text(
                '#!/bin/bash\nprintf "%s %s\\n" "${0##*/}" "$*" >>"$CALL_LOG"\n'
                'if [[ ${0##*/} == vendor-packaged-apps.sh ]]; then exit "$FAKE_EXIT"; fi\n')
        for name, content in [('uname', 'echo aarch64'), ('pacman', 'exit 0')]:
            path = self.bin / name
            path.write_text('#!/bin/bash\n' + content + '\n')
            path.chmod(0o755)

    def invoke(self, *args):
        result = subprocess.run(['bash', str(self.root / 'vendor-apps.sh'), *args], env=self.env,
                                text=True, capture_output=True)
        return result, self.log.read_text() if self.log.exists() else ''

    def test_default_includes_existing_specialized_apps_and_tether(self):
        result, calls = self.invoke('--check')
        self.assertEqual(result.returncode, 0, result.stderr)
        for app in ['tether.sh --check', '1password.sh --check', 'zed.sh --check', 'bazecor.sh --check',
                    'hqplayer5desktop', 'hqplayer-embedded', 'hyprmoncfg', 'browseros', 'wine-arm64ec.sh --check']:
            self.assertIn(app, calls)
        self.assertTrue(all('--check' in line for line in calls.splitlines()))

    def test_user_only_has_no_system_installs_and_skips_missing_apps(self):
        result, calls = self.invoke('--user-only')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(calls, '')
        desktop = self.home / '.local/share/applications/tether.desktop'
        desktop.parent.mkdir(parents=True)
        desktop.touch()
        zed = self.home / '.local/zed.app/bin/zed'
        zed.parent.mkdir(parents=True)
        zed.touch()
        zed.chmod(0o755)
        result, calls = self.invoke('--user-only')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(calls.splitlines(), ['tether.sh ', 'zed.sh '])

    def test_download_mode_propagates_to_all_requested_backends(self):
        result, calls = self.invoke('--download-only', 'tether', 'hqplayer-embedded', 'bazecor')
        self.assertEqual(result.returncode, 0)
        self.assertTrue(all('--download-only' in line for line in calls.splitlines()))
        self.assertNotIn('zed.sh', calls)

    def test_failure_reported_and_independent_user_apps_still_checked(self):
        self.env['FAKE_EXIT'] = '1'
        result, calls = self.invoke('--check', 'chrome', 'tether')
        self.assertEqual(result.returncode, 1)
        self.assertIn('tether.sh --check', calls)

    def test_polkit_cancellation_does_not_prompt_for_more_apps(self):
        self.env['FAKE_EXIT'] = '126'
        result, calls = self.invoke('chrome', '1password')
        self.assertEqual(result.returncode, 126)
        self.assertNotIn('1password.sh', calls)


class PackagedDependencyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.log = self.root / 'install-targets'
        self.probe = self.root / 'dependency-query'
        self.env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'],
                        CALL_LOG=str(self.log), PROBE_LOG=str(self.probe),
                        DEPTEST_EXIT='0', MISSING_DEPS='')
        script = (HERE / 'vendor-packaged-apps.sh').read_text()
        script = script.replace('. /etc/os-release', 'ID=arch; ID_LIKE=')
        script = script.replace('((EUID != 0))', 'true')
        (self.root / 'vendor-packaged-apps.sh').write_text(script)
        recipes = self.root / 'vendor-packages'
        recipes.mkdir()
        (recipes / 'chrome.PKGBUILD').write_text("depends=('mesa' 'recipe-runtime>=2')\n")
        for name, content in [
            ('uname', 'echo aarch64'),
            ('pacman', '[[ $1 == -T ]] || exit 99\n'
                       'printf "%s\\n" "$@" >"$PROBE_LOG"\n'
                       '[[ -z $MISSING_DEPS ]] || printf "%s\\n" "$MISSING_DEPS"\n'
                       'exit "$DEPTEST_EXIT"'),
            # Capture the proposed transaction and cancel before any install,
            # network lookup, or package build can happen.
            ('pkexec', 'printf "%s\\n" "$@" >"$CALL_LOG"\nexit 126'),
        ]:
            path = self.bin / name
            path.write_text('#!/bin/bash\n' + content + '\n')
            path.chmod(0o755)

    def invoke(self):
        result = subprocess.run(['bash', str(self.root / 'vendor-packaged-apps.sh'), 'chrome'],
                                env=self.env, text=True, capture_output=True)
        targets = self.log.read_text().splitlines() if self.log.exists() else []
        return result, targets

    def test_satisfied_providers_are_preserved_and_full_upgrade_still_runs(self):
        result, targets = self.invoke()
        self.assertEqual(result.returncode, 126, result.stderr)
        self.assertEqual(targets, ['/usr/bin/pacman', '-Syu', '--needed', '--noconfirm'])
        queried = self.probe.read_text().splitlines()
        self.assertIn('base-devel', queried)
        self.assertIn('mesa', queried)
        self.assertIn('recipe-runtime>=2', queried)

    def test_missing_versioned_dependency_is_installed_without_replacing_mesa(self):
        self.env.update(DEPTEST_EXIT='127', MISSING_DEPS='recipe-runtime>=2\nlibarchive\nlibarchive')
        result, targets = self.invoke()
        self.assertEqual(result.returncode, 126, result.stderr)
        self.assertEqual(targets[4:], ['libarchive', 'recipe-runtime>=2'])

    def test_mesa_is_installed_when_no_provider_satisfies_it(self):
        self.env.update(DEPTEST_EXIT='127', MISSING_DEPS='mesa')
        result, targets = self.invoke()
        self.assertEqual(result.returncode, 126, result.stderr)
        self.assertEqual(targets[4:], ['mesa'])

    def test_dependency_query_failure_stops_before_authentication(self):
        self.env.update(DEPTEST_EXIT='1', MISSING_DEPS='partial-output')
        result, targets = self.invoke()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(targets, [])


class NativeMetadataTests(unittest.TestCase):
    def test_embedded_selects_highest_native_version_and_revision(self):
        index = '\n'.join(f'<a href="hqplayerd-{v}-{r}.fc44.{a}.rpm">build</a>' for v, r, a in [
            ('6.1.1', 5, 'aarch64'), ('6.2.0', 6, 'aarch64'), ('6.2.0', 7, 'aarch64'),
            ('99.0.0', 9, 'x86_64')])
        result = extra.resolve_hqplayer('hqplayer-embedded', 'aarch64', index)
        self.assertEqual(result['version'], '6.2.0-7')
        self.assertTrue(result['url'].endswith('.aarch64.rpm'))

    def test_desktop_uses_product_five_and_arm_form_without_version_pin(self):
        html = '''<h3>HQPlayer 6 Desktop: 6.9.0</h3><form>Debian 13<input name="form_id" value="six"></form>
<h3>HQPlayer 5 Desktop: 5.99.0</h3><form>Debian 13<input name="form_id" value="five"></form>
<h3>HQPlayer Embedded</h3>'''
        def submit(url, fields):
            self.assertEqual(fields['form_id'], 'five')
            return json.dumps(dict(success=True, data=dict(success=True, url='/bins/trixie/hqplayer5desktop_5.99.0-50_arm64.deb')))
        self.assertIn('5.99.0-50_arm64', extra.hqplayer_desktop_url(html, 'aarch64', submit))

    def test_embedded_rejects_wrong_arch_and_external_links(self):
        for index in ['<a href="hqplayerd-6.2.0-6.fc44.x86_64.rpm">',
                      '<a href="https://evil.invalid/hqplayerd-6.2.0-6.fc44.aarch64.rpm">']:
            with self.assertRaises(ValueError):
                extra.resolve_hqplayer('hqplayer-embedded', 'aarch64', index)

    def test_hyprmoncfg_requires_native_digest(self):
        release = dict(tag_name='v1.28.0', assets=[dict(name='hyprmoncfg_1.28.0_linux_arm64.tar.gz',
            digest='sha256:' + 'a'*64, size=123,
            browser_download_url='https://github.com/crmne/hyprmoncfg/releases/download/v1.28.0/hyprmoncfg_1.28.0_linux_arm64.tar.gz')])
        self.assertEqual(extra.resolve_hyprmoncfg('aarch64', json.dumps(release))['version'], '1.28.0')
        release['assets'][0]['digest'] = ''
        with self.assertRaises(ValueError):
            extra.resolve_hyprmoncfg('aarch64', json.dumps(release))


class FoyerMetadataTests(unittest.TestCase):
    def test_new_release_floats_and_wrong_arch_is_rejected(self):
        spec = importlib.util.spec_from_file_location('foyer', HERE / 'omarchy-desktop/install-foyer.py')
        foyer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(foyer)
        name = 'foyer_9.2.1_linux_arm64.tar.gz'
        release = dict(tag_name='v9.2.1', assets=[dict(name=name, digest='sha256:'+'a'*64,
            browser_download_url='https://github.com/tektum/foyer/releases/download/v9.2.1/'+name)])
        self.assertEqual(foyer.resolve(release, 'aarch64')[0], '9.2.1')
        with self.assertRaises(ValueError):
            foyer.resolve(release, 'x86_64')


class WineMetadataTests(unittest.TestCase):
    def test_provided_name_is_not_mistaken_for_old_installed_package(self):
        spec = importlib.util.spec_from_file_location('wine', HERE / 'wine-arm64ec.py')
        wine = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(wine)
        result = subprocess.CompletedProcess([], 0, 'wine-git 11.21.r1.g2528aff-31\n', '')
        with patch.object(wine.subprocess, 'run', return_value=result):
            self.assertIsNone(wine.installed('wine'))
            self.assertEqual(wine.installed('wine-git'), '11.21.r1.g2528aff-31')

    def test_native_packages_require_digests_and_correct_publisher(self):
        spec = importlib.util.spec_from_file_location('wine', HERE / 'wine-arm64ec.py')
        wine = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(wine)
        name = 'wine-git-11.21.r1.g2528aff-31-aarch64.pkg.tar.xz'
        release = dict(tag_name='arch-repo', assets=[dict(name=name, digest='sha256:'+'b'*64,
                       browser_download_url=wine.BASE+name)])
        self.assertEqual(wine.candidates(release)['wine-git']['version'], '11.21.r1.g2528aff-31')
        release['assets'][0]['browser_download_url'] = 'https://evil.invalid/'+name
        with self.assertRaises(ValueError):
            wine.candidates(release)


if __name__ == '__main__':
    unittest.main()
