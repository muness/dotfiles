"""Validate stable Codex bundle selection and download metadata."""
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('vendor_metadata', Path(__file__).with_name('vendor-app-metadata.py'))
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)



class CodexMetadataTests(unittest.TestCase):
    def release(self, arch='aarch64'):
        name = f'codex-package-{arch}-unknown-linux-musl.tar.zst'
        return dict(tag_name='rust-v0.166.0', assets=[dict(
            name=name, digest='sha256:' + 'a' * 64, size=123,
            browser_download_url=f'https://github.com/openai/codex/releases/download/rust-v0.166.0/{name}')])

    def test_native_complete_bundle(self):
        for arch in metadata.ARCHES:
            result = metadata.resolve_codex(arch, json.dumps(self.release(arch)))
            self.assertEqual(result['package'], 'openai-codex-bin')
            self.assertEqual(result['version'], '0.166.0')
            self.assertIn(f'codex-package-{arch}-', result['url'])

    def test_invalid_metadata_rejected(self):
        for key, value in [('digest', ''), ('browser_download_url', 'https://example.com/codex'), ('size', 0)]:
            item = self.release()
            item['assets'][0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                metadata.resolve_codex('aarch64', json.dumps(item))

    def test_unstable_or_missing_native_asset_rejected(self):
        for change in [dict(prerelease=True), dict(draft=True), dict(tag_name='rust-v0.167.0-alpha.1'), dict(assets=[])]:
            item = self.release()
            item.update(change)
            with self.subTest(change=change), self.assertRaises(ValueError):
                metadata.resolve_codex('aarch64', json.dumps(item))


if __name__ == '__main__':
    unittest.main()
