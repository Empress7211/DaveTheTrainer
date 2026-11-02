import Foundation
import TrainerCore

struct TrainerOperationContext {
    let session: MemorySession
    let gameBuild: GameBuildSignature
    let allowExperimentalFeatures: Bool

    init(session: MemorySession, gameBuild: GameBuildSignature, allowExperimentalFeatures: Bool = false) {
        self.session = session
        self.gameBuild = gameBuild
        self.allowExperimentalFeatures = allowExperimentalFeatures
    }
}

enum TrainerOperationPayload {
    case staticPatch(patchID: String)
    case staticPatchGroup(patchIDs: [String])
    case valuePatch(patchID: String, valueText: String)
    case runtimeQuantity(resourceID: DaveTrainerFeatureID, valueText: String)
    case inventory(scope: IngredientsInventoryScope, valueText: String)
    case jungleInventory(scope: JungleDLCInventoryScope, valueText: String)
}

struct TrainerOperationRequest {
    let featureID: DaveTrainerFeatureID
    let isEnabled: Bool
    let payload: TrainerOperationPayload
}

private struct ValuePatchOperation {
    let patchID: String
    let valueText: String
    let request: TrainerOperationRequest
    let context: TrainerOperationContext
}

private struct OperationResultDraft {
    let featureID: DaveTrainerFeatureID
    let state: DaveTrainerOperationState
    let targets: [String]
    let message: String
}

protocol RuntimeQuantityIncrementing {
    func clearCachedAddresses()
    func increment(_ request: RuntimeQuantityIncrementRequest, session: RuntimeQuantityMemorySession) throws -> RuntimeQuantityIncrementResult
}

extension RuntimeQuantityIncrementer: RuntimeQuantityIncrementing {}

protocol IngredientsInventoryIncrementing {
    func clearCachedAddresses()
    func increment(_ request: IngredientsInventoryIncrementRequest, session: IngredientsInventoryMemorySession) throws -> IngredientsInventoryIncrementResult
}

extension IngredientsInventoryIncrementer: IngredientsInventoryIncrementing {}

protocol JungleIngredientsInventoryIncrementing {
    func clearCachedAddresses()
    func increment(_ request: JungleIngredientsInventoryIncrementRequest, session: JungleIngredientsInventoryMemorySession) throws -> JungleIngredientsInventoryIncrementResult
}

extension JungleIngredientsInventoryIncrementer: JungleIngredientsInventoryIncrementing {}

typealias StaticValuePatchFactory = (_ id: String, _ valueText: String) throws -> StaticGamePatch

final class TrainerOperationService {
    struct Configuration {
        private struct LiveProfile {
            let manifest: DaveTrainerManifest
            let patches: [StaticGamePatch]
            let valuePatchFactory: StaticValuePatchFactory
            let runtimeLayout: DaveRuntimeLayout
            let unsupportedFeatureIDs: Set<DaveTrainerFeatureID>
        }

        let manifest: DaveTrainerManifest
        let staticPatches: [String: StaticGamePatch]
        let valuePatchFactory: StaticValuePatchFactory
        let applier: StaticPatchApplying
        let runtimeQuantityIncrementer: RuntimeQuantityIncrementing
        let ingredientsIncrementer: IngredientsInventoryIncrementing
        let jungleIngredientsIncrementer: JungleIngredientsInventoryIncrementing
        let intentionallyUnsupportedFeatureIDs: Set<DaveTrainerFeatureID>

        static func liveProfiles() -> [Configuration] {
            [
                live(LiveProfile(
                    manifest: .current,
                    patches: DefaultStaticGamePatches.make(),
                    valuePatchFactory: DefaultStaticGamePatches.makeValuePatch(id:valueText:),
                    runtimeLayout: .v106675,
                    unsupportedFeatureIDs: []
                )),
                live(LiveProfile(
                    manifest: .v106710,
                    patches: DaveV106710StaticGamePatches.make(),
                    valuePatchFactory: DaveV106710StaticGamePatches.makeValuePatch(id:valueText:),
                    runtimeLayout: .v106675,
                    unsupportedFeatureIDs: Set(DaveTrainerFeatureID.allCases).subtracting(
                        DaveTrainerManifest.v106710.features.map(\.id)
                    )
                )),
                live(LiveProfile(
                    manifest: .v106756,
                    patches: DaveV106756StaticGamePatches.make(),
                    valuePatchFactory: DaveV106756StaticGamePatches.makeValuePatch(id:valueText:),
                    runtimeLayout: .v106756,
                    unsupportedFeatureIDs: Set(DaveTrainerFeatureID.allCases).subtracting(
                        DaveTrainerManifest.v106756.features.map(\.id)
                    )
                ))
            ]
        }

