import Foundation

public enum DaveV106756StaticGamePatches {
    private struct VerifiedPoint {
        let targetID: String
        let rva: UInt64
        let expectedBytes: [UInt8]?
        let patchBytes: [UInt8]?
        let trampoline: StaticPatchTrampoline?

        init(
            targetID: String,
            rva: UInt64,
            expectedBytes: [UInt8]? = nil,
            patchBytes: [UInt8]? = nil,
            trampoline: StaticPatchTrampoline? = nil
        ) {
            self.targetID = targetID
            self.rva = rva
            self.expectedBytes = expectedBytes
            self.patchBytes = patchBytes
            self.trampoline = trampoline
        }
    }

    private static let supportedPatchIDs = [
        "god",
        "oxygen",
        "ammo",
        "crabTraps",
        "weight",
        "damage",
        "drones",
        "stamina",
        "wasabi"
    ]

    // Verified against the local v1.0.6.756 arm64 image; see docs/compatibility-v1.0.6.756.mac.md.
    private static let staticVerifiedPoints = [
        VerifiedPoint(targetID: "god.0", rva: 0xB86670),
        VerifiedPoint(targetID: "god.1", rva: 0xB868FC),
        VerifiedPoint(targetID: "god.2", rva: 0xB82F60),
        VerifiedPoint(targetID: "god.3", rva: 0xB7A8FC),
        VerifiedPoint(targetID: "god.4", rva: 0x1BC9E40),
        VerifiedPoint(targetID: "god.5", rva: 0x1BC62F8),
        VerifiedPoint(targetID: "god.6", rva: 0x1BC6318),
        // x20 addresses the player insect; x19 addresses the enemy insect.
        VerifiedPoint(targetID: "god.7", rva: 0xDF38E0, expectedBytes: [0x01, 0x3D, 0x40, 0xB9]),
        VerifiedPoint(targetID: "god.8", rva: 0xDF3BBC, expectedBytes: [0xE1, 0x03, 0x00, 0xAA]),
        VerifiedPoint(targetID: "god.9", rva: 0x1959940, expectedBytes: [0xE0, 0x0C, 0x00, 0xB4], trampoline: rpgTrampoline(kind: .rpgDamagePolicyIgnoreDamage)),
        VerifiedPoint(targetID: "oxygen.0", rva: 0x14158D8),
        VerifiedPoint(targetID: "oxygen.1", rva: 0x1418594),
        VerifiedPoint(targetID: "oxygen.2", rva: 0x1BC023C),
        VerifiedPoint(targetID: "oxygen.3", rva: 0x1BC9AE4),
        VerifiedPoint(targetID: "ammo.0", rva: 0xB8DC70),
        VerifiedPoint(targetID: "ammo.1", rva: 0xB89268),
        VerifiedPoint(targetID: "ammo.2", rva: 0x1BBB530),
        VerifiedPoint(targetID: "ammo.3", rva: 0x1BBB5F8),
        VerifiedPoint(targetID: "ammo.4", rva: 0x1BAED24),
        VerifiedPoint(targetID: "ammo.5", rva: 0x1BADFC4),
        VerifiedPoint(targetID: "ammo.6", rva: 0x1BAEAC8),
        VerifiedPoint(targetID: "ammo.7", rva: 0x1BAF57C),
        VerifiedPoint(targetID: "ammo.8", rva: 0x1BAE4DC),
        VerifiedPoint(targetID: "ammo.9", rva: 0x1BAE70C),
        VerifiedPoint(targetID: "ammo.10", rva: 0x13E3C88),
        VerifiedPoint(targetID: "ammo.11", rva: 0x13E36A4),
        VerifiedPoint(targetID: "ammo.12", rva: 0x13E3744),
        VerifiedPoint(targetID: "ammo.13", rva: 0x1374B10),
        VerifiedPoint(targetID: "ammo.14", rva: 0x1D95AD8),
        VerifiedPoint(targetID: "ammo.15", rva: 0x13F1978),
        VerifiedPoint(targetID: "ammo.16", rva: 0x13F7314),
        VerifiedPoint(targetID: "ammo.17", rva: 0x13F73C8),
        VerifiedPoint(targetID: "ammo.18", rva: 0x13FB560),
        VerifiedPoint(targetID: "ammo.19", rva: 0x13FBB98),
        VerifiedPoint(targetID: "ammo.20", rva: 0x13FBC24),
        VerifiedPoint(targetID: "crabTraps.0", rva: 0x1457588),
        VerifiedPoint(targetID: "crabTraps.1", rva: 0x1457590),
        VerifiedPoint(targetID: "crabTraps.2", rva: 0xB7B158),
        VerifiedPoint(targetID: "crabTraps.3", rva: 0xB7B160),
        VerifiedPoint(targetID: "crabTraps.4", rva: 0xB7B168),
        VerifiedPoint(targetID: "crabTraps.5", rva: 0x148E980),
        VerifiedPoint(targetID: "crabTraps.6", rva: 0x148E988),
        VerifiedPoint(targetID: "weight.0", rva: 0x1E1FB70),
        VerifiedPoint(targetID: "weight.1", rva: 0x1E1FB80),
        VerifiedPoint(targetID: "weight.2", rva: 0x1E1FB88),
        VerifiedPoint(targetID: "weight.3", rva: 0x1490610),
        VerifiedPoint(targetID: "weight.4", rva: 0x1490618),
        VerifiedPoint(targetID: "weight.5", rva: 0x1F35FF4),
        VerifiedPoint(targetID: "weight.6", rva: 0x1F35FEC),
        VerifiedPoint(targetID: "weight.7", rva: 0x1F362EC),
        VerifiedPoint(targetID: "weight.8", rva: 0x1F36334),
        VerifiedPoint(targetID: "weight.9", rva: 0x1F35D80),
        VerifiedPoint(targetID: "weight.10", rva: 0x1F36344),
        VerifiedPoint(targetID: "weight.11", rva: 0x1F37E60),
        VerifiedPoint(targetID: "weight.12", rva: 0x1F385EC),
        VerifiedPoint(
            targetID: "weight.13",
            rva: 0x210BBAC,
            expectedBytes: [
                0xF4, 0x4F, 0xBE, 0xA9,
                0xFD, 0x7B, 0x01, 0xA9,
                0xFD, 0x43, 0x00, 0x91,
                0x13, 0xE6, 0x03, 0xD0
            ]
        ),
        VerifiedPoint(targetID: "damage.3", rva: 0x1E2FBA8, expectedBytes: [0xE0, 0x03, 0x13, 0xAA, 0xEF, 0xF8, 0xFF, 0x97, 0xF5, 0x03, 0x00, 0xAA], patchBytes: (try! Arm64ReturnCode.moveInt32ToW21(999_999)) + [0x1F, 0x20, 0x03, 0xD5]),
        VerifiedPoint(targetID: "damage.4", rva: 0x13A4834, expectedBytes: [0xE0, 0x03, 0x14, 0xAA, 0x01, 0x00, 0x80, 0xD2, 0x71, 0x90, 0x24, 0x94]),
        VerifiedPoint(targetID: "damage.5", rva: 0x13A4904, expectedBytes: [0xE0, 0x03, 0x14, 0xAA, 0x01, 0x00, 0x80, 0xD2, 0x3D, 0x90, 0x24, 0x94, 0xF4, 0x03, 0x00, 0xAA]),
        VerifiedPoint(targetID: "damage.6", rva: 0x13B5A58, expectedBytes: [0xE0, 0x03, 0x15, 0xAA, 0x01, 0x00, 0x80, 0xD2, 0xE8, 0x4B, 0x24, 0x94, 0xF4, 0x03, 0x00, 0xAA]),
        VerifiedPoint(targetID: "damage.7", rva: 0x14A0860, expectedBytes: [0xE0, 0x03, 0x14, 0xAA, 0x01, 0x00, 0x80, 0xD2, 0x66, 0xA0, 0x20, 0x94]),
        VerifiedPoint(targetID: "damage.8", rva: 0x152BE14, expectedBytes: [0x80, 0x42, 0x00, 0x91, 0x01, 0x00, 0x80, 0xD2, 0xF9, 0x72, 0x1E, 0x94, 0xF6, 0x03, 0x00, 0xAA]),
        VerifiedPoint(targetID: "damage.9", rva: 0x15E75C0, expectedBytes: [0xE0, 0x03, 0x15, 0xAA, 0x01, 0x00, 0x80, 0xD2, 0x0E, 0x85, 0x1B, 0x94]),
        VerifiedPoint(targetID: "damage.10", rva: 0x17188B0, expectedBytes: [0xE0, 0x03, 0x01, 0xAA, 0x01, 0x00, 0x80, 0xD2, 0x52, 0xC0, 0x16, 0x94]),
        VerifiedPoint(targetID: "damage.11", rva: 0x1718908, expectedBytes: [0xE0, 0x03, 0x14, 0xAA, 0x01, 0x00, 0x80, 0xD2, 0x3C, 0xC0, 0x16, 0x94]),
        VerifiedPoint(targetID: "damage.12", rva: 0x1728170, expectedBytes: [0xE0, 0x03, 0x01, 0xAA, 0x01, 0x00, 0x80, 0xD2, 0x22, 0x82, 0x16, 0x94, 0xF4, 0x03, 0x00, 0xAA]),
        VerifiedPoint(targetID: "damage.13", rva: 0x1CC7FE4, expectedBytes: [0xE0, 0x03, 0x13, 0xAA, 0x86, 0x02, 0x00, 0x94]),
        VerifiedPoint(targetID: "damage.14", rva: 0x1CC8068, expectedBytes: [0xE0, 0x03, 0x13, 0xAA, 0x65, 0x02, 0x00, 0x94]),
        VerifiedPoint(targetID: "damage.15", rva: 0x1CDAD58, expectedBytes: [0xE0, 0x03, 0x00, 0x91, 0x01, 0x00, 0x80, 0xD2, 0x28, 0xB7, 0xFF, 0x97, 0xE1, 0x03, 0x00, 0xAA]),
        VerifiedPoint(targetID: "damage.16", rva: 0x1E4E280, expectedBytes: [0xE0, 0x03, 0x14, 0xAA, 0x01, 0x00, 0x80, 0xD2, 0xDE, 0xE9, 0xF9, 0x97]),
        VerifiedPoint(targetID: "damage.17", rva: 0x1F883A8, expectedBytes: [0xE0, 0x03, 0x14, 0xAA, 0x01, 0x00, 0x80, 0xD2, 0x94, 0x01, 0xF5, 0x97]),
        VerifiedPoint(targetID: "damage.18", rva: 0x1F884DC, expectedBytes: [0xE0, 0x03, 0x14, 0xAA, 0x01, 0x00, 0x80, 0xD2, 0x47, 0x01, 0xF5, 0x97]),
        VerifiedPoint(targetID: "damage.19", rva: 0x1F8877C, expectedBytes: [0xE0, 0x03, 0x14, 0xAA, 0x01, 0x00, 0x80, 0xD2, 0x9F, 0x00, 0xF5, 0x97, 0xF4, 0x03, 0x00, 0xAA]),
        VerifiedPoint(targetID: "damage.20", rva: 0xDF3940, expectedBytes: [0x01, 0x3D, 0x40, 0xB9, 0x02, 0x00, 0x80, 0xD2]),
        VerifiedPoint(targetID: "damage.21", rva: 0xDF39EC, expectedBytes: [0x5F, 0x03, 0x00, 0x71, 0x41, 0x57, 0x9A, 0x5A]),
        VerifiedPoint(targetID: "damage.22", rva: 0xDF3AB4, expectedBytes: [0x5F, 0x03, 0x00, 0x71, 0x41, 0x57, 0x9A, 0x5A]),
        VerifiedPoint(targetID: "damage.23", rva: 0x1959940, expectedBytes: [0xE0, 0x0C, 0x00, 0xB4], trampoline: rpgTrampoline(kind: .rpgDamagePolicySuperDamage)),
        VerifiedPoint(targetID: "drones.0", rva: 0xB7B138),
        VerifiedPoint(targetID: "drones.1", rva: 0x1D962AC),
        VerifiedPoint(targetID: "drones.2", rva: 0xB7B140),
        VerifiedPoint(targetID: "drones.3", rva: 0xB7B148),
        VerifiedPoint(targetID: "stamina.0", rva: 0x1029FCC),
        VerifiedPoint(targetID: "stamina.1", rva: 0x1029FD4),
        VerifiedPoint(targetID: "stamina.2", rva: 0x1029C90),
        VerifiedPoint(targetID: "stamina.3", rva: 0x102A324),
        VerifiedPoint(
            targetID: "wasabi.0",
            rva: 0x21D4F50,
            expectedBytes: [
                0xFD, 0x7B, 0xBF, 0xA9,
                0xFD, 0x03, 0x00, 0x91,
                0x08, 0x08, 0x40, 0xF9,
                0x48, 0x01, 0x00, 0xB4,
                0x09, 0x19, 0x40, 0xB9,
                0x3F, 0x00, 0x09, 0x6B,
                0x02, 0x01, 0x00, 0x54,
                0x08, 0xCD, 0x21, 0x8B,
                0x08, 0x11, 0x40, 0xF9,
                0x88, 0x00, 0x00, 0xB4,
                0x00, 0x11, 0x40, 0xB9,
                0xFD, 0x7B, 0xC1, 0xA8,
                0xC0, 0x03, 0x5F, 0xD6
            ]
        ),
        VerifiedPoint(targetID: "wasabi.1", rva: 0x21D52A0),
        VerifiedPoint(targetID: "wasabi.2", rva: 0x21D5168),
        VerifiedPoint(targetID: "wasabi.3", rva: 0x21D4A10),
        VerifiedPoint(targetID: "wasabi.4", rva: 0x21D4D24)
    ]

