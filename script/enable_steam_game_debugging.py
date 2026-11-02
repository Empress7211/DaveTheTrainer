#!/usr/bin/env python3
"""Prepare, explicitly apply, or restore debugging permission on the Steam game."""
import argparse
import json
import os
import plistlib
import subprocess
import tempfile
from pathlib import Path

from prepare_debug_game_copy import digest, prepare as prepare_copy


SUPPORTED_VERSION = "v1.0.6.756.mac"
SUPPORTED_GUID = "1958d94b767741a5a13a2ae0032db743"
SUPPORTED_ASSEMBLY = "0a608e833f8df5ff22323f9712879e5dea6aac43327f622767e234d4714f4b82"
SUPPORTED_METADATA = "04b3ba2460dec827579c3668cf46408ffc353184a0947008319220eb6fbf56ed"
ASSEMBLY = "Contents/Frameworks/GameAssembly.dylib"
METADATA = "Contents/Resources/Data/il2cpp_data/Metadata/global-metadata.dat"


def snapshot(bundle):
    files = {}
    for path in sorted(bundle.rglob("*")):
        relative = str(path.relative_to(bundle))
        if path.is_symlink():
            files[relative] = {"symlink": os.readlink(path)}
        elif path.is_file():
            files[relative] = {"sha256": digest(path)}
    return files


def require_stopped(source, executable):
    selected = str((source / executable).resolve())
    output = subprocess.check_output(["/bin/ps", "-axo", "pid=,comm="], text=True)
    for line in output.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) == 2 and fields[1].strip() == selected:
            raise ValueError("Save and quit the Steam game first; refusing to alter a running target")


def sync_directory(directory):
    descriptor = os.open(directory, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def write_json(path, value):
    """Keep the previous JSON intact until the replacement is fully written."""
    descriptor, temporary = tempfile.mkstemp(prefix="." + path.name + "-", dir=path.parent)
    temporary = Path(temporary)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as file:
            json.dump(value, file, indent=2)
            file.write("\n")
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary, path)
        sync_directory(path.parent)
    finally:
        temporary.unlink(missing_ok=True)


def journal_path(path):
    return path.with_name(path.name + ".recovery.json")


def write_journal(path, receipt, operation):
    write_json(journal_path(path), {
        "schema": 1, "receipt_path": str(path.resolve()),
        "operation": operation, "receipt": receipt,
    })


def finish_receipt(path, receipt):
    write_json(path, receipt)
    journal_path(path).unlink(missing_ok=True)
    sync_directory(path.parent)


def read_receipt(path):
    recovery = journal_path(path)
    if recovery.exists():
        # A durable journal also recovers a missing/truncated legacy receipt.
        journal = json.loads(recovery.read_text())
        if (journal.get("schema") != 1 or journal.get("receipt_path") != str(path.resolve())
                or journal.get("operation") not in ("apply", "restore")):
            raise ValueError("Invalid recovery journal; preserve the full backup")
        receipt = journal["receipt"]
    else:
        receipt = json.loads(path.read_text())
    if receipt.get("schema") != 1:
        raise ValueError("Unsupported receipt")
    source = Path(receipt["source"]).resolve(strict=True)
    backup = Path(receipt["backup"]).resolve(strict=True)
    staged = Path(receipt["staged"]).resolve()
    paths = [source, backup, staged]
    if len(set(paths)) != 3 or any(first in second.parents for first in paths for second in paths if first != second):
        raise ValueError("Receipt paths must be independent")
    allowed = [receipt["executable"], "Contents/_CodeSignature/CodeResources"]
    executable_parts = Path(receipt["executable"]).parts
    if executable_parts[:2] != ("Contents", "MacOS") or len(executable_parts) != 3 or executable_parts[2] in (".", ".."):
        raise ValueError("Invalid executable in receipt")
    if receipt["allowed_changes"] != allowed:
        raise ValueError("Receipt must restrict changes to launcher and resource signature")
    for manifest in [receipt["prepared"], receipt.get("applied", receipt["prepared"])]:
        changed = {key for key in receipt["baseline"].keys() | manifest.keys()
                   if receipt["baseline"].get(key) != manifest.get(key)}
        if receipt["executable"] not in changed or not changed.issubset(set(allowed)):
            raise ValueError("Receipt changes exceed the authorized signing files")
        for relative in allowed:
            for state in [receipt["baseline"], manifest]:
                if set(state.get(relative, {})) != {"sha256"}:
                    raise ValueError("Signing files must be regular files in every recorded state")
    return receipt, source, backup, staged


