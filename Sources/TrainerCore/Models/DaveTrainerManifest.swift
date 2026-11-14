import Foundation

public enum DaveTrainerFeatureID: String, CaseIterable, Codable, Sendable {
    case divingGod
    case god
    case oxygen
    case ammo
    case crabTraps
    case weight
    case swimSpeed
    case damage
    case drones
    case gold
    case bei
    case jungleGold
    case ingredients
    case jungleIngredients
    case seaPeopleVillageItems
    case fishIngredients
    case vegetableIngredients
    case seasoningIngredients
    case upgradeMaterials
    case stamina
    case wasabi
    case artisan
}

public enum DaveTrainerFeatureKind: String, Codable, Sendable {
    case codePatch
    case runtimeValue
    case inventoryResource
    case diagnostic
}

public enum DaveTrainerFailureMode: String, Codable, Sendable {
    case failLoud = "fail-loud"
}

public struct DaveTrainerPlayerRuntimePolicy: Equatable, Codable, Sendable {
    public let allowRuntimeScanning: Bool
    public let failureMode: DaveTrainerFailureMode
    public let requiresBuildMatch: Bool

    public init(
        allowRuntimeScanning: Bool,
        failureMode: DaveTrainerFailureMode,
        requiresBuildMatch: Bool
    ) {
        self.allowRuntimeScanning = allowRuntimeScanning
        self.failureMode = failureMode
        self.requiresBuildMatch = requiresBuildMatch
    }

    public static let playerManifestOnly = DaveTrainerPlayerRuntimePolicy(
        allowRuntimeScanning: false,
        failureMode: .failLoud,
        requiresBuildMatch: true
    )
}

public struct DaveManifestPatchPoint: Equatable, Codable, Sendable {
    public let id: String
    public let moduleID: String
    public let rva: UInt64
    public let expectedBytes: [UInt8]
    public let patchBytes: [UInt8]
    public let restoreBytes: [UInt8]
    public let usesTrampoline: Bool
    public let note: String

    public init(id: String, moduleID: String, point: StaticPatchPoint) {
        self.id = id
        self.moduleID = moduleID
        self.rva = point.rva
        self.expectedBytes = point.expectedBytes
        self.patchBytes = point.patchBytes
        self.restoreBytes = point.expectedBytes
        self.usesTrampoline = point.trampoline != nil
        self.note = point.note
    }
}

public struct DaveResourceCapability: Equatable, Codable, Sendable {
    public let id: String
    public let resourceKind: String
    public let runtimePlane: String
    public let savePlane: String
    public let canCreateEntries: Bool
    public let modifiesExistingEntries: Bool

    public init(
        id: String,
        resourceKind: String,
        runtimePlane: String,
        savePlane: String,
        canCreateEntries: Bool,
        modifiesExistingEntries: Bool
    ) {
        self.id = id
        self.resourceKind = resourceKind
        self.runtimePlane = runtimePlane
        self.savePlane = savePlane
        self.canCreateEntries = canCreateEntries
        self.modifiesExistingEntries = modifiesExistingEntries
    }
}

public struct DaveModuleIdentity: Equatable, Codable, Sendable {
    public let id: String
    public let moduleName: String
    public let architecture: String
    public let machoUUID: String?
    public let pathMatchPolicy: String

    public init(
        id: String,
        moduleName: String,
        architecture: String,
        machoUUID: String?,
        pathMatchPolicy: String
    ) {
        self.id = id
        self.moduleName = moduleName
        self.architecture = architecture
        self.machoUUID = machoUUID
        self.pathMatchPolicy = pathMatchPolicy
    }
}

public enum DaveTrainerManifestTarget: Equatable, Codable, Sendable {
    case patchPoint(DaveManifestPatchPoint)
    case resourceCapability(DaveResourceCapability)
}

public struct DaveTrainerManifestFeature: Equatable, Codable, Sendable {
    public let id: DaveTrainerFeatureID
    public let title: String
    public let kind: DaveTrainerFeatureKind
    public let targets: [DaveTrainerManifestTarget]
    public let playerRuntimePolicy: DaveTrainerPlayerRuntimePolicy

