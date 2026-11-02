import XCTest
import TrainerCore
@testable import DaveTheTrainer

final class TrainerOperationServiceTests: XCTestCase {
    func testV106756WritesAreGatedBeforePreflightUntilExplicitOptIn() throws {
        let applier = RecordingTrainerOperationApplier()
        let service = TrainerOperationService(configuration: .v106756(applier: applier))
        let context = TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.v106756)
        for featureID in DaveTrainerFeatureID.allCases {
            XCTAssertNotNil(service.buildCompatibilityFailure(featureID: featureID, gameBuild: context.gameBuild))
            XCTAssertTrue(service.unsupportedReason(featureID: featureID, gameBuild: context.gameBuild)?.contains("实验功能") == true)
            let result = try service.apply(
                TrainerOperationRequest(featureID: featureID, isEnabled: true, payload: .staticPatch(patchID: "god")),
                context: context
            )
            XCTAssertEqual(result.state, .unsupportedBuild)
            XCTAssertTrue(result.message.contains("实验功能"))
        }
        XCTAssertTrue(applier.preflightRequests.isEmpty)
        XCTAssertTrue(applier.requests.isEmpty)
    }

    func testV106756CodeRestorationDoesNotRequireOptIn() throws {
        let applier = RecordingTrainerOperationApplier()
        let service = TrainerOperationService(configuration: .v106756(applier: applier))
        let patch = TrainerOperationPayload.staticPatch(patchID: "oxygen")
        _ = try service.apply(
            TrainerOperationRequest(featureID: .oxygen, isEnabled: true, payload: patch),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.v106756, allowExperimentalFeatures: true)
        )
        let restored = try service.apply(
            TrainerOperationRequest(featureID: .oxygen, isEnabled: false, payload: patch),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.v106756)
        )
        XCTAssertEqual(restored.state, .bytesApplied)
        XCTAssertEqual(Array(applier.requests.suffix(4)).map(\.isEnabled), [false, false, false, false])
    }

    func testV106756ResourceWritesCannotBypassGateUsingDisabledRequest() throws {
        let quantity = RecordingRuntimeQuantityIncrementer(result: RuntimeQuantityIncrementResult(updatedAddressCount: 1))
        let service = TrainerOperationService(configuration: .v106756(
            applier: RecordingTrainerOperationApplier(), runtimeQuantityIncrementer: quantity
        ))
        let result = try service.apply(
            TrainerOperationRequest(featureID: .gold, isEnabled: false, payload: .runtimeQuantity(resourceID: .gold, valueText: "1")),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.v106756)
        )
        XCTAssertEqual(result.state, .unsupportedBuild)
        XCTAssertTrue(quantity.requests.isEmpty)
    }

    func testUnknownBuildStaticPatchReturnsUnsupportedWithoutWritingMemory() throws {
        let applier = RecordingTrainerOperationApplier()
        let service = TrainerOperationService(configuration: .test(applier: applier))
        let result = try service.apply(
            TrainerOperationRequest(featureID: .god, isEnabled: true, payload: .staticPatch(patchID: "god")),
            context: TrainerOperationContext(session: Self.session(), gameBuild: Self.unsupportedBuild)
        )

        XCTAssertEqual(result.state, .unsupportedBuild)
        XCTAssertTrue(result.message.contains("导出兼容报告"))
        XCTAssertTrue(applier.preflightRequests.isEmpty)
        XCTAssertTrue(applier.requests.isEmpty)
    }

    func testMultipleBuildProfilesRouteV106710ToItsExactPatchSet() throws {
        let baselineApplier = RecordingTrainerOperationApplier()
        let v106710Applier = RecordingTrainerOperationApplier()
        let service = TrainerOperationService(configurations: [
            .test(applier: baselineApplier),
            .v106710(applier: v106710Applier)
        ])

        let result = try service.apply(
            TrainerOperationRequest(
                featureID: .oxygen,
                isEnabled: true,
                payload: .staticPatch(patchID: "oxygen")
            ),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.v106710)
        )

        XCTAssertEqual(result.state, .bytesApplied)
        XCTAssertEqual(result.targetIDs, ["oxygen.0", "oxygen.1", "oxygen.2", "oxygen.3"])
        XCTAssertEqual(v106710Applier.requests.map(\.patch.id), result.targetIDs)
        XCTAssertEqual(v106710Applier.requests.map { $0.patch.points[0].rva }, [
            0x13F2_AD0,
            0x13F5_78C,
            0x1B60_BE8,
            0x1B6A_468
        ])
        XCTAssertTrue(baselineApplier.preflightRequests.isEmpty)
        XCTAssertTrue(baselineApplier.requests.isEmpty)
    }

    func testV106710UnsupportedFeatureIsRejectedWithoutWritingMemory() throws {
        let applier = RecordingTrainerOperationApplier()
        let service = TrainerOperationService(configuration: .v106710(applier: applier))

        let result = try service.apply(
            TrainerOperationRequest(
                featureID: .damage,
                isEnabled: true,
                payload: .staticPatch(patchID: "damage")
            ),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.v106710)
        )

        XCTAssertEqual(result.state, .unsupportedBuild)
        XCTAssertTrue(result.message.contains("尚未验证功能 damage"))
        XCTAssertTrue(applier.preflightRequests.isEmpty)
        XCTAssertTrue(applier.requests.isEmpty)
    }

    func testV106710ValuePatchUsesRelocatedSpeedTargets() throws {
        let applier = RecordingTrainerOperationApplier()
        let service = TrainerOperationService(configuration: .v106710(applier: applier))

        let result = try service.apply(
            TrainerOperationRequest(
                featureID: .swimSpeed,
                isEnabled: true,
                payload: .valuePatch(patchID: "swimSpeed", valueText: "7")
            ),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.v106710)
        )

        XCTAssertEqual(result.state, .bytesApplied)
        XCTAssertEqual(result.targetIDs, ["swimSpeed"])
        XCTAssertEqual(applier.requests.count, 1)
        XCTAssertEqual(applier.requests[0].patch.points.map(\.rva), [
            0x20A4_8AC,
            0x0B80_8D0,
            0x100B_AF4,
            0x0F64_794,
            0x1152_180,
            0x115B_59C
        ])
    }

    func testMultipleBuildProfilesRouteV106756ToItsExactPatchSet() throws {
        let baselineApplier = RecordingTrainerOperationApplier()
        let v106756Applier = RecordingTrainerOperationApplier()
        let service = TrainerOperationService(configurations: [
            .test(applier: baselineApplier),
            .v106710(applier: baselineApplier),
            .v106756(applier: v106756Applier)
        ])

        let result = try service.apply(
            TrainerOperationRequest(
                featureID: .oxygen,
                isEnabled: true,
                payload: .staticPatch(patchID: "oxygen")
            ),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.v106756, allowExperimentalFeatures: true)
        )

        XCTAssertEqual(result.state, .bytesApplied)
        XCTAssertEqual(result.targetIDs, ["oxygen.0", "oxygen.1", "oxygen.2", "oxygen.3"])
        XCTAssertEqual(v106756Applier.requests.map(\.patch.id), result.targetIDs)
        XCTAssertEqual(v106756Applier.requests.map { $0.patch.points[0].rva }, [
            0x14158D8,
            0x1418594,
            0x1BC023C,
            0x1BC9AE4
        ])
        XCTAssertTrue(baselineApplier.preflightRequests.isEmpty)
        XCTAssertTrue(baselineApplier.requests.isEmpty)
    }

    func testV106756OptedInFeaturesAreSupportedAndDamageUsesNewTargets() throws {
        let applier = RecordingTrainerOperationApplier()
        let service = TrainerOperationService(configuration: .v106756(applier: applier))
        for featureID in DaveTrainerFeatureID.allCases {
            XCTAssertNil(service.buildCompatibilityFailure(featureID: featureID, gameBuild: KnownGameBuild.v106756, allowExperimentalFeatures: true))
        }
        let result = try service.apply(
            TrainerOperationRequest(featureID: .damage, isEnabled: true, payload: .staticPatch(patchID: "damage")),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.v106756, allowExperimentalFeatures: true)
        )
        XCTAssertEqual(result.state, .bytesApplied)
        XCTAssertEqual(result.targetIDs, (3...23).map { "damage.\($0)" })
        XCTAssertEqual(applier.requests.first?.patch.points.first?.rva, 0x1E2FBA8)
    }

    func testV106756AllResourceControlsRouteToTheirIncrementers() throws {
        let quantity = RecordingRuntimeQuantityIncrementer(result: RuntimeQuantityIncrementResult(updatedAddressCount: 1))
        let ingredients = RecordingIngredientsInventoryIncrementer(result: IngredientsInventoryIncrementResult(updatedItemCount: 1))
        let jungle = RecordingJungleIngredientsInventoryIncrementer(result: JungleIngredientsInventoryIncrementResult(updatedItemCount: 1))
        let service = TrainerOperationService(configuration: .v106756(
            applier: RecordingTrainerOperationApplier(),
            runtimeQuantityIncrementer: quantity,
            ingredientsIncrementer: ingredients,
            jungleIngredientsIncrementer: jungle
        ))
        let context = TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.v106756, allowExperimentalFeatures: true)
        var operations: [(DaveTrainerFeatureID, TrainerOperationPayload)] = [.gold, .bei, .jungleGold, .artisan].map {
            ($0, .runtimeQuantity(resourceID: $0, valueText: "99"))
        }
        operations += [
            (.ingredients, .inventory(scope: .all, valueText: "99")),
            (.fishIngredients, .inventory(scope: .fish, valueText: "99")),
            (.vegetableIngredients, .inventory(scope: .vegetable, valueText: "99")),
            (.seasoningIngredients, .inventory(scope: .seasoning, valueText: "99")),
            (.upgradeMaterials, .inventory(scope: .upgrade, valueText: "99")),
            (.jungleIngredients, .jungleInventory(scope: .ingredientsAndVillageItems, valueText: "99")),
            (.seaPeopleVillageItems, .jungleInventory(scope: .villageItems, valueText: "99"))
        ]
        for (featureID, payload) in operations {
            let result = try service.apply(TrainerOperationRequest(featureID: featureID, isEnabled: true, payload: payload), context: context)
            XCTAssertEqual(result.state, .behaviorVerified)
        }
        XCTAssertEqual(quantity.requests.map(\.featureID), ["gold", "bei", "jungleGold", "artisan"])
        XCTAssertEqual(ingredients.requests.map(\.scope), [.all, .fish, .vegetable, .seasoning, .upgrade])
        XCTAssertEqual(jungle.requests.map(\.scope), [.ingredientsAndVillageItems, .villageItems])
    }

    func testV106756ResourceCannotUseAnUnreviewedCodePatch() throws {
        let applier = RecordingTrainerOperationApplier()
        let service = TrainerOperationService(configuration: .v106756(applier: applier))
        let result = try service.apply(
            TrainerOperationRequest(featureID: .gold, isEnabled: true, payload: .valuePatch(patchID: "gold", valueText: "999")),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.v106756, allowExperimentalFeatures: true)
        )
        XCTAssertEqual(result.state, .targetMismatch)
        XCTAssertTrue(applier.preflightRequests.isEmpty)
        XCTAssertTrue(applier.requests.isEmpty)
    }

    func testV106756ValuePatchUsesRelocatedSpeedTargets() throws {
        let applier = RecordingTrainerOperationApplier()
        let service = TrainerOperationService(configuration: .v106756(applier: applier))

        let result = try service.apply(
            TrainerOperationRequest(
                featureID: .swimSpeed,
                isEnabled: true,
                payload: .valuePatch(patchID: "swimSpeed", valueText: "7")
            ),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.v106756, allowExperimentalFeatures: true)
        )

        XCTAssertEqual(result.state, .bytesApplied)
        XCTAssertEqual(result.targetIDs, ["swimSpeed"])
        XCTAssertEqual(applier.requests.count, 1)
        XCTAssertEqual(applier.requests[0].patch.points.map(\.rva), [
            0x210BDFC,
            0xB81BC8,
            0x1029FDC,
            0xFDE3B0,
            0xF7FB70,
            0xF7EAC8,
            0xF7EAD0,
            0x1800730,
            0x17F5FD4,
            0x116F610,
            0x1178B3C
        ])
    }

    func testV106756WrongBuildGUIDIsRejectedBeforePreflight() throws {
        let applier = RecordingTrainerOperationApplier()
        let service = TrainerOperationService(configuration: .v106756(applier: applier))
        let build = GameBuildSignature(
            identity: GameBuildIdentity(bundleID: "com.nexon.dave", version: "v1.0.6.756.mac", buildGUID: "different-build"),
            paths: GameBuildPaths(executablePath: "/custom/game", metadataPath: "/custom/metadata")
        )
        let result = try service.apply(
            TrainerOperationRequest(featureID: .oxygen, isEnabled: true, payload: .staticPatch(patchID: "oxygen")),
            context: TrainerOperationContext(session: Self.session(), gameBuild: build)
        )
        XCTAssertEqual(result.state, .unsupportedBuild)
        XCTAssertTrue(applier.preflightRequests.isEmpty)
        XCTAssertTrue(applier.requests.isEmpty)
    }

    func testKnownPartialProfileCanPrepareBeforeSelectingAFeature() {
        let service = TrainerOperationService(configuration: .v106710(
            applier: RecordingTrainerOperationApplier()
        ))

        XCTAssertNil(service.buildSupportFailure(
            featureID: .divingGod,
            gameBuild: KnownGameBuild.v106710
        ))
        XCTAssertNotNil(service.buildCompatibilityFailure(
            featureID: .divingGod,
            gameBuild: KnownGameBuild.v106710
        ))
    }

    func testClearingRuntimeCachesAlsoClearsActiveValuePatchState() throws {
        let applier = RecordingTrainerOperationApplier()
        let service = TrainerOperationService(configuration: .test(applier: applier))
        let context = TrainerOperationContext(
            session: Self.session(),
            gameBuild: KnownGameBuild.current
        )

        _ = try service.apply(
            TrainerOperationRequest(
                featureID: .swimSpeed,
                isEnabled: true,
                payload: .valuePatch(patchID: "swimSpeed", valueText: "5")
            ),
            context: context
        )
        service.clearRuntimeCaches()
        _ = try service.apply(
            TrainerOperationRequest(
                featureID: .swimSpeed,
                isEnabled: false,
                payload: .valuePatch(patchID: "swimSpeed", valueText: "7")
            ),
            context: context
        )

        let expectedRestorePatch = try DefaultStaticGamePatches.makeValuePatch(
            id: "swimSpeed",
            valueText: "7"
        )
        XCTAssertEqual(applier.requests.last?.patch, expectedRestorePatch)
    }

    func testUnknownManifestFeatureReturnsTargetMismatchWithoutWritingMemory() throws {
        let applier = RecordingTrainerOperationApplier()
        let manifest = DaveTrainerManifest(schemaVersion: "1.0", gameBuild: KnownGameBuild.current, features: [])
        let service = TrainerOperationService(configuration: .test(manifest: manifest, applier: applier))
        let result = try service.apply(
            TrainerOperationRequest(featureID: .god, isEnabled: true, payload: .staticPatch(patchID: "god")),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.current)
        )

        XCTAssertEqual(result.state, .targetMismatch)
        XCTAssertTrue(applier.requests.isEmpty)
    }

    func testStaticPatchOutsideManifestFeatureReturnsTargetMismatchWithoutWritingMemory() throws {
        let applier = RecordingTrainerOperationApplier()
        let service = TrainerOperationService(configuration: .test(applier: applier))
        let result = try service.apply(
            TrainerOperationRequest(featureID: .god, isEnabled: true, payload: .staticPatch(patchID: "oxygen")),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.current)
        )

        XCTAssertEqual(result.state, .targetMismatch)
        XCTAssertTrue(applier.preflightRequests.isEmpty)
        XCTAssertTrue(applier.requests.isEmpty)
    }

    func testPatchGroupOutsideManifestFeatureReturnsTargetMismatchWithoutWritingMemory() throws {
        let applier = RecordingTrainerOperationApplier()
        let service = TrainerOperationService(configuration: .test(applier: applier))
        let result = try service.apply(
            TrainerOperationRequest(
                featureID: .divingGod,
                isEnabled: true,
                payload: .staticPatchGroup(patchIDs: ["god", "oxygen", "swimSpeed"])
            ),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.current)
        )

        XCTAssertEqual(result.state, .targetMismatch)
        XCTAssertTrue(applier.preflightRequests.isEmpty)
        XCTAssertTrue(applier.requests.isEmpty)
    }

    func testValuePatchOutsideManifestFeatureReturnsTargetMismatchWithoutWritingMemory() throws {
        let applier = RecordingTrainerOperationApplier()
        let service = TrainerOperationService(configuration: .test(applier: applier))
        let result = try service.apply(
            TrainerOperationRequest(featureID: .god, isEnabled: true, payload: .valuePatch(patchID: "swimSpeed", valueText: "6")),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.current)
        )

        XCTAssertEqual(result.state, .targetMismatch)
        XCTAssertTrue(applier.preflightRequests.isEmpty)
        XCTAssertTrue(applier.requests.isEmpty)
    }

    func testPatchGroupFailureRollsBackAndReturnsWriteFailedResult() throws {
        let applier = RecordingTrainerOperationApplier(failingPatchID: "oxygen.0", failingEnabledState: true)
        let service = TrainerOperationService(configuration: .test(applier: applier))
        let result = try service.apply(
            TrainerOperationRequest(
                featureID: .divingGod,
                isEnabled: true,
                payload: .staticPatchGroup(patchIDs: ["god", "oxygen", "ammo"])
            ),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.current)
        )

        XCTAssertEqual(result.state, .writeFailed)
        XCTAssertFalse(result.isMemoryApplied)
        XCTAssertEqual(applier.requests.map(\.patch.id), ["god.0", "oxygen.0", "god.0"])
        XCTAssertEqual(applier.requests.map(\.isEnabled), [true, true, false])
    }

    func testPatchGroupSuccessReturnsBytesAppliedResult() throws {
        let applier = RecordingTrainerOperationApplier()
        let service = TrainerOperationService(configuration: .test(applier: applier))
        let result = try service.apply(
            TrainerOperationRequest(
                featureID: .divingGod,
                isEnabled: true,
                payload: .staticPatchGroup(patchIDs: ["god", "oxygen"])
            ),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.current)
        )

        XCTAssertEqual(result.state, .bytesApplied)
        XCTAssertEqual(result.targetIDs, ["god.0", "oxygen.0"])
        XCTAssertTrue(result.isMemoryApplied)
    }

    func testPatchGroupPreflightTargetMismatchReturnsTargetMismatchResult() throws {
        let applier = RecordingTrainerOperationApplier(
            preflightError: TrainerError.targetMismatch("forced target mismatch")
        )
        let service = TrainerOperationService(configuration: .test(applier: applier))
        let result = try service.apply(
            TrainerOperationRequest(
                featureID: .divingGod,
                isEnabled: true,
                payload: .staticPatchGroup(patchIDs: ["god", "oxygen"])
            ),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.current)
        )

        XCTAssertEqual(result.state, .targetMismatch)
        XCTAssertFalse(result.isMemoryApplied)
        XCTAssertEqual(applier.requests.map(\.patch.id), [])
    }

    func testSinglePatchVerifyFailureReturnsVerifyFailedResult() throws {
        let applier = RecordingTrainerOperationApplier(
            failingPatchID: "god.0",
            failingEnabledState: true,
            applyError: TrainerError.verifyFailed("forced verify failure")
        )
        let service = TrainerOperationService(configuration: .test(applier: applier))
        let result = try service.apply(
            TrainerOperationRequest(featureID: .god, isEnabled: true, payload: .staticPatch(patchID: "god")),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.current)
        )

        XCTAssertEqual(result.state, .verifyFailed)
        XCTAssertFalse(result.isMemoryApplied)
    }

    func testSinglePatchFailureRollsBackPreviouslyAppliedPatchPoint() throws {
        let applier = RecordingTrainerOperationApplier(failingPatchID: "multiGod.1", failingEnabledState: true)
        let service = TrainerOperationService(configuration: .test(
            manifest: Self.manifest(featureID: .god, patchID: "multiGod"),
            applier: applier
        ))
        let result = try service.apply(
            TrainerOperationRequest(featureID: .god, isEnabled: true, payload: .staticPatch(patchID: "multiGod")),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.current)
        )

        XCTAssertEqual(result.state, .writeFailed)
        XCTAssertFalse(result.isMemoryApplied)
        XCTAssertEqual(applier.requests.map(\.patch.id), ["multiGod.0", "multiGod.1", "multiGod.0"])
        XCTAssertEqual(applier.requests.map(\.isEnabled), [true, true, false])
    }

    func testGoldIncrementUsesManifestCapabilityAndReturnsBehaviorVerified() throws {
        let runtimeIncrementer = RecordingRuntimeQuantityIncrementer(result: RuntimeQuantityIncrementResult(updatedAddressCount: 1))
        let service = TrainerOperationService(configuration: .test(
            applier: RecordingTrainerOperationApplier(),
            runtimeQuantityIncrementer: runtimeIncrementer
        ))
        let result = try service.apply(
            TrainerOperationRequest(featureID: .gold, isEnabled: true, payload: .runtimeQuantity(resourceID: .gold, valueText: "99")),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.current)
        )

        XCTAssertEqual(result.state, .behaviorVerified)
        XCTAssertEqual(result.targetIDs, ["gold"])
        XCTAssertEqual(runtimeIncrementer.requests, [RuntimeQuantityIncrementRequest(featureID: "gold", delta: 99)])
    }

    func testUnknownBuildRuntimeResourceReturnsUnsupportedWithoutWritingMemory() throws {
        let runtimeIncrementer = RecordingRuntimeQuantityIncrementer(result: RuntimeQuantityIncrementResult(updatedAddressCount: 1))
        let service = TrainerOperationService(configuration: .test(
            applier: RecordingTrainerOperationApplier(),
            runtimeQuantityIncrementer: runtimeIncrementer
        ))
        let result = try service.apply(
            TrainerOperationRequest(featureID: .gold, isEnabled: true, payload: .runtimeQuantity(resourceID: .gold, valueText: "99")),
            context: TrainerOperationContext(session: Self.session(), gameBuild: Self.unsupportedBuild)
        )

        XCTAssertEqual(result.state, .unsupportedBuild)
        XCTAssertTrue(runtimeIncrementer.requests.isEmpty)
    }

    func testResourceWithoutManifestCapabilityReturnsTargetMismatch() throws {
        let runtimeIncrementer = RecordingRuntimeQuantityIncrementer(result: RuntimeQuantityIncrementResult(updatedAddressCount: 1))
        let manifest = DaveTrainerManifest(
            schemaVersion: "1.0",
            gameBuild: KnownGameBuild.current,
            features: [
                DaveTrainerManifestFeature(id: .gold, title: "Gold", kind: .inventoryResource, targets: [])
            ]
        )
        let service = TrainerOperationService(configuration: .test(
            manifest: manifest,
            applier: RecordingTrainerOperationApplier(),
            runtimeQuantityIncrementer: runtimeIncrementer
        ))
        let result = try service.apply(
            TrainerOperationRequest(featureID: .gold, isEnabled: true, payload: .runtimeQuantity(resourceID: .gold, valueText: "99")),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.current)
        )

        XCTAssertEqual(result.state, .targetMismatch)
        XCTAssertEqual(runtimeIncrementer.requests, [])
    }

    func testRuntimeResourceVerifyFailureReturnsVerifyFailedResult() throws {
        let runtimeIncrementer = RecordingRuntimeQuantityIncrementer(error: TrainerError.verifyFailed("forced verify failure"))
        let service = TrainerOperationService(configuration: .test(
            applier: RecordingTrainerOperationApplier(),
            runtimeQuantityIncrementer: runtimeIncrementer
        ))
        let result = try service.apply(
            TrainerOperationRequest(featureID: .gold, isEnabled: true, payload: .runtimeQuantity(resourceID: .gold, valueText: "99")),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.current)
        )

        XCTAssertEqual(result.state, .verifyFailed)
        XCTAssertFalse(result.isMemoryApplied)
    }

    func testSeaPeopleVillageItemsUseVillageOnlyJungleScope() throws {
        let jungleIncrementer = RecordingJungleIngredientsInventoryIncrementer(
            result: JungleIngredientsInventoryIncrementResult(updatedItemCount: 2)
        )
        let service = TrainerOperationService(configuration: .test(
            applier: RecordingTrainerOperationApplier(),
            jungleIngredientsIncrementer: jungleIncrementer
        ))
        let result = try service.apply(
            TrainerOperationRequest(
                featureID: .seaPeopleVillageItems,
                isEnabled: true,
                payload: .jungleInventory(scope: .villageItems, valueText: "99")
            ),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.current)
        )

        XCTAssertEqual(result.state, .behaviorVerified)
        XCTAssertEqual(result.targetIDs, ["seaPeopleVillageItems"])
        XCTAssertEqual(jungleIncrementer.requests, [
            JungleIngredientsInventoryIncrementRequest(delta: 99, scope: .villageItems)
        ])
    }

    func testJungleInventoryFeatureScopeMismatchReturnsTargetMismatch() throws {
        let jungleIncrementer = RecordingJungleIngredientsInventoryIncrementer(
            result: JungleIngredientsInventoryIncrementResult(updatedItemCount: 2)
        )
        let service = TrainerOperationService(configuration: .test(
            applier: RecordingTrainerOperationApplier(),
            jungleIngredientsIncrementer: jungleIncrementer
        ))
        let result = try service.apply(
            TrainerOperationRequest(
                featureID: .jungleIngredients,
                isEnabled: true,
                payload: .jungleInventory(scope: .villageItems, valueText: "99")
            ),
            context: TrainerOperationContext(session: Self.session(), gameBuild: KnownGameBuild.current)
        )

        XCTAssertEqual(result.state, .targetMismatch)
        XCTAssertEqual(jungleIncrementer.requests, [])
    }

    private static var unsupportedBuild: GameBuildSignature {
        GameBuildSignature(
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
    }

    private static func session() -> MemorySession {
        MachMemoryAccess().currentProcessSession()
    }
}