def prepare(source, workspace, backup_root):
    source = source.resolve(strict=True)
    workspace, backup_root = workspace.resolve(), backup_root.resolve()
    if workspace.exists() or backup_root.exists():
        raise ValueError("Preparation and backup destinations must be new")
    paths = [source, workspace, backup_root]
    if len(set(paths)) != 3:
        raise ValueError("Preparation, backup and game paths must be independent")
    for first in paths:
        for second in paths:
            if first != second and (first in second.parents or second in first.parents):
                raise ValueError("Preparation, backup and game paths must not overlap")
    info = plistlib.loads((source / "Contents/Info.plist").read_bytes())
    executable_name = info.get("CFBundleExecutable", "")
    if info.get("CFBundleIdentifier") != "com.nexon.dave" or not executable_name or executable_name in (".", "..") or Path(executable_name).name != executable_name:
        raise ValueError("Expected a Dave game bundle with a valid executable")
    executable = "Contents/MacOS/" + executable_name
    if info.get("CFBundleShortVersionString") != SUPPORTED_VERSION:
        raise ValueError("This workflow requires the reviewed v1.0.6.756.mac build")
    boot = (source / "Contents/Resources/Data/boot.config").read_text()
    if "build-guid=" + SUPPORTED_GUID not in boot.splitlines():
        raise ValueError("Build GUID is not the reviewed build")
    require_stopped(source, executable)
    baseline = snapshot(source)
    if baseline.get(ASSEMBLY) != {"sha256": SUPPORTED_ASSEMBLY} or baseline.get(METADATA) != {"sha256": SUPPORTED_METADATA}:
        raise ValueError("GameAssembly or metadata does not match the reviewed build")
    workspace.mkdir(parents=True)
    backup_root.mkdir(parents=True)
    backup = backup_root / source.name
    staged = workspace / source.name
    subprocess.run(["/bin/cp", "-cR", str(source), str(backup)], check=True)
    prepare_copy(source, staged)
    if snapshot(backup) != baseline or snapshot(source) != baseline:
        raise ValueError("Original or backup changed during preparation; original was not modified")
    prepared = snapshot(staged)
    allowed = [executable, "Contents/_CodeSignature/CodeResources"]
    changed = {key for key in baseline.keys() | prepared.keys() if baseline.get(key) != prepared.get(key)}
    if executable not in changed or not changed.issubset(set(allowed)):
        raise ValueError("Prepared copy changed files outside the two expected signing files")
    receipt = {
        "schema": 1, "source": str(source), "backup": str(backup), "staged": str(staged),
        "executable": executable, "allowed_changes": allowed,
        "baseline": baseline, "prepared": prepared, "state": "prepared"
    }
    receipt_path = workspace / "receipt.json"
    write_json(receipt_path, receipt)
    print("PREPARED ONLY: Steam game has not been changed.")
    print("Original signature and every game file backed up:", backup)
    print("Reviewed changes: launcher code signature and bundle resource signature only.")
    print("Apply requires --allow-original-resign. Receipt:", receipt_path)


def replace_files(source, replacement, allowed):
    # Install exact, already-signed bytes on fresh inodes. Staging beside the
    # bundle keeps interrupted temporary copies out of its signed manifest.
    for relative in allowed:
        if source.parent.stat().st_dev != (source / relative).parent.stat().st_dev:
            raise ValueError("Atomic signing-file replacement requires a single filesystem")
    for relative in allowed:
        target = source / relative
        descriptor, temporary = tempfile.mkstemp(prefix=".davetrainer-signature-", dir=source.parent)
        os.close(descriptor)
        temporary = Path(temporary)
        try:
            subprocess.run(["/bin/cp", "-p", str(replacement / relative), str(temporary)], check=True)
            with temporary.open("rb") as file:
                os.fsync(file.fileno())
            os.replace(temporary, target)
            sync_directory(target.parent)
        finally:
            temporary.unlink(missing_ok=True)


def entitlements(bundle):
    return plistlib.loads(subprocess.check_output([
        "/usr/bin/codesign", "-d", "--entitlements", "-", "--xml", str(bundle)
    ]))


