import copy
from pathlib import Path
import runpy
import unittest

rules = runpy.run_path(str(Path(__file__).resolve().parents[1] / "scripts/check-boundaries.py"))


class ComponentBoundaryTests(unittest.TestCase):
    def test_allowed_logic(self):
        source = "import Foundation\nimport Combine\nlet clock: () -> Date\n// UserDefaults is an adapter"
        self.assertEqual(list(rules["violations"](source)), [])

    def test_forbidden_logic(self):
        for source in ["import SwiftUI", "import AppKit", "import WorkingOnAdapters",
                       "import NotchShell", "import NotchShellAdapters", "import WorkingOn",
                       "let defaults = UserDefaults.standard", "Timer()", "RunLoop.main",
                       "RunLoopCountdownScheduler()", "TaskNotchDelayScheduler()",
                       "try await Task.sleep(for: .seconds(1))", "let store = Thing.shared"]:
            with self.subTest(source=source):
                self.assertTrue(list(rules["violations"](source)))

    def test_graph_direction(self):
        manifest = {"targets": [
            {"name": "WorkingOn", "dependencies": []},
            {"name": "WorkingOnAdapters", "dependencies": [{"byName": ["WorkingOn", None]}]},
            {"name": "NotchShell", "dependencies": []},
            {"name": "NotchShellAdapters", "dependencies": [{"byName": ["NotchShell", None]}]},
            {"name": "MediaFeature", "dependencies": []},
        ]}
        self.assertEqual(list(rules["graph_violations"](manifest)), [])
        reversed_graph = copy.deepcopy(manifest)
        reversed_graph["targets"][0]["dependencies"] = [{"byName": ["WorkingOnAdapters", None]}]
        self.assertTrue(list(rules["graph_violations"](reversed_graph)))
        coupled_shell = copy.deepcopy(manifest)
        coupled_shell["targets"][2]["dependencies"] = [{"byName": ["WorkingOn", None]}]
        self.assertTrue(list(rules["graph_violations"](coupled_shell)))
        wrong_adapter = copy.deepcopy(manifest)
        wrong_adapter["targets"][3]["dependencies"] = [{"byName": ["WorkingOn", None]}]
        self.assertTrue(list(rules["graph_violations"](wrong_adapter)))
        self.assertTrue(list(rules["graph_violations"]({"targets": []})))

    def test_sources_and_build_settings(self):
        for target in rules["LOGIC_TARGETS"]:
            for extra in [{"path": "../../anotchup"}, {"settings": [{"unsafeFlags": ["-I", "app"]}]}]:
                manifest = {"targets": [
                    {"name": "WorkingOn", "dependencies": []},
                    {"name": "WorkingOnAdapters", "dependencies": [{"byName": ["WorkingOn", None]}]},
                    {"name": "NotchShell", "dependencies": []},
                    {"name": "NotchShellAdapters", "dependencies": [{"byName": ["NotchShell", None]}]},
                    {"name": "MediaFeature", "dependencies": []},
                ]}
                next(item for item in manifest["targets"] if item["name"] == target).update(extra)
                self.assertTrue(list(rules["graph_violations"](manifest)))


if __name__ == "__main__":
    unittest.main()