        private static func live(_ profile: LiveProfile) -> Configuration {
            let moduleResolver = MachOModuleResolver(
                expectedModuleIdentity: profile.manifest.moduleIdentity(id: DaveTrainerManifest.gameAssemblyModuleID)
            )
            return Configuration(
                manifest: profile.manifest,
                staticPatches: Dictionary(uniqueKeysWithValues: profile.patches.map { ($0.id, $0) }),
                valuePatchFactory: profile.valuePatchFactory,
                applier: StaticPatchEngine(moduleResolver: moduleResolver),
                runtimeQuantityIncrementer: RuntimeQuantityIncrementer(moduleResolver: moduleResolver, layout: profile.runtimeLayout),
                ingredientsIncrementer: IngredientsInventoryIncrementer(moduleResolver: moduleResolver, layout: profile.runtimeLayout),
                jungleIngredientsIncrementer: JungleIngredientsInventoryIncrementer(moduleResolver: moduleResolver, layout: profile.runtimeLayout),
                intentionallyUnsupportedFeatureIDs: profile.unsupportedFeatureIDs
            )
        }
    }

    private let profileServices: [TrainerBuildOperationService]

    convenience init() {
        self.init(configurations: Configuration.liveProfiles())
    }

    init(configuration: Configuration) {
        self.profileServices = [TrainerBuildOperationService(configuration: configuration)]
    }

    init(configurations: [Configuration]) {
        precondition(!configurations.isEmpty, "TrainerOperationService requires at least one build profile")
        self.profileServices = configurations.map(TrainerBuildOperationService.init)
        precondition(Self.hasUniqueBuildIdentities(profileServices), "Duplicate trainer build profile identity")
    }

    func clearRuntimeCaches() {
        profileServices.forEach { $0.clearRuntimeCaches() }
    }

    func apply(
        _ request: TrainerOperationRequest,
        context: TrainerOperationContext
    ) throws -> DaveTrainerOperationResult {
        guard let service = matchingService(for: context.gameBuild) else {
            return unsupportedBuildResult(featureID: request.featureID, actual: context.gameBuild)
        }
        if service.intentionallyUnsupportedFeatureIDs.contains(request.featureID) {
            return unsupportedFeatureResult(featureID: request.featureID, service: service)
        }
        let isCodeRestore: Bool
        switch request.payload {
        case .staticPatch, .staticPatchGroup, .valuePatch:
            isCodeRestore = !request.isEnabled
        default:
            isCodeRestore = false
        }
        if !isCodeRestore, let reason = experimentalReason(service: service, allowed: context.allowExperimentalFeatures) {
            return DaveTrainerOperationResult(featureID: request.featureID, state: .unsupportedBuild, targetIDs: [], message: reason)
        }
        return try service.apply(request, context: context)
    }

    func buildCompatibilityFailure(
        featureID: DaveTrainerFeatureID,
        gameBuild: GameBuildSignature,
        allowExperimentalFeatures: Bool = false
    ) -> DaveTrainerOperationResult? {
        guard let service = matchingService(for: gameBuild) else {
            return unsupportedBuildResult(featureID: featureID, actual: gameBuild)
        }
        guard service.intentionallyUnsupportedFeatureIDs.contains(featureID) else {
            if let reason = experimentalReason(service: service, allowed: allowExperimentalFeatures) {
                return DaveTrainerOperationResult(featureID: featureID, state: .unsupportedBuild, targetIDs: [], message: reason)
            }
            return nil
        }
        return unsupportedFeatureResult(featureID: featureID, service: service)
    }

