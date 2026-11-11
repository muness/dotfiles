import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('power_change', Path(__file__).with_name('tlp-power-change.py'))
power_change = importlib.util.module_from_spec(spec)
spec.loader.exec_module(power_change)

class PowerChangeTests(unittest.TestCase):
    def test_only_actual_ac_transitions_run_tlp(self):
        with tempfile.TemporaryDirectory() as tmp:
            ac, state = Path(tmp) / 'online', Path(tmp) / 'state'
            ac.write_text('0')
            with patch.object(power_change, 'AC', ac), patch.object(power_change, 'STATE', state), \
                 patch.object(power_change.subprocess, 'run') as run:
                power_change.main()
                power_change.main()
                self.assertEqual(run.call_count, 1)
                ac.write_text('1')
                power_change.main()
                power_change.main()
                self.assertEqual(run.call_count, 2)
                self.assertEqual(state.read_text(), '1\n')