private final class RecordingTrainerOperationApplier: StaticPatchApplying {
    private let failingPatchID: String?
    private let failingEnabledState: Bool?
    private let preflightError: Error?
    private let applyError: Error?
    private(set) var preflightRequests: [StaticPatchApplyRequest] = []
    private(set) var requests: [StaticPatchApplyRequest] = []

    init(
        failingPatchID: String? = nil,
        failingEnabledState: Bool? = nil,
        preflightError: Error? = nil,
        applyError: Error? = nil
    ) {
        self.failingPatchID = failingPatchID
        self.failingEnabledState = failingEnabledState
        self.preflightError = preflightError
        self.applyError = applyError
    }

    func preflight(_ request: StaticPatchApplyRequest, session: MemorySession) throws {
        preflightRequests.append(request)
        if let preflightError {
            throw preflightError
        }
    }

    func apply(_ request: StaticPatchApplyRequest, session: MemorySession) throws {
        requests.append(request)
        guard request.patch.id == failingPatchID, request.isEnabled == failingEnabledState else {
            return
        }
        throw applyError ?? TrainerError.memoryWriteFailed("forced failure")
    }
}

private extension TrainerOperationService.Configuration {
    static func test(
        manifest: DaveTrainerManifest = .current,
        applier: StaticPatchApplying,
        runtimeQuantityIncrementer: RuntimeQuantityIncrementing = RecordingRuntimeQuantityIncrementer(),
        ingredientsIncrementer: IngredientsInventoryIncrementing = RecordingIngredientsInventoryIncrementer(),
        jungleIngredientsIncrementer: JungleIngredientsInventoryIncrementing = RecordingJungleIngredientsInventoryIncrementer()
    ) -> TrainerOperationService.Configuration {
        TrainerOperationService.Configuration(
            manifest: manifest,
            staticPatches: TrainerOperationServiceTests.testPatches,
            valuePatchFactory: DefaultStaticGamePatches.makeValuePatch(id:valueText:),
            applier: applier,
            runtimeQuantityIncrementer: runtimeQuantityIncrementer,
            ingredientsIncrementer: ingredientsIncrementer,
            jungleIngredientsIncrementer: jungleIngredientsIncrementer,
            intentionallyUnsupportedFeatureIDs: []
        )
    }

