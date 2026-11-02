# v1.0.6.756.mac Compatibility Evidence

This exact profile was reviewed against a local macOS installation on
2026-10-07. It provides all 22 player controls, including combined Diving God
mode, damage, currencies, inventory scopes, and main/jungle artisan flame.
Code targets and resource layouts have local static evidence and fixture checks;
actual gameplay behavior is still pending confirmation.

## Build Identity

| Field | Value |
| --- | --- |
| Bundle ID | `com.nexon.dave` |
| Version | `v1.0.6.756.mac` |
| Build GUID | `1958d94b767741a5a13a2ae0032db743` |
| GameAssembly arm64 UUID | `698AB592-0DAA-3787-9B22-43683C35F62B` |
| GameAssembly SHA-256 | `0a608e833f8df5ff22323f9712879e5dea6aac43327f622767e234d4714f4b82` |
| IL2CPP metadata version | `31` |
| IL2CPP metadata SHA-256 | `04b3ba2460dec827579c3668cf46408ffc353184a0947008319220eb6fbf56ed` |

## Reviewed Code Coverage

| Patch family | Included points | Baseline points |
| --- | ---: | ---: |
| God mode | 10 | 10 |
| Oxygen | 4 | 4 |
| Ammo | 21 | 21 |
| Crab traps | 7 | 7 |
| Weight | 14 | 14 |
| Damage | 21 | 28 |
| Player speed | 11 | 13 |
| Drones | 4 | 4 |
| Stamina | 4 | 4 |
| Wasabi | 5 | 5 |

The 101 final expected-byte windows were read directly from the local arm64
image using the final profile. Candidates were restricted to named methods,
bounded by the next distinct symbol address. No global RVA delta or runtime
scanning is used. Retired damage restore points (`damage.0`–`.2`, `.24`–`.27`)
and retired fish-speed restore points (`swimSpeed.11`–`.12`) are excluded:
this new profile never installed those old, unscoped patches.

Reviewed changes beyond relocation:

- `weight.13` at `0x210BBAC`: the exact 16-byte prologue includes a changed
  linker-dependent `ADRP x19` page immediate. Its replacement remains a float
  return. `wasabi.0` at `0x21D4F50` checks the unchanged 52-byte prefix through
  the first `RET`, avoiding unrelated relocated calls beyond that return.
- Damage call-site windows record the new exact `BL` encodings. Each selected
  call was checked against the buffed-damage getter within its target-specific
  caller. Shared attack-data getters are not patched globally.
- Normal harpoon damage at `0x1E2FBA8` now places its result in `x21`, rather
  than the old `x23`; the replacement writes `w21`. Capture/net paths retain
  their earlier branches and are not overwritten.
- Insect combat assigns the player pointer to the controller's `0x20` field and
  the enemy pointer to `0x28`. Enemy-to-player direct damage is at `0xDF38E0`;
  player-to-enemy direct damage is at `0xDF3940`. The two advantage paths for
  player attacks and the enemy advantage path were separately reviewed.
- RPG `DealDamage` hook `0x1959940` retains `x20 = target`, `w21 = damage`,
  `x0 = health`, with `x28` preserved by the enclosing function. Both policies
  use the existing shared-policy engine with independently reviewed resume
  `0x1959944`, null handler `0x1959ADC`, and `BattleUtils.IsEnemy` helper
  `0x195F3B0`. The 72 zero bytes at `0x940` were checked directly in the
  file-backed executable `__TEXT` segment: load commands end at `0x940`, and
  the first function begins at `0x988`. Section-only report reads do not map
  this header padding; its independent segment check is required.
- Farm and fish-farm movement helpers became compiler-generated local functions
  under `HandleInputs`. Farm speed is at `0xFDE3B0`, with literal `+12` and
  continuation `+16`. Fish-farm dash/walk are `0xF7EAC8`/`0xF7EAD0`.
  Village getter/setter at `0x1800730` retains its literal at `+12`, and village
  movement uses the speed field at `0x17F5FD4`. The copied relative encodings
  are checked against code regenerated for these new addresses.

## Reviewed Resource Layout

`DaveRuntimeLayout.v106756` is selected with the exact build and module UUID.
The `.675` default layout remains unchanged; `.710` resource controls remain
disabled. The `.756` layout does not fall back to older singleton slots.

