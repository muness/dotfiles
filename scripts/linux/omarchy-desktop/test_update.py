import unittest
from update import latest_release


class Releases(unittest.TestCase):
    def test_new_rc_beats_older_stable_maintenance(self):
        self.assertEqual(latest_release([
            {'tag_name': 'v4.0.7'}, {'tag_name': 'v4.5.0-rc3', 'prerelease': True},
            {'tag_name': 'v4.5.0-rc2', 'prerelease': True},
        ]), 'v4.5.0-rc3')

    def test_final_release_replaces_rc_without_changing_config(self):
        self.assertEqual(latest_release([
            {'tag_name': 'v4.5.0-rc10'}, {'tag_name': 'v4.5.0'},
        ]), 'v4.5.0')

    def test_drafts_and_unrelated_tags_never_install(self):
        self.assertEqual(latest_release([
            {'tag_name': 'v9.0.0', 'draft': True},
            {'tag_name': 'v4.5.0-rc3'}, {'tag_name': 'nightly'},
        ]), 'v4.5.0-rc3')


if __name__ == '__main__':
    unittest.main()