    func buildSupportFailure(
        featureID: DaveTrainerFeatureID,
        gameBuild: GameBuildSignature
    ) -> DaveTrainerOperationResult? {
        guard matchingService(for: gameBuild) == nil else {
            return nil
        }
        return unsupportedBuildResult(featureID: featureID, actual: gameBuild)
    }

    func unsupportedReason(
        featureID: DaveTrainerFeatureID,
        gameBuild: GameBuildSignature,
        allowExperimentalFeatures: Bool = false
    ) -> String? {
        guard let service = matchingService(for: gameBuild) else {
            return "当前构建没有精确 profile；仅可导出兼容报告。"
        }
        guard service.intentionallyUnsupportedFeatureIDs.contains(featureID) else {
            return experimentalReason(service: service, allowed: allowExperimentalFeatures)
        }
        return "此功能尚无 \(service.manifest.gameBuild.version) 的完整目标证据。"
    }

    func profileSummary(for gameBuild: GameBuildSignature) -> String? {
        guard let service = matchingService(for: gameBuild) else {
            return nil
        }
        let supportedCount = service.manifest.features.count
        return "已匹配精确 profile：\(service.manifest.gameBuild.version)，已收录 \(supportedCount)/\(DaveTrainerFeatureID.allCases.count) 个功能的精确目标。"
    }

    private func matchingService(for build: GameBuildSignature) -> TrainerBuildOperationService? {
        profileServices.first { build.matchesIdentity(of: $0.manifest.gameBuild) }
    }

    private func experimentalReason(service: TrainerBuildOperationService, allowed: Bool) -> String? {
        guard service.manifest.gameBuild.matchesIdentity(of: KnownGameBuild.v106756), !allowed else {
            return nil
        }
        return "此版本功能尚待完整游戏实测。备份存档后，开启“启用 .756 实验功能”以继续。"
    }

    private func unsupportedBuildResult(
        featureID: DaveTrainerFeatureID,
        actual: GameBuildSignature
    ) -> DaveTrainerOperationResult {
        let supportedVersions = profileServices.map(\.manifest.gameBuild.version).joined(separator: ", ")
        return DaveTrainerOperationResult(
            featureID: featureID,
            state: .unsupportedBuild,
            targetIDs: [],
            message: "当前游戏构建 \(actual.version) / \(actual.buildGUID) 尚无精确 profile；已阻止玩家写入。已收录：\(supportedVersions)。请导出兼容报告。"
        )
    }

    private func unsupportedFeatureResult(
        featureID: DaveTrainerFeatureID,
        service: TrainerBuildOperationService
    ) -> DaveTrainerOperationResult {
        DaveTrainerOperationResult(
            featureID: featureID,
            state: .unsupportedBuild,
            targetIDs: [],
            message: "当前 \(service.manifest.gameBuild.version) profile 尚未验证功能 \(featureID.rawValue)；已阻止写入。可使用界面中未标记为不支持的功能，或继续导出兼容报告补充证据。"
        )
    }

    private static func hasUniqueBuildIdentities(_ services: [TrainerBuildOperationService]) -> Bool {
        for (index, service) in services.enumerated() {
            let remaining = services.dropFirst(index + 1)
            if remaining.contains(where: { $0.manifest.gameBuild.matchesIdentity(of: service.manifest.gameBuild) }) {
                return false
            }
        }
        return true
    }
}

private final class TrainerBuildOperationService {
    let manifest: DaveTrainerManifest
    let intentionallyUnsupportedFeatureIDs: Set<DaveTrainerFeatureID>

    private let staticPatches: [String: StaticGamePatch]
    private let valuePatchFactory: StaticValuePatchFactory
    private let applier: StaticPatchApplying
    private let runtimeQuantityIncrementer: RuntimeQuantityIncrementing
    private let ingredientsIncrementer: IngredientsInventoryIncrementing
    private let jungleIngredientsIncrementer: JungleIngredientsInventoryIncrementing
    private let transactionEngine: PatchTransactionEngine
    private var activeValuePatches: [String: StaticGamePatch] = [:]