    static func v106710(applier: StaticPatchApplying) -> TrainerOperationService.Configuration {
        let manifest = DaveTrainerManifest.v106710
        return TrainerOperationService.Configuration(
            manifest: manifest,
            staticPatches: Dictionary(
                uniqueKeysWithValues: DaveV106710StaticGamePatches.make().map { ($0.id, $0) }
            ),
            valuePatchFactory: DaveV106710StaticGamePatches.makeValuePatch(id:valueText:),
            applier: applier,
            runtimeQuantityIncrementer: RecordingRuntimeQuantityIncrementer(),
            ingredientsIncrementer: RecordingIngredientsInventoryIncrementer(),
            jungleIngredientsIncrementer: RecordingJungleIngredientsInventoryIncrementer(),
            intentionallyUnsupportedFeatureIDs: Set(DaveTrainerFeatureID.allCases).subtracting(
                manifest.features.map(\.id)
            )
        )
    }

    static func v106756(
        applier: StaticPatchApplying,
        runtimeQuantityIncrementer: RuntimeQuantityIncrementing = RecordingRuntimeQuantityIncrementer(),
        ingredientsIncrementer: IngredientsInventoryIncrementing = RecordingIngredientsInventoryIncrementer(),
        jungleIngredientsIncrementer: JungleIngredientsInventoryIncrementing = RecordingJungleIngredientsInventoryIncrementer()
    ) -> TrainerOperationService.Configuration {
        let manifest = DaveTrainerManifest.v106756
        return TrainerOperationService.Configuration(
            manifest: manifest,
            staticPatches: Dictionary(
                uniqueKeysWithValues: DaveV106756StaticGamePatches.make().map { ($0.id, $0) }
            ),
            valuePatchFactory: DaveV106756StaticGamePatches.makeValuePatch(id:valueText:),
            applier: applier,
            runtimeQuantityIncrementer: runtimeQuantityIncrementer,
            ingredientsIncrementer: ingredientsIncrementer,
            jungleIngredientsIncrementer: jungleIngredientsIncrementer,
            intentionallyUnsupportedFeatureIDs: Set(DaveTrainerFeatureID.allCases).subtracting(
                manifest.features.map(\.id)
            )
        )
    }
}