    // The farm and village literal/branch distances are unchanged: +12/+16 and +12.
    // Their exact encodings are covered by DaveV106756ProfileTests.
    private static let swimSpeedVerifiedPoints = [
        VerifiedPoint(targetID: "swimSpeed.0", rva: 0x210BDFC),
        VerifiedPoint(targetID: "swimSpeed.1", rva: 0xB81BC8),
        VerifiedPoint(targetID: "swimSpeed.2", rva: 0x1029FDC),
        VerifiedPoint(targetID: "swimSpeed.3", rva: 0xFDE3B0),
        VerifiedPoint(targetID: "swimSpeed.4", rva: 0xF7FB70),
        VerifiedPoint(targetID: "swimSpeed.5", rva: 0xF7EAC8),
        VerifiedPoint(targetID: "swimSpeed.6", rva: 0xF7EAD0),
        VerifiedPoint(targetID: "swimSpeed.7", rva: 0x1800730),
        VerifiedPoint(targetID: "swimSpeed.8", rva: 0x17F5FD4),
        VerifiedPoint(targetID: "swimSpeed.9", rva: 0x116F610),
        VerifiedPoint(targetID: "swimSpeed.10", rva: 0x1178B3C)
    ]

    public static func make() -> [StaticGamePatch] {
        let baselinePatches = Dictionary(
            uniqueKeysWithValues: DefaultStaticGamePatches.make().map { ($0.id, $0) }
        )
        let evidenceByID = Dictionary(uniqueKeysWithValues: staticVerifiedPoints.map { ($0.targetID, $0) })
        let patches = supportedPatchIDs.map { patchID in
            guard let baseline = baselinePatches[patchID] else {
                preconditionFailure("Missing baseline patch: \(patchID)")
            }
            return relocatedPatch(baseline, evidenceByID: evidenceByID)
        }
        let pointCount = patches.reduce(0) { $0 + $1.points.count }
        precondition(pointCount == evidenceByID.count, "Unconsumed v1.0.6.756 patch evidence")
        return patches
    }

