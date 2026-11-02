import XCTest
import TrainerCore
@testable import DaveTheTrainer

@MainActor
final class PlayerPathContractTests: XCTestCase {
    func testV106756OptInIsSessionOnlyAndBlocksResourceBeforeAttach() async throws {
        let install = GameInstall(
            outerAppURL: URL(fileURLWithPath: "/Applications/DaveTheDiver.app", isDirectory: true),
            innerAppURL: URL(fileURLWithPath: KnownGameBuild.v106756.executablePath).deletingLastPathComponent(),
            signature: KnownGameBuild.v106756
        )
        let memory = RecordingMemoryAccess()
        let store = AppStore(dependencies: .test(install: install, memoryAccess: memory))
        let gold = try XCTUnwrap(SimpleTrainerOptions.currencies.first { $0.id == "money" })
        XCTAssertTrue(store.showsExperimentalControls)
        XCTAssertFalse(store.allowExperimentalFeatures)
        XCTAssertTrue(store.unsupportedReason(for: gold)?.contains("实验功能") == true)
        let success = await withCheckedContinuation { continuation in
            store.applySimpleOption(SimpleTrainerActionRequest(option: gold, isEnabled: true, valueText: "1")) {
                continuation.resume(returning: $0)
            }
        }
        XCTAssertFalse(success)
        XCTAssertEqual(memory.attachCount, 0)
        store.allowExperimentalFeatures = true
        XCTAssertNil(store.unsupportedReason(for: gold))
        let fresh = AppStore(dependencies: .test(install: install))
        XCTAssertFalse(fresh.allowExperimentalFeatures)
        XCTAssertNotNil(fresh.unsupportedReason(for: gold))
    }

    func testDefaultPlayerViewDoesNotExposeDeveloperStaticFeatureControls() throws {
        let viewSource = try Self.readProjectFile("Sources/DaveTrainerApp/Views/SimpleTrainerView.swift")

        XCTAssertFalse(viewSource.contains("Button(\"特征\")"))
        XCTAssertFalse(viewSource.contains("refreshStaticFeatures()"))
    }

    func testDefaultPlayerViewExposesExplicitCompatibilityReportExport() throws {
        let viewSource = try Self.readProjectFile("Sources/DaveTrainerApp/Views/SimpleTrainerView.swift")

        XCTAssertTrue(viewSource.contains("Label(\"导出兼容报告\""))
        XCTAssertTrue(viewSource.contains("store.exportCompatibilityReport()"))
    }

    func testQuickPrepareDoesNotRunDeveloperStaticFeatureLocator() throws {
        let storeSource = try Self.readProjectFile("Sources/DaveTrainerApp/Stores/AppStore.swift")
        let quickPrepareBody = try Self.functionBody(named: "quickPrepare", in: storeSource)

        XCTAssertFalse(quickPrepareBody.contains("refreshStaticFeatures()"))
        XCTAssertFalse(quickPrepareBody.contains("locateStaticFeatures"))
        XCTAssertFalse(quickPrepareBody.contains("exportCompatibilityReport"))
    }

    func testDefaultPlayerOptionsAreManifestBacked() {
        let manifestIDs = Set(DaveTrainerManifest.current.features.map(\.id.rawValue))
        let optionIDs = Set(SimpleTrainerOptions.allPlayerOptions.map(\.manifestFeatureID))

        XCTAssertEqual(optionIDs.subtracting(manifestIDs), [])
    }

    func testDefaultPlayerOptionsDisallowRuntimeScanning() throws {
        let manifest = DaveTrainerManifest.current

        for option in SimpleTrainerOptions.allPlayerOptions {
            let featureID = try XCTUnwrap(DaveTrainerFeatureID(rawValue: option.manifestFeatureID))
            let feature = try XCTUnwrap(manifest.feature(id: featureID))
            XCTAssertFalse(feature.playerRuntimePolicy.allowRuntimeScanning, option.id)
        }
    }