private final class RecordingRuntimeQuantityIncrementer: RuntimeQuantityIncrementing {
    private let result: RuntimeQuantityIncrementResult
    private let error: Error?
    private(set) var requests: [RuntimeQuantityIncrementRequest] = []
    private(set) var clearCallCount = 0

    init(
        result: RuntimeQuantityIncrementResult = RuntimeQuantityIncrementResult(updatedAddressCount: 0),
        error: Error? = nil
    ) {
        self.result = result
        self.error = error
    }

    func clearCachedAddresses() {
        clearCallCount += 1
    }

    func increment(
        _ request: RuntimeQuantityIncrementRequest,
        session: RuntimeQuantityMemorySession
    ) throws -> RuntimeQuantityIncrementResult {
        requests.append(request)
        if let error {
            throw error
        }
        return result
    }
}

private final class RecordingIngredientsInventoryIncrementer: IngredientsInventoryIncrementing {
    private let result: IngredientsInventoryIncrementResult
    private let error: Error?
    private(set) var requests: [IngredientsInventoryIncrementRequest] = []
    private(set) var clearCallCount = 0

    init(
        result: IngredientsInventoryIncrementResult = IngredientsInventoryIncrementResult(updatedItemCount: 0),
        error: Error? = nil
    ) {
        self.result = result
        self.error = error
    }