    public static func makeValuePatch(id: String, valueText: String) throws -> StaticGamePatch {
        guard id == "swimSpeed" else {
            throw TrainerError.invalidInput("v1.0.6.756 尚未验证固定数值 patch：\(id)")
        }
        let baseline = try DefaultStaticGamePatches.makeValuePatch(id: id, valueText: valueText)
        let evidenceByID = Dictionary(
            uniqueKeysWithValues: swimSpeedVerifiedPoints.map { ($0.targetID, $0) }
        )
        let patch = relocatedPatch(baseline, evidenceByID: evidenceByID)
        precondition(patch.points.count == evidenceByID.count, "Unconsumed v1.0.6.756 value patch evidence")
        return patch
    }

    private static func rpgTrampoline(kind: StaticPatchTrampolineKind) -> StaticPatchTrampoline {
        // DealDamage retains x20 = target, w21 = damage, x0 = health at this hook.
        // BattleUtils.IsEnemy keeps player and enemy damage policies independent.
        StaticPatchTrampoline(
            kind: kind,
            value: 999_999,
            resumeRVA: 0x1959944,
            nullHandlerRVA: 0x1959ADC,
            helperRVA: 0x195F3B0,
            codeCaveRVA: 0x940,
            codeCaveExpectedBytes: Array(repeating: 0, count: 72)
        )
    }