    init(configuration: TrainerOperationService.Configuration) {
        self.manifest = configuration.manifest
        self.intentionallyUnsupportedFeatureIDs = configuration.intentionallyUnsupportedFeatureIDs
        self.staticPatches = configuration.staticPatches
        self.valuePatchFactory = configuration.valuePatchFactory
        self.applier = configuration.applier
        self.runtimeQuantityIncrementer = configuration.runtimeQuantityIncrementer
        self.ingredientsIncrementer = configuration.ingredientsIncrementer
        self.jungleIngredientsIncrementer = configuration.jungleIngredientsIncrementer
        self.transactionEngine = PatchTransactionEngine(applier: configuration.applier)
    }

    func clearRuntimeCaches() {
        runtimeQuantityIncrementer.clearCachedAddresses()
        ingredientsIncrementer.clearCachedAddresses()
        jungleIngredientsIncrementer.clearCachedAddresses()
        activeValuePatches.removeAll()
    }

    func apply(_ request: TrainerOperationRequest, context: TrainerOperationContext) throws -> DaveTrainerOperationResult {
        guard let feature = manifest.feature(id: request.featureID) else {
            return result(OperationResultDraft(
                featureID: request.featureID,
                state: .targetMismatch,
                targets: [],
                message: "manifest 缺少功能：\(request.featureID.rawValue)。"
            ))
        }

        guard !feature.targets.isEmpty else {
            return result(OperationResultDraft(
                featureID: request.featureID,
                state: .targetMismatch,
                targets: [],
                message: "manifest 功能缺少目标：\(request.featureID.rawValue)。"
            ))
        }

        return try applyValidated(request, context: context, feature: feature)
    }

    private func applyValidated(
        _ request: TrainerOperationRequest,
        context: TrainerOperationContext,
        feature: DaveTrainerManifestFeature
    ) throws -> DaveTrainerOperationResult {
        switch request.payload {
        case .staticPatch(let patchID):
            guard feature.kind == .codePatch else {
                return targetMismatchResult(featureID: request.featureID, message: "功能不是静态 patch：\(request.featureID.rawValue)。")
            }
            guard let mismatch = staticPatchTargetMismatch(patchIDs: [patchID], feature: feature) else {
                return applySinglePatch(patchID: patchID, request: request, context: context)
            }
            return mismatch
        case .staticPatchGroup(let patchIDs):
            guard feature.kind == .codePatch else {
                return targetMismatchResult(featureID: request.featureID, message: "功能不是静态 patch group：\(request.featureID.rawValue)。")
            }
            guard let mismatch = staticPatchTargetMismatch(patchIDs: patchIDs, feature: feature) else {
                return applyPatchGroup(patchIDs: patchIDs, request: request, context: context)
            }
            return mismatch
        case .valuePatch(let patchID, let valueText):
            guard feature.kind == .codePatch else {
                return targetMismatchResult(featureID: request.featureID, message: "功能不是静态 value patch：\(request.featureID.rawValue)。")
            }
            guard let mismatch = staticPatchTargetMismatch(patchIDs: [patchID], feature: feature) else {
                return try applyValuePatch(ValuePatchOperation(
                    patchID: patchID,
                    valueText: valueText,
                    request: request,
                    context: context
                ))
            }
            return mismatch
        case .runtimeQuantity(let resourceID, let valueText):
            return applyRuntimeQuantity(resourceID: resourceID, valueText: valueText, request: request, context: context, feature: feature)
        case .inventory(let scope, let valueText):
            return applyInventory(scope: scope, valueText: valueText, request: request, context: context, feature: feature)
        case .jungleInventory(let scope, let valueText):
            return applyJungleInventory(scope: scope, valueText: valueText, request: request, context: context, feature: feature)
        }
    }

    private func staticPatchTargetMismatch(
        patchIDs: [String],
        feature: DaveTrainerManifestFeature
    ) -> DaveTrainerOperationResult? {
        guard !patchIDs.isEmpty else {
            return targetMismatchResult(featureID: feature.id, message: "静态 patch 请求为空：\(feature.id.rawValue)。")
        }
        let allowedPatchIDs = Self.allowedStaticPatchIDs(for: feature)
        guard !allowedPatchIDs.isEmpty else {
            return targetMismatchResult(featureID: feature.id, message: "manifest 功能缺少静态 patch target：\(feature.id.rawValue)。")
        }
        let mismatchedPatchIDs = patchIDs.filter { !allowedPatchIDs.contains($0) }
        guard mismatchedPatchIDs.isEmpty else {
            return targetMismatchResult(
                featureID: feature.id,
                message: "请求 patch 不属于功能 \(feature.id.rawValue)：\(mismatchedPatchIDs.joined(separator: ", "))。"
            )
        }
        return nil
    }

