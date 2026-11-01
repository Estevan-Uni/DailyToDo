"""Run: python3 -m unittest discover -s scripts/tests -v

Only temporary bundles and an owned non-GUI child are created. No user App,
database, authorization or installed executable is modified by these tests.
"""
import hashlib
import importlib.util
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("app_output_guard", ROOT / "scripts/app-output-guard.py")
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)
BUNDLE_ID = "local.tododesktop.guardtest"


@unittest.skipUnless(sys.platform == "darwin", "Native App output protection requires macOS")
class AppOutputGuardTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="App output [guard] 测试-")
        self.folder = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def bundle(self, name="Test.app", info=None):
        app = self.folder / name
        (app / "Contents/MacOS").mkdir(parents=True)
        with (app / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump(info if info is not None else {"CFBundleIdentifier": BUNDLE_ID, "CFBundleExecutable": "DailyToDo"}, stream)
        return app

    def rejection(self, app, code):
        with self.assertRaises(guard.OutputGuardError) as caught:
            guard.check_destination(str(app), BUNDLE_ID)
        self.assertEqual(caught.exception.code, code)

    def test_fresh_destination_matches_exact_paths_not_prefixes(self):
        app = self.folder / "New.app"
        neighbor = app.parent / "New.app-neighbor/Contents/MacOS/DailyToDo"
        with patch.object(guard, "process_executables", return_value=iter([(123, neighbor)])):
            guard.check_destination(str(app), BUNDLE_ID)
        self.assertFalse(app.exists())

    def test_foreign_invalid_and_unexpected_executable_bundles_are_unchanged(self):
        for index, info in enumerate([{}, ["not", "a", "dictionary"], {"CFBundleIdentifier": "other.app", "CFBundleExecutable": "DailyToDo"},
                                      {"CFBundleIdentifier": BUNDLE_ID, "CFBundleExecutable": "Other"}]):
            app = self.bundle(f"Invalid-{index}.app", info)
            plist = app / "Contents/Info.plist"; before = plist.read_bytes()
            self.rejection(app, 2)
            self.assertEqual(plist.read_bytes(), before)
        app = self.bundle("Malformed.app")
        plist = app / "Contents/Info.plist"; plist.write_bytes(b"not a plist")
        self.rejection(app, 2)
        self.assertEqual(plist.read_bytes(), b"not a plist")

    def test_non_app_paths_and_extra_build_arguments_are_rejected_before_build(self):
        self.rejection(self.folder / "not-a-bundle", 2)
        existing_file = self.folder / "File.app"; existing_file.write_bytes(b"keep")
        self.rejection(existing_file, 2)
        result = subprocess.run([str(ROOT / "scripts/build-app.sh"), "debug", "unexpected"], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertNotIn("Building", result.stdout)
        self.assertEqual(existing_file.read_bytes(), b"keep")

    def test_legacy_executable_is_checked_before_name_upgrade(self):
        app = self.bundle("Legacy.app", {"CFBundleIdentifier": BUNDLE_ID, "CFBundleExecutable": "TodoDesktop"})
        before = (app / "Contents/Info.plist").read_bytes()
        with patch.object(guard, "process_executables", return_value=iter([(123, (app / "Contents/MacOS/TodoDesktop").resolve())])):
            self.rejection(app, 3)
        with patch.object(guard, "process_executables", return_value=iter([])):
            guard.check_destination(str(app), BUNDLE_ID)
        self.assertEqual((app / "Contents/Info.plist").read_bytes(), before)

    def test_unavailable_process_information_is_a_refusal(self):
        with patch.object(guard, "process_executables", side_effect=guard.OutputGuardError("unavailable", 3)):
            self.rejection(self.folder / "New.app", 3)
        self.assertFalse((self.folder / "New.app").exists())

    def test_native_relative_argv0_alias_and_build_preflight_preserve_live_output(self):
        app = self.bundle("Live [test].app")
        executable = app / "Contents/MacOS/DailyToDo"
        # An owned native child with relative argv[0], not a UI automation host.
        source = b"#include <unistd.h>\nint main(void) { for (;;) pause(); }\n"
        subprocess.run(["/usr/bin/clang", "-x", "c", "-", "-o", str(executable)], input=source, check=True, capture_output=True, timeout=20)
        child = subprocess.Popen(["./DailyToDo"], cwd=executable.parent)
        try:
            self.assertIsNone(child.poll())
            before = hashlib.sha256(executable.read_bytes()).hexdigest()
            self.rejection(app, 3)
            alias = self.folder / "别名 [alias].app"; alias.symlink_to(app, target_is_directory=True)
            self.rejection(alias, 3)
            result = subprocess.run([str(ROOT / "scripts/build-app.sh"), "debug"],
                                    env=dict(os.environ, APP_OUTPUT=str(alias), APP_BUNDLE_ID=BUNDLE_ID),
                                    text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 3, result.stderr)
            self.assertNotIn("Building", result.stdout)
            self.assertEqual(hashlib.sha256(executable.read_bytes()).hexdigest(), before)
            self.assertIsNone(child.poll())
            neighbor = self.bundle("Live [test]-neighbor.app")
            guard.check_destination(str(neighbor), BUNDLE_ID)
        finally:
            if child.poll() is None:
                child.terminate()
            child.wait(timeout=5)
        guard.check_destination(str(app), BUNDLE_ID)