    public init(
        id: DaveTrainerFeatureID,
        title: String,
        kind: DaveTrainerFeatureKind,
        targets: [DaveTrainerManifestTarget],
        playerRuntimePolicy: DaveTrainerPlayerRuntimePolicy = .playerManifestOnly
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.targets = targets
        self.playerRuntimePolicy = playerRuntimePolicy
    }
}

public struct DaveTrainerManifest: Equatable, Codable, Sendable {
    public static let currentSchemaVersion = "1.0"
    public static let gameAssemblyModuleID = "gameAssembly"

    public let schemaVersion: String
    public let gameBuild: GameBuildSignature
    public let moduleIdentities: [DaveModuleIdentity]
    public let features: [DaveTrainerManifestFeature]

    public init(
        schemaVersion: String,
        gameBuild: GameBuildSignature,
        moduleIdentities: [DaveModuleIdentity] = [],
        features: [DaveTrainerManifestFeature]
    ) {
        self.schemaVersion = schemaVersion
        self.gameBuild = gameBuild
        self.moduleIdentities = moduleIdentities
        self.features = features
    }

    public func feature(id: DaveTrainerFeatureID) -> DaveTrainerManifestFeature? {
        features.first { $0.id == id }
    }

    public func moduleIdentity(id: String) -> DaveModuleIdentity? {
        moduleIdentities.first { $0.id == id }
    }

    public static let current = DaveTrainerManifest(
        schemaVersion: currentSchemaVersion,
        gameBuild: KnownGameBuild.current,
        moduleIdentities: [
            DaveModuleIdentity(
                id: gameAssemblyModuleID,
                moduleName: "GameAssembly.dylib",
                architecture: "arm64",
                machoUUID: "7BA6FD17-58B4-31CC-A621-45EE26D462F9",
                pathMatchPolicy: "image-name"
            )
        ],
        features: DaveTrainerManifestFactory.makeCurrentFeatures()
    )

    public static let v106710 = DaveTrainerManifest(
        schemaVersion: currentSchemaVersion,
        gameBuild: KnownGameBuild.v106710,
        moduleIdentities: [
            DaveModuleIdentity(
                id: gameAssemblyModuleID,
                moduleName: "GameAssembly.dylib",
                architecture: "arm64",
                machoUUID: "266578BA-B451-313B-8326-CF241BB3FA5F",
                pathMatchPolicy: "image-name"
            )
        ],
        features: DaveTrainerManifestFactory.makeV106710Features()
    )

    public static let v106756 = DaveTrainerManifest(
        schemaVersion: currentSchemaVersion,
        gameBuild: KnownGameBuild.v106756,
        moduleIdentities: [
            DaveModuleIdentity(
                id: gameAssemblyModuleID,
                moduleName: "GameAssembly.dylib",
                architecture: "arm64",
                machoUUID: "698AB592-0DAA-3787-9B22-43683C35F62B",
                pathMatchPolicy: "image-name"
            )
        ],
        features: DaveTrainerManifestFactory.makeV106756Features()
    )
}

private enum DaveTrainerManifestFactory {
    static func makeCurrentFeatures() -> [DaveTrainerManifestFeature] {
        makeFullFeatures(
            patches: DefaultStaticGamePatches.make(),
            speedPatch: valuePatch(id: "swimSpeed", valueText: "5")
        )
    }