    func clearCachedAddresses() {
        clearCallCount += 1
    }

    func increment(
        _ request: IngredientsInventoryIncrementRequest,
        session: IngredientsInventoryMemorySession
    ) throws -> IngredientsInventoryIncrementResult {
        requests.append(request)
        if let error {
            throw error
        }
        return result
    }
}

private final class RecordingJungleIngredientsInventoryIncrementer: JungleIngredientsInventoryIncrementing {
    private let result: JungleIngredientsInventoryIncrementResult
    private let error: Error?
    private(set) var requests: [JungleIngredientsInventoryIncrementRequest] = []
    private(set) var clearCallCount = 0

    init(
        result: JungleIngredientsInventoryIncrementResult = JungleIngredientsInventoryIncrementResult(updatedItemCount: 0),
        error: Error? = nil
    ) {
        self.result = result
        self.error = error
    }

    func clearCachedAddresses() {
        clearCallCount += 1
    }

    func increment(
        _ request: JungleIngredientsInventoryIncrementRequest,
        session: JungleIngredientsInventoryMemorySession
    ) throws -> JungleIngredientsInventoryIncrementResult {
        requests.append(request)
        if let error {
            throw error
        }
        return result
    }
}

private extension TrainerOperationServiceTests {
    static let testPatches: [String: StaticGamePatch] = [
        "god": patch(id: "god"),
        "multiGod": patch(id: "multiGod", pointCount: 2),
        "oxygen": patch(id: "oxygen"),
        "ammo": patch(id: "ammo"),
        "swimSpeed": patch(id: "swimSpeed")
    ]

