"""Generated native fixtures exercise backup, signing, refusal and restoration."""
import contextlib
import importlib.util
import io
import json
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))
spec = importlib.util.spec_from_file_location("steam_debug", SCRIPT_DIR / "enable_steam_game_debugging.py")
workflow = importlib.util.module_from_spec(spec)
spec.loader.exec_module(workflow)


@unittest.skipUnless(sys.platform == "darwin", "Requires macOS codesign and APFS cloning")
class SteamDebugWorkflowTests(unittest.TestCase):
    def test_generated_fixture_workflow(self):
        with tempfile.TemporaryDirectory(prefix="davetrainer-steam-test-") as scratch:
            root = Path(scratch).resolve()
            source, prepared, backup = root / "Game.app", root / "prepared", root / "backup"
            for directory in ["Contents/MacOS", "Contents/Frameworks", "Contents/Resources/Data/il2cpp_data/Metadata"]:
                (source / directory).mkdir(parents=True, exist_ok=True)
            c_source = root / "main.c"
            c_source.write_text("int main(void) { return 0; }\n")
            subprocess.run(["clang", str(c_source), "-o", str(source / "Contents/MacOS/Fixture")], check=True)
            subprocess.run(["clang", "-dynamiclib", str(c_source), "-o", str(source / workflow.ASSEMBLY)], check=True)
            subprocess.run(["codesign", "--force", "--sign", "-", str(source / workflow.ASSEMBLY)], check=True)
            (source / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": "com.nexon.dave", "CFBundleExecutable": "Fixture",
                "CFBundlePackageType": "APPL", "CFBundleShortVersionString": workflow.SUPPORTED_VERSION,
            }))
            (source / "Contents/Resources/Data/boot.config").write_text("build-guid=" + workflow.SUPPORTED_GUID + "\n")
            (source / workflow.METADATA).write_bytes(b"generated fixture metadata")
            entitlements = root / "entitlements.plist"
            entitlements.write_bytes(plistlib.dumps({"com.apple.security.cs.disable-library-validation": True}))
            subprocess.run(["codesign", "--force", "--sign", "-", "--options", "runtime", "--entitlements", str(entitlements), str(source)], check=True)
            # Test-only reviewed identities: production constants remain strict.
            with patch.object(workflow, "SUPPORTED_ASSEMBLY", workflow.digest(source / workflow.ASSEMBLY)), patch.object(workflow, "SUPPORTED_METADATA", workflow.digest(source / workflow.METADATA)), contextlib.redirect_stdout(io.StringIO()):
                baseline = workflow.snapshot(source)
                workflow.prepare(source, prepared, backup)
                receipt = prepared / "receipt.json"
                self.assertEqual(workflow.snapshot(source), baseline)
                self.assertEqual(workflow.snapshot(backup / source.name), baseline)
                rejected = subprocess.run([sys.executable, str(SCRIPT_DIR / "enable_steam_game_debugging.py"), "apply", str(receipt)], capture_output=True, text=True)
                self.assertNotEqual(rejected.returncode, 0)
                self.assertIn("--allow-original-resign", rejected.stderr)
                self.assertEqual(workflow.snapshot(source), baseline)
                changed_asset = source / "Contents/Resources/steam-update.txt"
                changed_asset.write_text("changed after preparation")
                with self.assertRaisesRegex(ValueError, "changed since preparation"):
                    workflow.apply(receipt)
                changed_asset.unlink()
                real_run = subprocess.run
                def fail_applied_verification(command, *args, **kwargs):
                    if "--verify" in command and command[-1] == str(source):
                        raise subprocess.CalledProcessError(1, command)
                    return real_run(command, *args, **kwargs)
                with patch.object(workflow.subprocess, "run", side_effect=fail_applied_verification):
                    with self.assertRaises(subprocess.CalledProcessError) as failure:
                        workflow.apply(receipt)
                    self.assertIn("--verify", failure.exception.cmd)
                self.assertEqual(workflow.snapshot(source), baseline)
                workflow.apply(receipt)
                self.assertEqual(workflow.snapshot(source), json.loads(receipt.read_text())["applied"])
                self.assertEqual(workflow.entitlements(source), {
                    "com.apple.security.cs.disable-library-validation": True,
                    "com.apple.security.get-task-allow": True,
                })
                changed_asset.write_text("changed after apply")
                with self.assertRaisesRegex(ValueError, "changed after apply"):
                    workflow.restore(receipt)
                changed_asset.unlink()
                shutil.rmtree(prepared / source.name)
                workflow.restore(receipt)
                self.assertEqual(workflow.snapshot(source), baseline)
                subprocess.run(["codesign", "--verify", "--strict", str(source)], check=True)
                workflow.restore(receipt)
                self.assertEqual(workflow.snapshot(source), baseline)
                with patch.object(workflow.subprocess, "check_output", return_value="42 " + str(source / "Contents/MacOS/Fixture") + "\n"):
                    with self.assertRaisesRegex(ValueError, "running target"):
                        workflow.apply(receipt)
                self.assertEqual(workflow.snapshot(source), baseline)


if __name__ == "__main__":
    unittest.main()