| Runtime root or field | `.675` | `.756` |
| --- | ---: | ---: |
| SaveSystem instance MethodInfo slot | `0x98D7948` | `0x99A7AC0` |
| SaveSystem has-instance MethodInfo slot | `0x98D7950` | `0x99A7AC8` |
| IngredientsStorage instance MethodInfo slot | `0x98D6E88` | `0x99A6FD0` |
| IngredientsStorage constructor MethodInfo slot | `0x98D6E80` | `0x99A6FC8` |
| SaveData player info | `0x220` | `0x240` |
| SaveData main ingredients dictionary | `0x100` | `0x120` |
| SaveData jungle contents | `0x2A8` | `0x2C8` |
| SaveDataJungle village-items dictionary | `0x150` | `0x178` |

The singleton slots were located by arm64 symbol identity. Save-field offsets
were decoded from the installed v31 metadata type/field records and each type's
exported `g_FieldOffsetTable`. In particular, old jungle offset `0x150` is now
an unrelated gift list; using the old layout would be incorrect.

Reviewed unchanged leaf fields include SaveSystem's manager and its data
pointer (`0x50` each); save dirty flag (`0x29`); player gold/Bei/flame
(`0x10`/`0x24`/`0x38`, ObscuredInt); jungle player info (`0xD0`) and its plain
currency/flame (`0x10`/`0x14`); jungle ingredient dictionary (`0xA8`); item ID
and quantity (`0x10`/`0x14`); main IngredientsData fields (`0x10`, `0x20`,
`0x28`, `0x50`); and IngredientsSave ID/count (`0x10`/`0x4C`). Compiled
IngredientsEntity getters confirm type `0x14` and ItemsTID `0x54`.
The existing bounded dictionary traversal, object/ID checks, ObscuredInt
validation, cache invalidation, and write-readback checks are retained.

## Validation and Reproduction

The application builds locally with the installed macOS 26.5 SDK. Exact build,
UUID and all 101 code windows match the installed binary, and the RPG padding
matches its expected 72 zero bytes. A temporary standalone assertion runner
executed 125 diagnostic routines from the repository's profile, routing,
resource fixtures, ARM64 encoding and transaction checks, including new-layout
currency, all ingredient categories, jungle/village scopes and rejection of old
singleton slots, Mach self-memory access, attach-error diagnostics, and empty
managed dictionaries with null entries arrays. This is
supplementary verification, not an XCTest run.

`swift test` was attempted but this Command Line Tools installation lacks the
XCTest framework. The upstream macOS CI run for this first-time contribution
requires maintainer approval. Run the portable suite and optional **read-only**
local code-window check in an environment with XCTest:

```bash
DAVE_V106756_APP_PATH="/path/to/DaveTheDiver.app" swift test \
  --skip InstalledGameIntegrationTests \
  --skip Il2CppFeatureLocatorTests \
  --skip MachOModuleResolverTests
```

The excluded suites require the old `.675` installation or proprietary
fixtures. Without the environment variable, the new local integration test
skips. Game binaries, symbol-table dumps, compatibility reports and saves are
not committed.

Runtime still requires exact build identity and module UUID, code-byte
preflight, transactional code writes, and readback. The initial permission
investigation used a read-only debug copy. Subsequent authorized Steam-original
checks below verify live code writes and the UI gold operation. Full in-game
behavior validation remains pending; code-patch readback reports `bytesApplied`,
not confirmed gameplay behavior.

## Attach Permission Follow-up (2026-10-09)

The vendor-signed installation uses Hardened Runtime without `get-task-allow`. A root
trainer can still receive `task_for_pid ... failure (5)` in this case. Signing
policy diagnostics now explain this restriction, and trainer bundles carry the
debugging-tool entitlement. This does not override the target's protection.

An explicitly authorized local debug copy was created with
`script/prepare_debug_game_copy.py`. The copy retains the original entitlements
and adds `get-task-allow` to its launcher only. Its signature verifies; original
critical file hashes, copied build identity, GameAssembly and metadata remain
unchanged. The script was also exercised on an independently signed fixture,
including missing-authorization and existing-destination rejection. The Steam
installation and user saves were not modified by this preparation. The corrected preview successfully attached to the copy without administrator
elevation. A separately signed read-only probe also attached as the normal
user, verified the exact build and loaded module UUID, and matched all 101
expected code windows. No feature was enabled or game memory written. Full
gameplay and real-save resource verification remain pending.

## Steam Installation Setup