    private static func allowedStaticPatchIDs(for feature: DaveTrainerManifestFeature) -> Set<String> {
        Set(feature.targets.compactMap(staticPatchID))
    }

    private static func staticPatchID(from target: DaveTrainerManifestTarget) -> String? {
        guard case .patchPoint(let patchPoint) = target else {
            return nil
        }
        return patchID(fromPatchPointID: patchPoint.id)
    }

    private static func patchID(fromPatchPointID patchPointID: String) -> String {
        guard let separatorIndex = patchPointID.lastIndex(of: ".") else {
            return patchPointID
        }
        let suffixIndex = patchPointID.index(after: separatorIndex)
        guard Int(patchPointID[suffixIndex...]) != nil else {
            return patchPointID
        }
        return String(patchPointID[..<separatorIndex])
    }

    private func applySinglePatch(
        patchID: String,
        request: TrainerOperationRequest,
        context: TrainerOperationContext
    ) -> DaveTrainerOperationResult {
        do {
            let patch = try requiredStaticPatch(id: patchID)
            return try transactionEngine.apply(PatchTransactionRequest(
                patches: [patch],
                isEnabled: request.isEnabled,
                featureID: request.featureID
            ), session: context.session)
        } catch {
            return failureResult(featureID: request.featureID, targets: [patchID], error: error)
        }
    }

    private func applyPatchGroup(
        patchIDs: [String],
        request: TrainerOperationRequest,
        context: TrainerOperationContext
    ) -> DaveTrainerOperationResult {
        do {
            let patches = try patchIDs.map(requiredStaticPatch)
            return try transactionEngine.apply(PatchTransactionRequest(
                patches: patches,
                isEnabled: request.isEnabled,
                featureID: request.featureID
            ), session: context.session)
        } catch {
            return failureResult(featureID: request.featureID, targets: patchIDs, error: error)
        }
    }

    private func applyValuePatch(_ operation: ValuePatchOperation) throws -> DaveTrainerOperationResult {
        let trimmedOperation = ValuePatchOperation(
            patchID: operation.patchID,
            valueText: operation.valueText.trimmingCharacters(in: .whitespacesAndNewlines),
            request: operation.request,
            context: operation.context
        )
        if operation.request.isEnabled {
            return try enableValuePatch(trimmedOperation)
        }
        return try disableValuePatch(trimmedOperation)
    }

    private func enableValuePatch(_ operation: ValuePatchOperation) throws -> DaveTrainerOperationResult {
        let patch = try valuePatchFactory(operation.patchID, operation.valueText)
        do {
            try restoreConflictingValuePatches(for: operation.patchID, session: operation.context.session)
            if let previousPatch = activeValuePatches[operation.patchID], previousPatch != patch {
                try applier.apply(StaticPatchApplyRequest(patch: previousPatch, isEnabled: false), session: operation.context.session)
            }
            try applier.apply(StaticPatchApplyRequest(patch: patch, isEnabled: true), session: operation.context.session)
            activeValuePatches[operation.patchID] = patch
            return result(OperationResultDraft(
                featureID: operation.request.featureID,
                state: .bytesApplied,
                targets: [patch.id],
                message: "已应用：\(patch.title) = \(operation.valueText)"
            ))
        } catch {
            return failureResult(featureID: operation.request.featureID, targets: [operation.patchID], error: error)
        }
    }

    private func disableValuePatch(_ operation: ValuePatchOperation) throws -> DaveTrainerOperationResult {
        let patch = try activeValuePatches[operation.patchID]
            ?? valuePatchFactory(operation.patchID, operation.valueText)
        do {
            try applier.apply(StaticPatchApplyRequest(patch: patch, isEnabled: false), session: operation.context.session)
            activeValuePatches[operation.patchID] = nil
            return result(OperationResultDraft(
                featureID: operation.request.featureID,
                state: .bytesApplied,
                targets: [patch.id],
                message: "已恢复：\(patch.title)"
            ))
        } catch {
            return failureResult(featureID: operation.request.featureID, targets: [operation.patchID], error: error)
        }
    }