def apply(receipt_path):
    receipt, source, backup, staged = read_receipt(receipt_path)
    require_stopped(source, receipt["executable"])
    if journal_path(receipt_path).exists():
        raise ValueError("An interrupted operation needs recovery; run restore with this receipt before retrying apply")
    if snapshot(backup) != receipt["baseline"] or snapshot(staged) != receipt["prepared"]:
        raise ValueError("Backup or prepared bundle changed; no original files replaced")
    if snapshot(source) != receipt["baseline"]:
        raise ValueError("Steam game changed since preparation; prepare again for the current installation")
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(staged)], check=True)
    expected_entitlements = entitlements(staged)
    if expected_entitlements.get("com.apple.security.get-task-allow") is not True:
        raise ValueError("Prepared bundle does not allow debugging")
    # All possible installed file hashes are durable before the first mutation.
    # Do not independently re-sign the original: that could produce unrecorded
    # hashes if signing or receipt persistence is interrupted.
    receipt["applied"] = receipt["prepared"]
    receipt["state"] = "applying"
    write_journal(receipt_path, receipt, "apply")
    require_stopped(source, receipt["executable"])
    try:
        replace_files(source, staged, receipt["allowed_changes"])
        subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(source)], check=True)
        applied = snapshot(source)
        if applied != receipt["applied"]:
            raise ValueError("Original does not match the exact journaled signing files")
        if entitlements(source) != expected_entitlements:
            raise ValueError("Original did not receive exactly the reviewed entitlements")
        receipt["state"] = "applied"
        finish_receipt(receipt_path, receipt)
    except BaseException:
        if snapshot(source) != receipt["baseline"]:
            replace_files(source, backup, receipt["allowed_changes"])
        if snapshot(source) != receipt["baseline"]:
            raise RuntimeError("Apply failed and rollback could not be verified; preserve the full backup")
        receipt["state"] = "prepared"
        # On persistent storage failure, retain the journal so restore can
        # finalize recovery even if the main receipt is unreadable.
        try:
            finish_receipt(receipt_path, receipt)
        except OSError:
            pass
        raise
    print("Applied debug permission at the original Steam path:", source)
    print("GameAssembly, metadata, game resources and saves were not changed.")
    print("Launch normally through Steam, then attach the trainer.")


def restore(receipt_path):
    receipt, source, backup, _ = read_receipt(receipt_path)
    require_stopped(source, receipt["executable"])
    if snapshot(backup) != receipt["baseline"]:
        raise ValueError("Backup changed; refusing restore")
    current = snapshot(source)
    if current == receipt["baseline"]:
        receipt["state"] = "restored"
        finish_receipt(receipt_path, receipt)
        print("Original signature already restored; no files changed.")
        return
    applied = receipt.get("applied", receipt["prepared"])
    recoverable = journal_path(receipt_path).exists() and all(
        current.get(key) in (receipt["baseline"].get(key), applied.get(key))
        if key in receipt["allowed_changes"] else current.get(key) == receipt["baseline"].get(key)
        for key in current.keys() | receipt["baseline"].keys() | applied.keys()
    )
    if current != applied and not recoverable:
        raise ValueError("Steam game changed after apply; refusing to restore an old signature onto new assets")
    receipt["applied"] = applied
    receipt["state"] = "restoring"
    write_journal(receipt_path, receipt, "restore")
    replace_files(source, backup, receipt["allowed_changes"])
    if snapshot(source) != receipt["baseline"]:
        raise ValueError("Restored files differ from the original backup")
    receipt["state"] = "restored"
    finish_receipt(receipt_path, receipt)
    print("Restored exact original launcher, official signature and all original file hashes.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prepare_parser = commands.add_parser("prepare", help="Create backup and reviewed signed payload; leave Steam game unchanged")
    prepare_parser.add_argument("source", type=Path)
    prepare_parser.add_argument("workspace", type=Path)
    prepare_parser.add_argument("--backup", type=Path, required=True)
    apply_parser = commands.add_parser("apply", help="Replace only the two prepared signing files in the Steam game")
    apply_parser.add_argument("receipt", type=Path)
    apply_parser.add_argument("--allow-original-resign", action="store_true")
    restore_parser = commands.add_parser("restore", help="Restore exact original signing files; reject a changed Steam build")
    restore_parser.add_argument("receipt", type=Path)
    args = parser.parse_args()
    if args.command == "prepare":
        prepare(args.source, args.workspace, args.backup)
    elif args.command == "apply":
        if not args.allow_original_resign:
            parser.error("Explicit --allow-original-resign authorization is required; no Steam files changed")
        apply(args.receipt)
    else:
        restore(args.receipt)


if __name__ == "__main__":
    main()
