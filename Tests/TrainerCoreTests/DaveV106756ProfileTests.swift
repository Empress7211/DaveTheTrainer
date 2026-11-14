import Foundation
import XCTest
@testable import TrainerCore

final class DaveV106756ProfileTests: XCTestCase {
    func testExactProfileIncludesAllPlayerFeatures() throws {
        let manifest = DaveTrainerManifest.v106756
        XCTAssertEqual(manifest.gameBuild.version, "v1.0.6.756.mac")
        XCTAssertEqual(manifest.gameBuild.buildGUID, "1958d94b767741a5a13a2ae0032db743")
        XCTAssertEqual(manifest.moduleIdentity(id: DaveTrainerManifest.gameAssemblyModuleID)?.machoUUID,
                       "698AB592-0DAA-3787-9B22-43683C35F62B")
        XCTAssertEqual(Set(manifest.features.map(\.id)), Set(DaveTrainerFeatureID.allCases))
        XCTAssertTrue(manifest.features.allSatisfy {
            $0.playerRuntimePolicy.requiresBuildMatch && !$0.playerRuntimePolicy.allowRuntimeScanning
        })
        let patches = DaveV106756StaticGamePatches.make()
        let speed = try DaveV106756StaticGamePatches.makeValuePatch(id: "swimSpeed", valueText: "7")
        XCTAssertEqual(patches.flatMap(\.points).count, 90)
        XCTAssertEqual(speed.points.compactMap(\.targetID), (0..<11).map { "swimSpeed.\($0)" })
        XCTAssertTrue((patches + [speed]).flatMap(\.points).allSatisfy {
            $0.patchBytes.count <= $0.expectedBytes.count
        })
        XCTAssertThrowsError(try DaveV106756StaticGamePatches.makeValuePatch(id: "gold", valueText: "999"))
        XCTAssertThrowsError(try DaveV106756StaticGamePatches.makeValuePatch(id: "swimSpeed", valueText: "nan"))
    }

    func testDamagePreservesNewHarpoonRegisterAndSkipsRetiredSharedGetters() throws {
        let damage = try XCTUnwrap(DaveV106756StaticGamePatches.make().first { $0.id == "damage" })
        XCTAssertEqual(damage.points.compactMap(\.targetID), (3...23).map { "damage.\($0)" })
        let harpoon = try XCTUnwrap(damage.points.first { $0.targetID == "damage.3" })
        XCTAssertEqual(harpoon.rva, 0x1E2FBA8)
        XCTAssertEqual(harpoon.patchBytes, try Arm64ReturnCode.moveInt32ToW21(999_999) + [0x1F, 0x20, 0x03, 0xD5])
    }

    func testInsectAndRPGPoliciesKeepPlayerAndEnemyTargetsSeparate() throws {
        let catalog = Dictionary(uniqueKeysWithValues: DaveV106756StaticGamePatches.make().map { ($0.id, $0) })
        let god = try XCTUnwrap(catalog["god"])
        let damage = try XCTUnwrap(catalog["damage"])
        XCTAssertEqual(god.points.first { $0.targetID == "god.7" }?.rva, 0xDF38E0)
        XCTAssertEqual(damage.points.first { $0.targetID == "damage.20" }?.rva, 0xDF3940)
        let ignore = try XCTUnwrap(god.points.first { $0.targetID == "god.9" })
        let superDamage = try XCTUnwrap(damage.points.first { $0.targetID == "damage.23" })
        XCTAssertEqual(ignore.rva, superDamage.rva)
        XCTAssertEqual(ignore.expectedBytes, [0xE0, 0x0C, 0x00, 0xB4])
        let ignorePolicy = try XCTUnwrap(ignore.trampoline)
        let damagePolicy = try XCTUnwrap(superDamage.trampoline)
        XCTAssertEqual(ignorePolicy.kind, .rpgDamagePolicyIgnoreDamage)
        XCTAssertEqual(damagePolicy.kind, .rpgDamagePolicySuperDamage)
        for policy in [ignorePolicy, damagePolicy] {
            XCTAssertEqual(policy.resumeRVA, 0x1959944)
            XCTAssertEqual(policy.nullHandlerRVA, 0x1959ADC)
            XCTAssertEqual(policy.helperRVA, 0x195F3B0)
            XCTAssertEqual(policy.codeCaveRVA, 0x940)
            XCTAssertEqual(policy.codeCaveExpectedBytes, Array(repeating: 0, count: 72))
        }
    }

    func testSpeedLiteralsAndBranchesUseReviewedRelativeDistances() throws {
        let speed = try DaveV106756StaticGamePatches.makeValuePatch(id: "swimSpeed", valueText: "7")
        let farm = try XCTUnwrap(speed.points.first { $0.targetID == "swimSpeed.3" })
        XCTAssertEqual(farm.patchBytes, try Arm64ReturnCode.loadFloat32LiteralToS0AndBranch(
            value: 7, patchRVA: 0xFDE3B0, literalRVA: 0xFDE3BC, continueRVA: 0xFDE3C0
        ))
        let village = try XCTUnwrap(speed.points.first { $0.targetID == "swimSpeed.7" })
        XCTAssertEqual(village.patchBytes, try Arm64ReturnCode.loadFloat32LiteralToS0ReturnAndDisableSetter(
            value: 7, patchRVA: 0x1800730, literalRVA: 0x180073C
        ))
    }

    // Optional read-only integration check. No binaries or diagnostic dumps are committed.
    func testInstalledV106756MatchesEveryReviewedByteWindow() throws {
        guard let path = ProcessInfo.processInfo.environment["DAVE_V106756_APP_PATH"] else {
            throw XCTSkip("Set DAVE_V106756_APP_PATH to the exact local v1.0.6.756 app bundle")
        }
        let app = URL(fileURLWithPath: path)
        let install = try GameInstallResolver().resolve(at: app)
        XCTAssertTrue(install.signature.matchesIdentity(of: KnownGameBuild.v106756))
        let patches = DaveV106756StaticGamePatches.make() + [
            try DaveV106756StaticGamePatches.makeValuePatch(id: "swimSpeed", valueText: "5")
        ]
        let points = patches.flatMap(\.points)
        let inspection = try MachOAnalyzer().inspectArm64(
            url: install.innerAppURL.appendingPathComponent("Contents/Frameworks/GameAssembly.dylib"),
            request: MachOBinaryInspectionRequest(
                symbolPrefixes: [],
                byteReads: points.map {
                    MachOByteReadRequest(id: $0.targetID!, rva: $0.rva, count: $0.expectedBytes.count)
                },
                symbolByteCount: 1
            )
        )
        XCTAssertEqual(inspection.uuid, "698AB592-0DAA-3787-9B22-43683C35F62B")
        XCTAssertEqual(inspection.byteReads.count, 101)
        let expected = Dictionary(uniqueKeysWithValues: points.map { ($0.targetID!, $0.expectedBytes) })
        for evidence in inspection.byteReads {
            guard case .bytes(let bytes) = evidence.result else {
                XCTFail("Unmapped target: \(evidence.request.id)")
                continue
            }
            XCTAssertEqual(bytes, expected[evidence.request.id], evidence.request.id)
        }
    }
}
