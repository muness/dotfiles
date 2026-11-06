"""Regression checks for independently versioned BrowserOS installers."""
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('vendor_metadata', Path(__file__).with_name('vendor-app-metadata.py'))
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)


def release(version, tag='0.52.0', **flags):
    name = f'BrowserOS_neo_v{version}_arm64.deb'
    return dict(tag_name=f'browserclaw/v{tag}', assets=[dict(
        name=name, digest='sha256:' + 'a' * 64, size=123,
        browser_download_url=f'https://github.com/browseros-ai/BrowserOS/releases/download/browserclaw%2Fv{tag}/{name}')], **flags)


class BrowserOSMetadataTests(unittest.TestCase):
    def resolve(self, *releases):
        return metadata.resolve_browseros('aarch64', json.dumps(releases))

    def test_maintenance_build_under_older_tag(self):
        self.assertEqual(self.resolve(release('0.51.2.3', '0.51.2.3'), release('0.52.1.1'))['version'], '0.52.1.1')

    def test_prerelease_and_draft_excluded(self):
        self.assertEqual(self.resolve(release('0.52.1.1'), release('0.99.0', prerelease=True), release('0.98.0', draft=True))['version'], '0.52.1.1')

    def test_untrusted_download_rejected(self):
        item = release('0.52.1.1')
        item['assets'][0]['browser_download_url'] = 'https://example.com/browser.deb'
        with self.assertRaises(ValueError):
            self.resolve(item)

    def test_checksum_required(self):
        item = release('0.52.1.1')
        item['assets'][0]['digest'] = ''
        with self.assertRaises(ValueError):
            self.resolve(item)


if __name__ == '__main__':
    unittest.main()
