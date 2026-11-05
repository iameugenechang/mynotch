"""Static rename contracts. No app launch or real-user data access."""
import json
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class IdentityTests(unittest.TestCase):
    def test_no_unclassified_legacy_names(self):
        allowed = json.loads((ROOT / "scripts/legacy-name-allowlist.json").read_text())
        paths = subprocess.check_output(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT
        ).decode().split("\0")
        pattern = re.compile(r"boring[ ._-]?notch|\bBoring[A-Z]\w*", re.IGNORECASE)
        failures = []
        for name in paths:
            path = ROOT / name
            if not name or not path.is_file():
                continue
            # Historical external feeds/automation and the explicit exception list.
            if name.startswith(("updater/", ".github/disabled-workflows/")) or name == "scripts/legacy-name-allowlist.json":
                continue
            if pattern.search(name):
                failures.append(name)
            try:
                text = path.read_text()
            except UnicodeDecodeError:
                continue
            for literal in allowed.get(name, []):
                text = text.replace(literal, "")
            if pattern.search(text):
                failures.append(name)
        self.assertEqual(failures, [])

    def test_app_and_helper_identity_agree(self):
        project = (ROOT / "anotchup.xcodeproj/project.pbxproj").read_text()
        self.assertEqual(project.count("PRODUCT_BUNDLE_IDENTIFIER = com.iameugenechang.anotchup;"), 2)
        helper = "com.iameugenechang.anotchup.AnotchupXPCHelper"
        self.assertEqual(project.count(f"PRODUCT_BUNDLE_IDENTIFIER = {helper};"), 2)
        client = (ROOT / "anotchup/XPCHelperClient/XPCHelperClient.swift").read_text()
        self.assertIn(f'private let serviceName = "{helper}"', client)
        self.assertIn("AnotchupXPCHelper.xpc in Embed XPC Services", project)
        self.assertIn("name = anotchup;", project)
        self.assertTrue((ROOT / "AnotchupXPCHelper/AnotchupXPCHelperProtocol.swift").exists())
        self.assertTrue((ROOT / "anotchup/XPCHelperClient/AnotchupXPCHelperProtocol.swift").exists())

    def test_migration_precedes_app_construction(self):
        app = (ROOT / "anotchup/anotchupApp.swift").read_text()
        self.assertIn("@main\nenum AnotchupBootstrap", app)
        self.assertNotIn("@main\nstruct AnotchupApp", app)
        self.assertLess(app.index("try PreferencesMigration.run("), app.index("AnotchupApp.main()"))
        self.assertIn('source: UserDefaultsDomain(name: "com.iameugenechang.mynotch")', app)
        self.assertIn('destination: UserDefaultsDomain(name: "com.iameugenechang.anotchup")', app)

    def test_publishing_is_quarantined(self):
        for name in ("release.yml", "nightly.yml", "static.yml", "crowdin.yml"):
            self.assertFalse((ROOT / ".github/workflows" / name).exists())
            self.assertTrue((ROOT / ".github/disabled-workflows" / name).exists())
        app = (ROOT / "anotchup/anotchupApp.swift").read_text()
        self.assertIn("startingUpdater: false", app)

    def test_localization_keys_remain_unique(self):
        def no_duplicates(pairs):
            result = {}
            for key, value in pairs:
                self.assertNotIn(key, result)
                result[key] = value
            return result
        catalog = json.loads((ROOT / "anotchup/Localizable.xcstrings").read_text(), object_pairs_hook=no_duplicates)
        self.assertIn("anotchup", catalog["strings"])


if __name__ == "__main__":
    unittest.main()
