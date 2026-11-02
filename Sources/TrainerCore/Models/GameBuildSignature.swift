import Foundation

public struct GameBuildIdentity: Equatable, Codable, Sendable {
    public let bundleID: String
    public let version: String
    public let buildGUID: String

    public init(bundleID: String, version: String, buildGUID: String) {
        self.bundleID = bundleID
        self.version = version
        self.buildGUID = buildGUID
    }
}

public struct GameBuildPaths: Equatable, Codable, Sendable {
    public let executablePath: String
    public let metadataPath: String

    public init(executablePath: String, metadataPath: String) {
        self.executablePath = executablePath
        self.metadataPath = metadataPath
    }
}

public struct GameBuildSignature: Equatable, Codable, Sendable {
    public let bundleID: String
    public let version: String
    public let buildGUID: String
    public let executablePath: String
    public let metadataPath: String

    public init(identity: GameBuildIdentity, paths: GameBuildPaths) {
        self.bundleID = identity.bundleID
        self.version = identity.version
        self.buildGUID = identity.buildGUID
        self.executablePath = paths.executablePath
        self.metadataPath = paths.metadataPath
    }

    public var isKnownBaseline: Bool {
        matchesIdentity(of: KnownGameBuild.current)
    }

    public var isDaveTheDiverBundle: Bool {
        bundleID == KnownGameBuild.current.bundleID
    }

    public func matchesIdentity(of profile: GameBuildSignature) -> Bool {
        bundleID == profile.bundleID
            && version == profile.version
            && buildGUID == profile.buildGUID
    }
}

public enum KnownGameBuild {
    public static let v106675 = GameBuildSignature(
        identity: GameBuildIdentity(
            bundleID: "com.nexon.dave",
            version: "v1.0.6.675.mac",
            buildGUID: "9d9190d99a8647ccb8b33f089cd69abb"
        ),
        paths: GameBuildPaths(
            executablePath: "/Applications/DaveTheDiver.app/Contents/Game/DaveTheDiver.app/Contents/MacOS/DAVE THE DIVER",
            metadataPath: "/Applications/DaveTheDiver.app/Contents/Game/DaveTheDiver.app/Contents/Resources/Data/il2cpp_data/Metadata/global-metadata.dat"
        )
    )

    public static let v106710 = GameBuildSignature(
        identity: GameBuildIdentity(
            bundleID: "com.nexon.dave",
            version: "v1.0.6.710.mac",
            buildGUID: "fd04739b28e64f148c3efcd479a839b8"
        ),
        paths: GameBuildPaths(
            executablePath: "/Applications/DaveTheDiver.app/Contents/Game/DaveTheDiver.app/Contents/MacOS/DAVE THE DIVER",
            metadataPath: "/Applications/DaveTheDiver.app/Contents/Game/DaveTheDiver.app/Contents/Resources/Data/il2cpp_data/Metadata/global-metadata.dat"
        )
    )

    public static let v106756 = GameBuildSignature(
        identity: GameBuildIdentity(
            bundleID: "com.nexon.dave",
            version: "v1.0.6.756.mac",
            buildGUID: "1958d94b767741a5a13a2ae0032db743"
        ),
        paths: GameBuildPaths(
            executablePath: "/Applications/DaveTheDiver.app/Contents/Game/DaveTheDiver.app/Contents/MacOS/DAVE THE DIVER",
            metadataPath: "/Applications/DaveTheDiver.app/Contents/Game/DaveTheDiver.app/Contents/Resources/Data/il2cpp_data/Metadata/global-metadata.dat"
        )
    )

    public static let current = v106675
}