    private static func relocatedPatch(
        _ baseline: StaticGamePatch,
        evidenceByID: [String: VerifiedPoint]
    ) -> StaticGamePatch {
        let points: [StaticPatchPoint] = baseline.points.enumerated().compactMap { index, point -> StaticPatchPoint? in
            let targetID = point.resolvedTargetID(patchID: baseline.id, fallbackIndex: index)
            guard let evidence = evidenceByID[targetID] else {
                return nil
            }
            precondition(point.trampoline == nil || evidence.trampoline != nil, "Unverified trampoline in v1.0.6.756 profile: \(targetID)")
            return relocatedPoint(point, evidence: evidence)
        }
        precondition(!points.isEmpty, "v1.0.6.756 patch has no verified points: \(baseline.id)")
        return StaticGamePatch(id: baseline.id, title: baseline.title, points: points)
    }

    private static func relocatedPoint(
        _ baseline: StaticPatchPoint,
        evidence: VerifiedPoint
    ) -> StaticPatchPoint {
        StaticPatchPoint(
            rva: evidence.rva,
            expectedBytes: evidence.expectedBytes ?? baseline.expectedBytes,
            patchBytes: evidence.patchBytes ?? baseline.patchBytes,
            note: baseline.note,
            acceptsLegacyIntReturnPatch: baseline.acceptsLegacyIntReturnPatch,
            acceptsCompatibleAppliedPatch: baseline.acceptsCompatibleAppliedPatch,
            trampoline: evidence.trampoline,
            targetID: evidence.targetID
        )
    }
}
