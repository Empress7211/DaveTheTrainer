#!/usr/bin/env python3
"""Prepare an explicitly authorized local debug copy; never alter the Steam app."""
import argparse
import hashlib
import plistlib
import subprocess
import tempfile
from pathlib import Path


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def prepare(source, destination):
    source = source.resolve(strict=True)
    destination = destination.resolve()
    if destination.exists():
        raise ValueError("Destination already exists; refusing to replace it")
    if source == destination or source in destination.parents or destination in source.parents:
        raise ValueError("Source and destination must be independent app paths")
    with (source / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("CFBundleIdentifier") != "com.nexon.dave":
        raise ValueError("Source is not the Dave game bundle")
    executable = info.get("CFBundleExecutable")
    if not executable or Path(executable).name != executable:
        raise ValueError("Invalid game executable name")
    critical = [
        Path("Contents/Info.plist"), Path("Contents/MacOS") / executable,
        Path("Contents/Frameworks/GameAssembly.dylib"),
        Path("Contents/Resources/Data/il2cpp_data/Metadata/global-metadata.dat")
    ]
    before = {str(path): digest(source / path) for path in critical}
    entitlement_output = subprocess.run(
        ["/usr/bin/codesign", "-d", "--entitlements", "-", "--xml", str(source)],
        check=True, capture_output=True
    ).stdout
    entitlements = plistlib.loads(entitlement_output) if entitlement_output.strip() else {}
    entitlements["com.apple.security.get-task-allow"] = True
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".davetrainer-debug-copy-", dir=destination.parent) as scratch:
        staged = Path(scratch) / source.name
        subprocess.run(["/bin/cp", "-cR", str(source), str(staged)], check=True)
        entitlement_path = Path(scratch) / "debug.entitlements"
        with entitlement_path.open("wb") as stream:
            plistlib.dump(entitlements, stream)
        subprocess.run([
            "/usr/bin/codesign", "--force", "--sign", "-", "--options", "runtime",
            "--entitlements", str(entitlement_path), str(staged)
        ], check=True)
        subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(staged)], check=True)
        checked = subprocess.run(
            ["/usr/bin/codesign", "-d", "--entitlements", "-", "--xml", str(staged)],
            check=True, capture_output=True
        )
        if plistlib.loads(checked.stdout).get("com.apple.security.get-task-allow") is not True:
            raise ValueError("Copy does not carry the requested debug permission")
        if {str(path): digest(source / path) for path in critical} != before:
            raise ValueError("Source changed during preparation; copy not promoted")
        # Signing changes only the copy's launcher signature. Build identity,
        # GameAssembly and metadata must remain identical to the approved source.
        for path in critical:
            if str(path).startswith("Contents/MacOS/"):
                continue
            if digest(staged / path) != before[str(path)]:
                raise ValueError("Critical game asset changed in copy: " + str(path))
        staged.rename(destination)
    print("Created independent debug copy:", destination)
    print("Steam original, build identity, GameAssembly, metadata and saves preserved.")
    print("Save and quit the running game before opening the copy; keep Steam running.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Original DaveTheDiver.app")
    parser.add_argument("destination", type=Path, help="New independent .app path")
    parser.add_argument("--allow-debug-attach", action="store_true", help="Explicitly authorize debugging of the COPY")
    args = parser.parse_args()
    if not args.allow_debug_attach:
        parser.error("Explicit --allow-debug-attach authorization is required; no files changed")
    if args.source.suffix != ".app" or args.destination.suffix != ".app":
        parser.error("Both paths must be .app bundles")
    prepare(args.source, args.destination)


if __name__ == "__main__":
    main()