The normal Steam launch workflow is the intended player route. A debug copy
was used to isolate the attach restriction, not as a replacement for Steam
launching. The opt-in Steam setup prepares a complete original backup and a
reviewed signing payload while leaving the installation unchanged. It binds
the source to the exact version, GUID and GameAssembly/metadata hashes.
Application is separately authorized, changes only the launcher and resource
signature, preserves existing entitlements, adds `get-task-allow`, verifies
unchanged game assets and records applied hashes. Failed verification restores
the original signing files. Restore refuses a changed Steam installation.

Generated signed native fixtures exercised preparation, explicit-authorization
refusal, intervening update refusal, failed verification rollback, entitlement
retention and constrained application, stale restore refusal, exact/idempotent
restoration without the prepared payload, and running-target refusal. The
committed Python unittest repeats the file/signature checks and uses a mocked
process listing for its running-target guard. No proprietary fixtures are used.
The actual Steam original was fully backed up and, with explicit authorization
on 2026-10-09, received the reviewed debug entitlement. Strict signature
verification passes; the full file manifest confirms that only the launcher
and resource signature changed, with existing entitlements retained.

## Steam-Original Live Verification (2026-10-09)

The user launched the installed game from Steam. Its canonical process path
matches the original Steam installation, and the exact build and loaded module
UUID match the reviewed profile. The preview UI attaches with administrator
mode disabled; a separately signed normal-user probe matches all 101 loaded
code windows.

All 11 code controls, including speed and combined Diving God mode, completed
enable/readback/restore transactions. After each transaction, all 101 windows
and the 72-byte RPG code cave match the original baseline. The preview UI's
oxygen toggle also writes all four expected windows and restores them; a
separate process probe confirms both states.

After loading an existing save, read-only resource planning exercises the
actual live object traversal and intercepted write/readback paths for gold,
Bei, jungle currency, main/jungle artisan flame, all main ingredients, fish,
vegetables and seasonings. These eight controls have valid live targets. The
remaining upgrade-material and two jungle/village inventory scopes have no
existing entries in this save; populated fixtures cover those paths. An empty
managed dictionary with a null entries array now reports no existing inventory
rather than an invalid pointer; nonempty dictionaries still require valid
entries. The regression check covers both `.675` and `.756` without writes.

The preview UI applied gold `+1`. A separate normal-user probe confirmed the
complete 20-byte ObscuredInt payload, then restored and reread the exact original
bytes. No inventory writes were committed and no save files were directly
written by the trainer or probes. The complete save directory was backed up
before loading; the game's save change predates the gold test. Actual diving,
combat, restaurant effects, populated jungle inventory writes and full XCTest
execution remain unverified. Local debug-signature access may be reset by a
Steam update or file verification.

## Review Corrections (2026-11-02)

The 2026-10-09 observations above are historical. Full diving, combat,
restaurant and populated resource behavior is still pending player testing.
All `.756` writes are now gated by an explicit, session-only experimental
switch, off on every app launch. The operation service enforces the gate before
preflight or resource access, including programmatic requests; code restoration
remains allowed. `.675`, `.710` and unknown-build policies are unchanged.

The Steam signing workflow now installs the exact already-verified signing
payload on fresh inodes rather than independently re-signing the original.
Before either file changes, it fsyncs and atomically publishes a recovery
journal containing the original receipt and both permitted full manifests.
Receipts are also written by fsync plus atomic replacement. Receipt persistence
failure rolls the source back; a persistent storage failure retains the journal
for recovery. Interrupted restore accepts only journaled per-file
baseline/applied combinations, with all other assets unchanged. Unrecognized
signing bytes, changed backups and unrelated Steam changes are rejected.
Legacy applied receipts with independently signed hashes remain restorable.

Keep `receipt.json.recovery.json` beside the receipt until recovery completes.
After an interrupted operation, stop the game and run the usual `restore`
command with the receipt path, even if the main receipt is missing or truncated.
Recovery does not require the staged payload. It finalizes an atomic restored
receipt before removing the journal; apply can then be retried normally.

Local validation used complete Xcode and the same public XCTest command as CI:
196 XCTest cases (one optional installed-game case skipped), zero failures;
the three proprietary-installation test classes remain excluded as in CI.
Ten Python tests pass, including native codesign/APFS fixture preparation,
application, rollback and exact restoration; portable fault injection covers
receipt writes, partial restore, abrupt process exits, legacy receipts and
unrelated-change refusal. These checks use generated fixtures, not the user's
game, and do not substitute for gameplay validation. CI now runs both Python
and Swift tests on macOS for pushes as well as pull requests; upstream
contributor approval remains a maintainer action.