    func testDefaultPlayerActionsDoNotUseLegacyScannerWriteOrFreeze() {
        let legacyActions = SimpleTrainerOptions.allPlayerOptions.filter { option in
            switch option.action {
            case .write, .freeze:
                return true
            case .increment, .incrementInventory, .incrementJungleInventory, .patch, .patchGroup, .valuePatch, .unavailable:
                return false
            }
        }

        XCTAssertEqual(legacyActions.map(\.id), [])
    }

    func testStoreResolvesInstallFromRunningProcessInsteadOfFixedApplicationsPath() {
        let install = Self.unsupportedInstall
        let process = TargetProcess(
            pid: getpid(),
            name: "DAVE THE DIVER",
            executablePath: install.signature.executablePath
        )
        let installResolver = RunningProcessOnlyGameInstallResolver(install: install)

        let store = AppStore(dependencies: AppStore.Dependencies(
            installResolver: installResolver,
            processResolver: FixedProcessResolver(process: process),
            runtime: AppStore.Dependencies.Runtime(memoryAccess: CurrentProcessMemoryAccess())
        ))

        XCTAssertEqual(store.install?.signature, install.signature)
        XCTAssertEqual(store.targetProcess, process)
        XCTAssertEqual(installResolver.runningProcessResolveCount, 1)
        XCTAssertEqual(installResolver.fixedPathResolveCount, 0)
    }

    func testUnknownBuildPatchIsRejectedWithoutMarkingPatchEnabled() async throws {
        let memoryAccess = RecordingMemoryAccess()
        let store = AppStore(dependencies: .test(install: Self.unsupportedInstall, memoryAccess: memoryAccess))
        let option = try XCTUnwrap(SimpleTrainerOptions.diving.first { $0.id == "god" })

        let completionResult = await withCheckedContinuation { continuation in
            store.applySimpleOption(SimpleTrainerActionRequest(
                option: option,
                isEnabled: true,
                valueText: option.defaultValue
            )) { success in
                continuation.resume(returning: success)
            }
        }

        XCTAssertEqual(completionResult, false)
        XCTAssertFalse(store.isPatchEnabled(id: "god"))
        XCTAssertEqual(store.latestOperationResult?.state, .unsupportedBuild)
        XCTAssertTrue(store.latestMessageIsError)
        XCTAssertEqual(memoryAccess.attachCount, 0)
    }

    func testUnknownBuildRuntimeResourceIsRejected() async throws {
        let memoryAccess = RecordingMemoryAccess()
        let store = AppStore(dependencies: .test(install: Self.unsupportedInstall, memoryAccess: memoryAccess))
        let option = try XCTUnwrap(SimpleTrainerOptions.currencies.first { $0.id == "money" })

        let completionResult = await withCheckedContinuation { continuation in
            store.applySimpleOption(SimpleTrainerActionRequest(
                option: option,
                isEnabled: true,
                valueText: option.defaultValue
            )) { success in
                continuation.resume(returning: success)
            }
        }

        XCTAssertEqual(completionResult, false)
        XCTAssertEqual(store.latestOperationResult?.state, .unsupportedBuild)
        XCTAssertTrue(store.latestMessageIsError)
        XCTAssertEqual(memoryAccess.attachCount, 0)
    }

    func testPartialBuildDisablesOnlyFeaturesWithoutExactEvidence() throws {
        let store = AppStore(dependencies: .test(install: Self.v106710Install))
        let god = try XCTUnwrap(SimpleTrainerOptions.diving.first { $0.id == "god" })
        let damage = try XCTUnwrap(SimpleTrainerOptions.diving.first { $0.id == "damage" })

        XCTAssertNil(store.unsupportedReason(for: god))
        XCTAssertTrue(store.unsupportedReason(for: damage)?.contains("v1.0.6.710.mac") == true)
        XCTAssertTrue(store.logs.contains { $0.contains("已收录 9/22 个功能") })
    }