    static func patch(id: String, pointCount: Int = 1) -> StaticGamePatch {
        StaticGamePatch(
            id: id,
            title: id,
            points: (0..<pointCount).map { index in
                StaticPatchPoint(
                    rva: 0x1000 + UInt64(index * 4),
                    expectedBytes: [0x01, 0x02, 0x03, 0x04],
                    patchBytes: [0x05, 0x06, 0x07, 0x08],
                    note: id
                )
            }
        )
    }

    static func manifest(featureID: DaveTrainerFeatureID, patchID: String) -> DaveTrainerManifest {
        DaveTrainerManifest(
            schemaVersion: DaveTrainerManifest.currentSchemaVersion,
            gameBuild: KnownGameBuild.current,
            features: [
                DaveTrainerManifestFeature(
                    id: featureID,
                    title: featureID.rawValue,
                    kind: .codePatch,
                    targets: patchTargets(patchID: patchID)
                )
            ]
        )
    }

    static func patchTargets(patchID: String) -> [DaveTrainerManifestTarget] {
        guard let patch = testPatches[patchID] else {
            return []
        }
        return patch.points.enumerated().map { index, point in
            DaveTrainerManifestTarget.patchPoint(DaveManifestPatchPoint(
                id: "\(patchID).\(index)",
                moduleID: DaveTrainerManifest.gameAssemblyModuleID,
                point: point
            ))
        }
    }
}