    private func applyRuntimeQuantity(
        resourceID: DaveTrainerFeatureID,
        valueText: String,
        request: TrainerOperationRequest,
        context: TrainerOperationContext,
        feature: DaveTrainerManifestFeature
    ) -> DaveTrainerOperationResult {
        do {
            let capability = try resourceCapability(feature: feature, expectedID: resourceID.rawValue)
            guard request.featureID == resourceID else {
                throw TrainerError.targetMismatch("请求功能 \(request.featureID.rawValue) 与资源 \(resourceID.rawValue) 不一致。")
            }
            let delta = try Self.parseIncrementDelta(valueText)
            let incrementResult = try runtimeQuantityIncrementer.increment(
                RuntimeQuantityIncrementRequest(featureID: resourceID.rawValue, delta: delta),
                session: context.session
            )
            return resourceSuccessResult(
                featureID: request.featureID,
                capability: capability,
                message: "已验证调整 \(feature.title)：\(Self.formatDelta(delta))，更新 \(incrementResult.updatedAddressCount) 处运行时数量。"
            )
        } catch {
            return failureResult(featureID: request.featureID, targets: [resourceID.rawValue], error: error)
        }
    }

    private func applyInventory(
        scope: IngredientsInventoryScope,
        valueText: String,
        request: TrainerOperationRequest,
        context: TrainerOperationContext,
        feature: DaveTrainerManifestFeature
    ) -> DaveTrainerOperationResult {
        let expectedFeatureID = scope.daveTrainerFeatureID
        do {
            let capability = try resourceCapability(feature: feature, expectedID: expectedFeatureID.rawValue)
            guard request.featureID == expectedFeatureID else {
                throw TrainerError.targetMismatch("请求功能 \(request.featureID.rawValue) 与库存范围 \(expectedFeatureID.rawValue) 不一致。")
            }
            let delta = try Self.parseIncrementDelta(valueText)
            let incrementResult = try ingredientsIncrementer.increment(
                IngredientsInventoryIncrementRequest(scope: scope, delta: delta),
                session: context.session
            )
            return resourceSuccessResult(
                featureID: request.featureID,
                capability: capability,
                message: "已验证调整 \(feature.title)：\(Self.formatDelta(delta))，更新 \(incrementResult.updatedItemCount) 项。"
            )
        } catch {
            return failureResult(featureID: request.featureID, targets: [expectedFeatureID.rawValue], error: error)
        }
    }

    private func applyJungleInventory(
        scope: JungleDLCInventoryScope,
        valueText: String,
        request: TrainerOperationRequest,
        context: TrainerOperationContext,
        feature: DaveTrainerManifestFeature
    ) -> DaveTrainerOperationResult {
        let expectedFeatureID = scope.daveTrainerFeatureID
        do {
            let capability = try resourceCapability(feature: feature, expectedID: expectedFeatureID.rawValue)
            guard request.featureID == expectedFeatureID else {
                throw TrainerError.targetMismatch("请求功能 \(request.featureID.rawValue) 与丛林库存范围 \(expectedFeatureID.rawValue) 不一致。")
            }
            let delta = try Self.parseIncrementDelta(valueText)
            let incrementResult = try jungleIngredientsIncrementer.increment(
                JungleIngredientsInventoryIncrementRequest(delta: delta, scope: scope),
                session: context.session
            )
            return resourceSuccessResult(
                featureID: request.featureID,
                capability: capability,
                message: "已验证调整 \(feature.title)：\(Self.formatDelta(delta))，更新 \(incrementResult.updatedItemCount) 项。"
            )
        } catch {
            return failureResult(featureID: request.featureID, targets: [expectedFeatureID.rawValue], error: error)
        }
    }