    private static var unsupportedInstall: GameInstall {
        GameInstall(
            outerAppURL: URL(fileURLWithPath: "/Applications/DaveTheDiver.app", isDirectory: true),
            innerAppURL: URL(fileURLWithPath: KnownGameBuild.current.executablePath).deletingLastPathComponent(),
            signature: GameBuildSignature(
                identity: GameBuildIdentity(
                    bundleID: KnownGameBuild.current.bundleID,
                    version: "unsupported",
                    buildGUID: "unsupported-build"
                ),
                paths: GameBuildPaths(
                    executablePath: KnownGameBuild.current.executablePath,
                    metadataPath: KnownGameBuild.current.metadataPath
                )
            )
        )
    }

    private static var v106710Install: GameInstall {
        GameInstall(
            outerAppURL: URL(fileURLWithPath: "/Applications/DaveTheDiver.app", isDirectory: true),
            innerAppURL: URL(fileURLWithPath: KnownGameBuild.v106710.executablePath).deletingLastPathComponent(),
            signature: KnownGameBuild.v106710
        )
    }

    private static func readProjectFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = root.appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func functionBody(named name: String, in source: String) throws -> String {
        guard let signatureRange = source.range(of: "func \(name)()") else {
            throw XCTSkip("Function \(name) not found")
        }
        let rest = source[signatureRange.lowerBound...]
        guard let openingBrace = rest.firstIndex(of: "{") else {
            throw XCTSkip("Function \(name) has no body")
        }

        var depth = 0
        var end = openingBrace
        for index in source[openingBrace...].indices {
            if source[index] == "{" {
                depth += 1
            } else if source[index] == "}" {
                depth -= 1
                if depth == 0 {
                    end = index
                    break
                }
            }
        }
        return String(source[openingBrace...end])
    }
}

private extension AppStore.Dependencies {
    static func test(install: GameInstall, memoryAccess: MemoryAccess = CurrentProcessMemoryAccess()) -> AppStore.Dependencies {
        AppStore.Dependencies(
            installResolver: FixedGameInstallResolver(install: install),
            processResolver: FixedProcessResolver(),
            runtime: AppStore.Dependencies.Runtime(memoryAccess: memoryAccess)
        )
    }
}

private struct FixedGameInstallResolver: GameInstallResolving {
    let install: GameInstall

    func resolveInstalledGame() throws -> GameInstall {
        install
    }

    func resolveRunningGame(_ process: TargetProcess) throws -> GameInstall {
        install
    }

    func validateCurrentInstall() throws -> GameInstall {
        install
    }
}

private struct FixedProcessResolver: ProcessResolving {
    let process: TargetProcess?

    init(process: TargetProcess? = nil) {
        self.process = process
    }

    func resolve(_ request: ProcessResolveRequest) throws -> TargetProcess {
        if let process {
            return process
        }
        return TargetProcess(
            pid: getpid(),
            name: "DAVE THE DIVER",
            executablePath: request.executablePath
        )
    }
}

private final class RunningProcessOnlyGameInstallResolver: GameInstallResolving {
    let install: GameInstall
    private(set) var runningProcessResolveCount = 0
    private(set) var fixedPathResolveCount = 0

    init(install: GameInstall) {
        self.install = install
    }

    func resolveInstalledGame() throws -> GameInstall {
        fixedPathResolveCount += 1
        throw TrainerError.installNotFound("fixed path should not be used")
    }

    func resolveRunningGame(_ process: TargetProcess) throws -> GameInstall {
        runningProcessResolveCount += 1
        return install
    }

    func validateCurrentInstall() throws -> GameInstall {
        install
    }
}

private struct CurrentProcessMemoryAccess: MemoryAccess {
    func attach(to process: TargetProcess) throws -> MemorySession {
        MachMemoryAccess().currentProcessSession()
    }
}

private final class RecordingMemoryAccess: MemoryAccess {
    private(set) var attachCount = 0

    func attach(to process: TargetProcess) throws -> MemorySession {
        attachCount += 1
        return MachMemoryAccess().currentProcessSession()
    }
}
