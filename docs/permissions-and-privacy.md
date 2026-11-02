# Permissions And Privacy

DaveTheTrainer modifies a running macOS game process. macOS may require administrator authorization to attach to the game task and write memory.

## Permission Model

- The player GUI should not run arbitrary privileged commands.
- Elevation is only for attach/read/write work against the detected Dave game process.
- Unknown game builds are rejected before player memory writes. They can only
  use the explicit, read-only compatibility report path.
- Permission denial is reported directly to the player.

## Local Data

The app may read:

- The game bundle identity.
- The running game process identity.
- Build fingerprint files needed for manifest selection and feature validation.
- Local save files when the player uses backup features.

The app does not upload telemetry, memory dumps, save files, or diagnostics.
Compatibility reports are written locally only after the user chooses a
destination. They contain build fingerprints, public manifest RVAs, small
targeted byte samples, and symbol candidate RVAs. They exclude absolute paths
and full symbol names.

## Diagnostic Redaction

Public diagnostics must redact:

- Home directory paths.
- Raw memory addresses.
- Save file paths and Steam account directories.
- Unrelated process lists.
- Extracted game symbols and memory dumps.

## Administrator Mode And Target Signing Policy

Administrator credentials do not make a hardened third-party game debuggable.
If its signature does not permit debugging (`com.apple.security.get-task-allow`),
macOS can deny `task_for_pid` even when the trainer is already running as root.
The trainer inspects the selected executable's signing flags after a failed
attach and distinguishes this case from missing administrator elevation. It
does not change game signatures or system security settings automatically.
See Apple's [debugging tool entitlement documentation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.debugger).

Trainer bundles include the debugging-tool entitlement. This allows attaching
to eligible debug targets; it does not remove a target game's signing policy.

## Normal Steam Launching

`script/enable_steam_game_debugging.py` provides a separate, explicit setup for
the reviewed `.756.mac` Steam build. It does not run automatically from the GUI.
Save and quit the game before preparation or signing. Its three commands are:

```bash
# Read and clone only: keep a full exact original and prepare a signed payload.
python3 script/enable_steam_game_debugging.py prepare \
  "/path/to/Steam/DaveTheDiver.app" \
  "/path/to/new/preparation" --backup "/path/to/new/original-backup"

# Only after explicit authorization to replace the Steam game's local signature.
python3 script/enable_steam_game_debugging.py apply \
  "/path/to/new/preparation/receipt.json" --allow-original-resign

# With the game closed, restore its exact original signing files.
python3 script/enable_steam_game_debugging.py restore \
  "/path/to/new/preparation/receipt.json"
```

Preparation verifies the reviewed version, build GUID and complete
GameAssembly/metadata hashes. It compares all original and backed-up files and
allows changes only to the launcher and `Contents/_CodeSignature/CodeResources`.
Application rechecks the unchanged installation and backup, retains existing
entitlements, adds `get-task-allow`, verifies the signature and complete file
manifest, and records the applied hashes. A failed application restores the
original signing files. Restore refuses to put an old signature over a changed
Steam installation and works without the staged payload.

Signing files are atomically replaced with the verified payload, after a durable
`receipt.json.recovery.json` journal records both permitted file states. Keep
this journal beside the receipt after any interrupted operation. Run the same
`restore` command to recover, even if the main receipt is missing or truncated.
Only journaled baseline/applied combinations are accepted; unrelated asset
changes and unrecognized signing bytes are still refused. Receipt write failure
rolls back application, and partial restoration can be retried. Original
schema-1 receipts from earlier versions remain supported.

The official local launcher signature is replaced with an ad-hoc debug signature.
Local debugging tools can then access the game process. GameAssembly, metadata,
resources, bundle identity and the Steam launch path are retained; saves are not
edited. No SIP, Developer Tools setting or privileged helper is changed. After
setup, launch the game normally from Steam and attach the trainer. Steam updates
or file verification can restore the official signature; a changed build still
requires its own reviewed profile and setup evidence.

## Optional Independent Debug Copy

For an explicitly authorized local test, `script/prepare_debug_game_copy.py`
creates an independent copy and adds debug permission to the copy's launcher.
It requires the `--allow-debug-attach` flag, retains existing entitlements,
rejects an existing or overlapping destination, and verifies the original's
critical hashes and unchanged copied build identity, GameAssembly and metadata.
It does not change the Steam installation, modify saves, stop a running game,
install a privileged helper, or change SIP/Developer Tools settings.

```bash
python3 script/prepare_debug_game_copy.py \
  "/path/to/Steam/DaveTheDiver.app" \
  "/path/to/separate/DaveTheDiver-debug.app" \
  --allow-debug-attach
```

The copy is ad-hoc signed and permits local debugging. Save and quit the
original game before launching the copy, keep Steam running, and attach the
trainer to that copy. Use the Steam original for normal play when debugging
is no longer needed. The trainer still requires the exact supported build
and module UUID before any feature writes.
