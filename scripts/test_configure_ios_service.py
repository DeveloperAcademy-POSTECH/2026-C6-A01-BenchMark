import base64
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name('configure-ios-service.py')


def token(role='anon', project='kfzfzarslqdqmrazohej'):
    payload = base64.urlsafe_b64encode(json.dumps({'role': role, 'ref': project}).encode()).decode().rstrip('=')
    return 'eyJhbGciOiJIUzI1NiJ9.' + payload + '.test-signature'


class ConfigurationChecks(unittest.TestCase):
    def check_configuration(self, data):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'Service.local.plist'
            if data is not None:
                path.write_bytes(data)
            result = subprocess.run([sys.executable, str(SCRIPT), '--check', str(path)], capture_output=True, text=True)
            if data is not None:
                self.assertEqual(path.read_bytes(), data)
            else:
                self.assertFalse(path.exists())
            return result

    def test_public_keys_are_accepted_without_logging_values(self):
        for key in ['sb_publishable_test-only', token()]:
            with self.subTest(key_type=key[:3]):
                result = self.check_configuration(plistlib.dumps({'publishableKey': key}))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn(key, result.stdout + result.stderr)

    def test_missing_configuration_explains_setup(self):
        result = self.check_configuration(None)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('error:', result.stderr)
        self.assertIn('--from-cli --http-check', result.stderr)
        self.assertIn('In CI', result.stderr)

    def test_invalid_configurations_fail_without_logging_values(self):
        values = [
            {}, [], {'publishableKey': 123}, {'publishableKey': ''},
            {'publishableKey': 'sb_secret_test-only'},
            {'publishableKey': 'sb_publishable_'},
            {'publishableKey': 'sb_publishable_test with spaces'},
            {'publishableKey': 'sb_publishable_invalid$character'},
            {'publishableKey': token(role='service_role')},
            {'publishableKey': token(project='another-project')},
            {'publishableKey': 'ey.invalid.signature'},
            {'publishableKey': 'ey.only-two-parts'},
        ]
        for value in values:
            with self.subTest(value_type=type(value).__name__):
                result = self.check_configuration(plistlib.dumps(value))
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('Traceback', result.stderr)
                if isinstance(value, dict) and isinstance(value.get('publishableKey'), str) and value['publishableKey']:
                    self.assertNotIn(value['publishableKey'], result.stdout + result.stderr)

    def test_corrupt_plist_has_actionable_error(self):
        for data in [b'not a plist', b'<?xml version="1.0"?><plist><dict>']:
            result = self.check_configuration(data)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('configuration is missing or invalid', result.stderr)
            self.assertNotIn('Traceback', result.stderr)

    def test_setup_preserves_existing_configuration_in_both_apps(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'scripts').mkdir()
            script = root / 'scripts' / SCRIPT.name
            shutil.copyfile(SCRIPT, script)
            paths = [root / 'apps' / 'ios' / name / 'Service.local.plist' for name in ['OiDonation', 'OiDonationClip']]
            for path in paths:
                path.parent.mkdir(parents=True)
            existing = plistlib.dumps({'publishableKey': 'sb_publishable_existing-test'})
            paths[1].write_bytes(existing)
            result = subprocess.run([sys.executable, str(script)], capture_output=True, text=True,
                                    env={**os.environ, 'OI_SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_new-test'})
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(paths[0].exists())
            self.assertEqual(paths[1].read_bytes(), existing)


if __name__ == '__main__':
    unittest.main()