    private static func makeFullFeatures(patches catalog: [StaticGamePatch], speedPatch: StaticGamePatch) -> [DaveTrainerManifestFeature] {
        let staticPatches = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        return [
            codeFeature(.divingGod, title: "God 模式（Diving 全开）", patches: patches(["god", "oxygen", "ammo", "crabTraps", "weight", "damage", "drones"], in: staticPatches)),
            codeFeature(.god, title: "无敌/忽略伤害", patchID: "god", in: staticPatches),
            codeFeature(.oxygen, title: "无限氧气", patchID: "oxygen", in: staticPatches),
            codeFeature(.ammo, title: "无限弹药/鱼叉资源", patchID: "ammo", in: staticPatches),
            codeFeature(.crabTraps, title: "无限鱼笼", patchID: "crabTraps", in: staticPatches),
            codeFeature(.weight, title: "无限负重", patchID: "weight", in: staticPatches),
            codeFeature(.swimSpeed, title: "设置玩家移动速度", patch: speedPatch),
            codeFeature(.damage, title: "超级伤害/一击必杀", patchID: "damage", in: staticPatches),
            codeFeature(.drones, title: "无限无人机", patchID: "drones", in: staticPatches),
            resourceFeature(.gold, title: "增加金币", capability: currencyCapability(id: "gold", kind: "main-gold", runtime: "PlayerInfoSave.m_Gold", save: "SaveData.playerInfo.m_Gold")),
            resourceFeature(.bei, title: "增加鲛人族贝壳", capability: currencyCapability(id: "bei", kind: "sea-people-bei", runtime: "PlayerInfoSave.m_Bei", save: "SaveData.playerInfo.m_Bei")),
            resourceFeature(.jungleGold, title: "增加丛林货币", capability: currencyCapability(id: "jungleGold", kind: "jungle-gold", runtime: "SaveDataJungle.currencyHolder.jungleGold", save: "SaveDataJungle.currencyHolder.jungleGold")),
            resourceFeature(.ingredients, title: "增加主线全部食材/素材", capability: ingredientsCapability(id: "ingredients", kind: "main-all")),
            resourceFeature(.jungleIngredients, title: "增加丛林DLC食材/素材（已有）", capability: DaveResourceCapability(id: "jungleIngredients", resourceKind: "jungle-existing", runtimePlane: "SaveDataJungle.JungleIngredientsSave", savePlane: "SaveDataJungle.JungleVilInven", canCreateEntries: false, modifiesExistingEntries: true)),
            resourceFeature(.seaPeopleVillageItems, title: "增加鲛人村/丛林村庄物品（已有）", capability: DaveResourceCapability(id: "seaPeopleVillageItems", resourceKind: "sea-people-village-existing", runtimePlane: "SaveDataJungle.IvenData", savePlane: "SaveDataJungle.IvenData", canCreateEntries: false, modifiesExistingEntries: true)),
            resourceFeature(.fishIngredients, title: "按鱼肉食材分类增加", capability: ingredientsCapability(id: "fishIngredients", kind: "main-fish")),
            resourceFeature(.vegetableIngredients, title: "按蔬菜食材分类增加", capability: ingredientsCapability(id: "vegetableIngredients", kind: "main-vegetable")),
            resourceFeature(.seasoningIngredients, title: "按调味品分类增加", capability: ingredientsCapability(id: "seasoningIngredients", kind: "main-seasoning")),
            resourceFeature(.upgradeMaterials, title: "按强化素材分类增加", capability: ingredientsCapability(id: "upgradeMaterials", kind: "main-upgrade")),
            codeFeature(.stamina, title: "无限体力", patchID: "stamina", in: staticPatches),
            codeFeature(.wasabi, title: "无限芥末", patchID: "wasabi", in: staticPatches),
            resourceFeature(.artisan, title: "增加主线/丛林匠人火焰", capability: DaveResourceCapability(id: "artisan", resourceKind: "chef-flame", runtimePlane: "PlayerInfoSave.m_ChefFlame + SaveDataJungle.currencyHolder.jungleChefFlame", savePlane: "SaveData player and jungle save", canCreateEntries: false, modifiesExistingEntries: true))
        ]
    }

    static func makeV106710Features() -> [DaveTrainerManifestFeature] {
        let staticPatches = Dictionary(
            uniqueKeysWithValues: DaveV106710StaticGamePatches.make().map { ($0.id, $0) }
        )
        return [
            codeFeature(.god, title: "无敌/忽略伤害", patchID: "god", in: staticPatches),
            codeFeature(.oxygen, title: "无限氧气", patchID: "oxygen", in: staticPatches),
            codeFeature(.ammo, title: "无限弹药/鱼叉资源", patchID: "ammo", in: staticPatches),
            codeFeature(.crabTraps, title: "无限鱼笼", patchID: "crabTraps", in: staticPatches),
            codeFeature(.weight, title: "无限负重", patchID: "weight", in: staticPatches),
            codeFeature(
                .swimSpeed,
                title: "设置玩家移动速度",
                patch: v106710ValuePatch(id: "swimSpeed", valueText: "5")
            ),
            codeFeature(.drones, title: "无限无人机", patchID: "drones", in: staticPatches),
            codeFeature(.stamina, title: "无限体力", patchID: "stamina", in: staticPatches),
            codeFeature(.wasabi, title: "无限芥末", patchID: "wasabi", in: staticPatches)
        ]
    }