    private func resourceCapability(feature: DaveTrainerManifestFeature, expectedID: String) throws -> DaveResourceCapability {
        guard feature.kind == .inventoryResource || feature.kind == .runtimeValue else {
            throw TrainerError.targetMismatch("功能不是资源 capability：\(feature.id.rawValue)。")
        }
        guard let capability = feature.targets.compactMap(Self.resourceCapabilityTarget).first else {
            throw TrainerError.targetMismatch("manifest 缺少资源 capability：\(feature.id.rawValue)。")
        }
        guard capability.id == expectedID else {
            throw TrainerError.targetMismatch("资源 capability 不匹配。期望 \(expectedID)，实际 \(capability.id)。")
        }
        return capability
    }

    private static func resourceCapabilityTarget(_ target: DaveTrainerManifestTarget) -> DaveResourceCapability? {
        if case .resourceCapability(let capability) = target {
            return capability
        }
        return nil
    }

    private func resourceSuccessResult(
        featureID: DaveTrainerFeatureID,
        capability: DaveResourceCapability,
        message: String
    ) -> DaveTrainerOperationResult {
        result(OperationResultDraft(
            featureID: featureID,
            state: .behaviorVerified,
            targets: [capability.id],
            message: message
        ))
    }

    private func restoreConflictingValuePatches(for patchID: String, session: MemorySession) throws {
        guard Self.inventoryValuePatchGroup.contains(patchID) else {
            return
        }

        for conflictingID in Self.inventoryValuePatchGroup where conflictingID != patchID && activeValuePatches[conflictingID] != nil {
            guard let activePatch = activeValuePatches[conflictingID] else {
                throw TrainerError.invalidInput("库存 patch 状态不一致：\(conflictingID) 已标记开启，但缺少可恢复的活动补丁。")
            }

            try applier.apply(StaticPatchApplyRequest(patch: activePatch, isEnabled: false), session: session)
            activeValuePatches[conflictingID] = nil
        }
    }

    private func requiredStaticPatch(id: String) throws -> StaticGamePatch {
        guard let patch = staticPatches[id] else {
            throw TrainerError.invalidInput("未知静态 patch：\(id)")
        }
        return patch
    }

    private func failureResult(
        featureID: DaveTrainerFeatureID,
        targets: [String],
        error: Error
    ) -> DaveTrainerOperationResult {
        let state: DaveTrainerOperationState
        if case TrainerError.targetMismatch = error {
            state = .targetMismatch
        } else if case TrainerError.verifyFailed = error {
            state = .verifyFailed
        } else {
            state = .writeFailed
        }

        return result(OperationResultDraft(
            featureID: featureID,
            state: state,
            targets: targets,
            message: error.localizedDescription
        ))
    }

    private func targetMismatchResult(featureID: DaveTrainerFeatureID, message: String) -> DaveTrainerOperationResult {
        result(OperationResultDraft(
            featureID: featureID,
            state: .targetMismatch,
            targets: [],
            message: message
        ))
    }

    private func result(_ draft: OperationResultDraft) -> DaveTrainerOperationResult {
        DaveTrainerOperationResult(
            featureID: draft.featureID,
            state: draft.state,
            targetIDs: draft.targets,
            message: draft.message
        )
    }

    private static func parseIncrementDelta(_ text: String) throws -> Int64 {
        let trimmedValue = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let delta = Int64(trimmedValue) else {
            throw TrainerError.invalidInput("调整数量必须是整数。")
        }
        return delta
    }

    private static func formatDelta(_ delta: Int64) -> String {
        delta >= 0 ? "+\(delta)" : String(delta)
    }

    private static let inventoryValuePatchGroup: Set<String> = [
        "materials",
        "fishIngredients",
        "vegetableIngredients",
        "seasoningIngredients",
        "upgradeMaterials"
    ]
}

private extension IngredientsInventoryScope {
    var daveTrainerFeatureID: DaveTrainerFeatureID {
        switch self {
        case .all:
            return .ingredients
        case .fish:
            return .fishIngredients
        case .vegetable:
            return .vegetableIngredients
        case .seasoning:
            return .seasoningIngredients
        case .upgrade:
            return .upgradeMaterials
        }
    }
}

private extension JungleDLCInventoryScope {
    var daveTrainerFeatureID: DaveTrainerFeatureID {
        switch self {
        case .ingredientsAndVillageItems, .ingredients:
            return .jungleIngredients
        case .villageItems:
            return .seaPeopleVillageItems
        }
    }
}
