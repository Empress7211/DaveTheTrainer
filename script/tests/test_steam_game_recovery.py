"""Portable failure injection; native signing is covered by the companion test."""
import contextlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from test_steam_game_debugging import workflow

REAL_RUN = subprocess.run
ALLOWED = ['Contents/MacOS/Fixture', 'Contents/_CodeSignature/CodeResources']
ENTITLEMENTS = {'com.apple.security.get-task-allow': True}


def fixture_run(command, *args, **kwargs):
    if command[0] == '/usr/bin/codesign':
        return subprocess.CompletedProcess(command, 0)
    return REAL_RUN(command, *args, **kwargs)


def crash_after_first_replacement(operation, receipt_path):
    """Exit without Python cleanup after the first actual atomic replacement."""
    receipt, source, _, _ = workflow.read_receipt(receipt_path)
    real_replace = workflow.os.replace
    def interrupted_replace(source_path, destination):
        real_replace(source_path, destination)
        if Path(destination) == source / receipt['executable']:
            workflow.os._exit(77)
    with patch.object(workflow, 'require_stopped'), patch.object(workflow, 'entitlements', return_value=ENTITLEMENTS), patch.object(workflow.subprocess, 'run', side_effect=fixture_run), patch.object(workflow.os, 'replace', side_effect=interrupted_replace):
        getattr(workflow, operation)(receipt_path)
    raise AssertionError('Crash point was not reached')


class SteamRecoveryFaultTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix='davetrainer-recovery-test-')
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name).resolve()
        self.source, self.backup, self.staged = (self.root / name for name in ['source.app', 'backup.app', 'staged.app'])
        for bundle, state in [(self.source, 'baseline'), (self.backup, 'baseline'), (self.staged, 'prepared')]:
            for relative in ALLOWED + ['Contents/Resources/unchanged.txt']:
                path = bundle / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                data = 'unchanged asset' if relative.endswith('unchanged.txt') else state + relative
                path.write_bytes(data.encode())
        self.receipt = {
            'schema': 1, 'source': str(self.source), 'backup': str(self.backup), 'staged': str(self.staged),
            'executable': ALLOWED[0], 'allowed_changes': ALLOWED,
            'baseline': workflow.snapshot(self.source), 'prepared': workflow.snapshot(self.staged), 'state': 'prepared',
        }
        self.path = self.root / 'receipt.json'
        workflow.write_json(self.path, self.receipt)
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
        self.stack.enter_context(patch.object(workflow, 'require_stopped'))
        self.stack.enter_context(patch.object(workflow, 'entitlements', return_value=ENTITLEMENTS))
        self.stack.enter_context(patch.object(workflow.subprocess, 'run', side_effect=fixture_run))

    def assert_original(self):
        self.assertEqual(workflow.snapshot(self.source), self.receipt['baseline'])
        self.assertEqual(workflow.snapshot(self.backup), self.receipt['baseline'])

    def test_receipt_persistence_failure_rolls_back_and_recovery_allows_retry(self):
        real_write = workflow.write_json
        def fail_receipt(path, value):
            if path == self.path:
                raise OSError('injected receipt write failure')
            return real_write(path, value)
        with patch.object(workflow, 'write_json', side_effect=fail_receipt):
            with self.assertRaisesRegex(OSError, 'receipt write failure'):
                workflow.apply(self.path)
        self.assert_original()
        self.assertTrue(workflow.journal_path(self.path).exists())
        self.assertEqual(json.loads(self.path.read_text())['state'], 'prepared')
        workflow.restore(self.path)
        self.assertFalse(workflow.journal_path(self.path).exists())
        workflow.apply(self.path)
        self.assertEqual(workflow.snapshot(self.source), self.receipt['prepared'])
        workflow.restore(self.path)
        self.assert_original()

    def test_atomic_receipt_write_failure_preserves_previous_json(self):
        original_bytes = self.path.read_bytes()
        real_replace = workflow.os.replace
        def fail_receipt_replace(source, destination):
            if Path(destination) == self.path:
                raise OSError('injected atomic receipt replacement failure')
            return real_replace(source, destination)
        with patch.object(workflow.os, 'replace', side_effect=fail_receipt_replace):
            with self.assertRaises(OSError):
                workflow.write_json(self.path, {'state': 'new'})
        self.assertEqual(self.path.read_bytes(), original_bytes)
        self.assertEqual(list(self.root.glob('.receipt.json-*')), [])
        self.assert_original()

    def test_journal_write_failure_prevents_game_mutation(self):
        with patch.object(workflow, 'write_journal', side_effect=OSError('injected journal failure')):
            with self.assertRaisesRegex(OSError, 'journal failure'):
                workflow.apply(self.path)
        self.assert_original()
        self.assertFalse(workflow.journal_path(self.path).exists())

    def test_second_restore_copy_failure_is_retryable(self):
        workflow.apply(self.path)
        def fail_second_copy(command, *args, **kwargs):
            if command[:2] == ['/bin/cp', '-p'] and command[2] == str(self.backup / ALLOWED[1]):
                raise subprocess.CalledProcessError(1, command)
            return fixture_run(command, *args, **kwargs)
        with patch.object(workflow.subprocess, 'run', side_effect=fail_second_copy):
            with self.assertRaises(subprocess.CalledProcessError):
                workflow.restore(self.path)
        mixed = workflow.snapshot(self.source)
        self.assertEqual(mixed[ALLOWED[0]], self.receipt['baseline'][ALLOWED[0]])
        self.assertEqual(mixed[ALLOWED[1]], self.receipt['prepared'][ALLOWED[1]])
        self.assertTrue(workflow.journal_path(self.path).exists())
        self.path.write_text('{truncated legacy receipt')
        shutil.rmtree(self.staged)
        workflow.restore(self.path)
        self.assert_original()
        self.assertEqual(json.loads(self.path.read_text())['state'], 'restored')
        self.assertFalse(workflow.journal_path(self.path).exists())

    def test_actual_process_exit_during_apply_and_restore_is_recoverable(self):
        for operation in ['apply', 'restore']:
            with self.subTest(operation=operation):
                if operation == 'restore':
                    workflow.apply(self.path)
                result = REAL_RUN([sys.executable, __file__, '--crash-after-first-replacement', operation, str(self.path)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 77, result.stderr)
                self.assertTrue(workflow.journal_path(self.path).exists())
                self.assertNotEqual(workflow.snapshot(self.source), self.receipt['baseline'])
                self.path.unlink()
                workflow.restore(self.path)
                self.assert_original()
                self.assertFalse(workflow.journal_path(self.path).exists())

    def test_active_journal_does_not_allow_unrelated_or_unknown_signing_changes(self):
        workflow.apply(self.path)
        current_receipt = json.loads(self.path.read_text())
        workflow.write_journal(self.path, current_receipt, 'restore')
        for relative in ['Contents/Resources/unchanged.txt', ALLOWED[0]]:
            with self.subTest(relative=relative):
                target = self.source / relative
                previous = target.read_bytes()
                target.write_bytes(b'unrecognized external change')
                before = workflow.snapshot(self.source)
                with self.assertRaisesRegex(ValueError, 'Steam game changed after apply'):
                    workflow.restore(self.path)
                self.assertEqual(workflow.snapshot(self.source), before)
                target.write_bytes(previous)
        workflow.restore(self.path)
        self.assert_original()

    def test_unjournaled_mixed_state_and_changed_backup_are_rejected(self):
        workflow.apply(self.path)
        (self.source / ALLOWED[0]).write_bytes((self.backup / ALLOWED[0]).read_bytes())
        with self.assertRaisesRegex(ValueError, 'Steam game changed after apply'):
            workflow.restore(self.path)
        (self.source / ALLOWED[0]).write_bytes((self.staged / ALLOWED[0]).read_bytes())
        (self.backup / ALLOWED[0]).write_bytes(b'changed backup')
        with self.assertRaisesRegex(ValueError, 'Backup changed'):
            workflow.restore(self.path)

    def test_legacy_receipt_with_independently_signed_applied_bytes_restores(self):
        for relative in ALLOWED:
            (self.source / relative).write_bytes(('legacy independently signed ' + relative).encode())
        legacy = dict(self.receipt, applied=workflow.snapshot(self.source), state='applied')
        workflow.write_json(self.path, legacy)
        workflow.restore(self.path)
        self.assert_original()

    def test_apply_requires_recovery_of_existing_journal(self):
        workflow.write_journal(self.path, dict(self.receipt, applied=self.receipt['prepared']), 'apply')
        with self.assertRaisesRegex(ValueError, 'run restore'):
            workflow.apply(self.path)
        self.assert_original()
        workflow.restore(self.path)
        workflow.apply(self.path)
        workflow.restore(self.path)
        self.assert_original()


if __name__ == '__main__':
    if len(sys.argv) == 4 and sys.argv[1] == '--crash-after-first-replacement':
        crash_after_first_replacement(sys.argv[2], Path(sys.argv[3]))
    else:
        unittest.main()
