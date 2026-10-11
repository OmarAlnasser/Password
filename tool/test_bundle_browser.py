#!/usr/bin/env python3
"""Tests for tool/bundle_browser.py.

    python3 -I tool/test_bundle_browser.py
"""

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('bundle_browser', HERE / 'bundle_browser.py')
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)


class BundleBrowserTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.release = self.dir / 'Release'
        self.release.mkdir()
        self.helper = self.dir / 'built.exe'
        self.helper.write_bytes(b'MZ helper')

    def tearDown(self):
        self.tmp.cleanup()

    def test_the_manifest_key_gives_the_id_the_app_expects(self):
        manifest = json.loads((bundle.EXTENSION / 'manifest.json').read_text('utf-8'))
        self.assertEqual(bundle.extension_id(manifest['key']), bundle.expected_id())

    def test_copies_the_extension_and_the_helper_and_sets_the_version(self):
        bundle.main([str(self.release), '--version', '1.2.3', '--helper', str(self.helper)])
        self.assertEqual((self.release / 'khazna_bridge.exe').read_bytes(), b'MZ helper')
        ext = self.release / 'extension'
        manifest = json.loads((ext / 'manifest.json').read_text('utf-8'))
        self.assertEqual(manifest['version'], '1.2.3')
        for name in ('background.js', 'content.js', 'popup.html', 'popup.js',
                     'popup.css', '_locales/en/messages.json',
                     '_locales/ar/messages.json', 'icons/icon128.png'):
            self.assertTrue((ext / name).is_file(), name)
        self.assertFalse((ext / 'test').exists())

    def test_running_again_replaces_the_old_copy(self):
        bundle.main([str(self.release), '--helper', str(self.helper)])
        stale = self.release / 'extension' / 'stale.js'
        stale.write_text('old')
        bundle.main([str(self.release), '--helper', str(self.helper)])
        self.assertFalse(stale.exists())

    def test_refuses_a_bad_version_or_folder(self):
        with self.assertRaises(SystemExit):
            bundle.main([str(self.release), '--version', '1.2', '--helper', str(self.helper)])
        with self.assertRaises(SystemExit):
            bundle.main([str(self.dir / 'missing'), '--helper', str(self.helper)])

    def test_both_locales_have_the_same_messages(self):
        en = json.loads((bundle.EXTENSION / '_locales/en/messages.json').read_text('utf-8'))
        ar = json.loads((bundle.EXTENSION / '_locales/ar/messages.json').read_text('utf-8'))
        self.assertEqual(en.keys(), ar.keys())
        used = set()
        import re
        for js in ('background.js', 'content.js', 'popup.js'):
            text = (bundle.EXTENSION / js).read_text('utf-8')
            used |= set(re.findall(r"\bt\('(\w+)'", text))
        manifest = (bundle.EXTENSION / 'manifest.json').read_text('utf-8')
        used |= set(re.findall(r'__MSG_(\w+)__', manifest))
        self.assertEqual(used - en.keys(), set())


if __name__ == '__main__':
    unittest.main()