    static func makeV106756Features() -> [DaveTrainerManifestFeature] {
        makeFullFeatures(
            patches: DaveV106756StaticGamePatches.make(),
            speedPatch: v106756ValuePatch(id: "swimSpeed", valueText: "5")
        )
    }

    private static func codeFeature(_ id: DaveTrainerFeatureID, title: String, patchID: String, in patchesByID: [String: StaticGamePatch]) -> DaveTrainerManifestFeature {
        codeFeature(id, title: title, patch: requiredPatch(id: patchID, in: patchesByID))
    }

    private static func codeFeature(_ id: DaveTrainerFeatureID, title: String, patch: StaticGamePatch) -> DaveTrainerManifestFeature {
        codeFeature(id, title: title, patches: [patch])
    }

    private static func codeFeature(_ id: DaveTrainerFeatureID, title: String, patches: [StaticGamePatch]) -> DaveTrainerManifestFeature {
        let targets = patches.flatMap { patch in
            patch.points.enumerated().map { index, point in
                DaveTrainerManifestTarget.patchPoint(DaveManifestPatchPoint(
                    id: point.resolvedTargetID(patchID: patch.id, fallbackIndex: index),
                    moduleID: DaveTrainerManifest.gameAssemblyModuleID,
                    point: point
                ))
            }
        }
        return DaveTrainerManifestFeature(id: id, title: title, kind: .codePatch, targets: targets)
    }

    private static func resourceFeature(_ id: DaveTrainerFeatureID, title: String, capability: DaveResourceCapability) -> DaveTrainerManifestFeature {
        DaveTrainerManifestFeature(id: id, title: title, kind: .inventoryResource, targets: [.resourceCapability(capability)])
    }

    private static func patches(_ ids: [String], in patchesByID: [String: StaticGamePatch]) -> [StaticGamePatch] {
        ids.map { requiredPatch(id: $0, in: patchesByID) }
    }

    private static func valuePatch(id: String, valueText: String) -> StaticGamePatch {
        do {
            return try DefaultStaticGamePatches.makeValuePatch(id: id, valueText: valueText)
        } catch {
            preconditionFailure("Invalid Dave value patch \(id): \(error.localizedDescription)")
        }
    }

    private static func v106710ValuePatch(id: String, valueText: String) -> StaticGamePatch {
        do {
            return try DaveV106710StaticGamePatches.makeValuePatch(id: id, valueText: valueText)
        } catch {
            preconditionFailure("Invalid v1.0.6.710 value patch \(id): \(error.localizedDescription)")
        }
    }

    private static func v106756ValuePatch(id: String, valueText: String) -> StaticGamePatch {
        do {
            return try DaveV106756StaticGamePatches.makeValuePatch(id: id, valueText: valueText)
        } catch {
            preconditionFailure("Invalid v1.0.6.756 value patch \(id): \(error.localizedDescription)")
        }
    }

    private static func requiredPatch(id: String, in patchesByID: [String: StaticGamePatch]) -> StaticGamePatch {
        guard let patch = patchesByID[id] else {
            preconditionFailure("Missing Dave static patch: \(id)")
        }
        return patch
    }

    private static func currencyCapability(id: String, kind: String, runtime: String, save: String) -> DaveResourceCapability {
        DaveResourceCapability(id: id, resourceKind: kind, runtimePlane: runtime, savePlane: save, canCreateEntries: false, modifiesExistingEntries: true)
    }

    private static func ingredientsCapability(id: String, kind: String) -> DaveResourceCapability {
        DaveResourceCapability(id: id, resourceKind: kind, runtimePlane: "IngredientsStorage.IngredientsData.counts[0]", savePlane: "SaveData.Ingredients.IngredientsSave.Count", canCreateEntries: false, modifiesExistingEntries: true)
    }
}
