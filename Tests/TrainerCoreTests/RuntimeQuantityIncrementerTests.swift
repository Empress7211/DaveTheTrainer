import XCTest
@testable import TrainerCore

final class RuntimeQuantityIncrementerTests: XCTestCase {
    func testV106756CurrenciesAndBothChefFlamesUseNewSaveLayout() throws {
        for resourceID in ["gold", "bei", "jungleGold", "artisan"] {
            let fixture = StaticSaveChainFixture(layout: .v106756)
            let session = InMemoryRuntimeQuantitySession(segments: fixture.segments)
            let result = try RuntimeQuantityIncrementer(moduleResolver: fixture.moduleResolver, layout: .v106756).increment(
                RuntimeQuantityIncrementRequest(featureID: resourceID, delta: 99), session: session
            )
            func quantity(_ offset: UInt64) throws -> Int32? {
                ObscuredInt32Value(data: try session.read(MemoryReadRequest(address: fixture.playerInfoAddress + offset, size: 0x14)))?.value
            }
            XCTAssertEqual(try quantity(0x10), resourceID == "gold" ? 1_099 : 1_000)
            XCTAssertEqual(try quantity(0x24), resourceID == "bei" ? 2_099 : 2_000)
            XCTAssertEqual(try quantity(0x38), resourceID == "artisan" ? 399 : 300)
            XCTAssertEqual(try session.readInt32(address: fixture.jungleGoldAddress), resourceID == "jungleGold" ? 876 : 777)
            XCTAssertEqual(try session.readInt32(address: fixture.jungleChefFlameAddress), resourceID == "artisan" ? 129 : 30)
            XCTAssertEqual(result.updatedAddressCount, resourceID == "artisan" ? 2 : 1)
            XCTAssertEqual(session.regionsCallCount, 0)
        }
    }

    func testV106756LayoutCannotFallBackToOldSingletonSlots() throws {
        let fixture = StaticSaveChainFixture()
        let session = InMemoryRuntimeQuantitySession(segments: fixture.segments)
        XCTAssertThrowsError(try RuntimeQuantityIncrementer(moduleResolver: fixture.moduleResolver, layout: .v106756).increment(
            RuntimeQuantityIncrementRequest(featureID: "gold", delta: 99), session: session
        ))
        let stored = try session.read(MemoryReadRequest(address: fixture.playerInfoAddress + 0x10, size: 0x14))
        XCTAssertEqual(ObscuredInt32Value(data: stored)?.value, 1_000)
        XCTAssertEqual(session.regionsCallCount, 0)
    }

    func testObscuredInt32DecodesAndReencodesWithExistingKey() throws {
        let original = ObscuredInt32Value(currentCryptoKey: 0x1357_2468, value: 12_345, fakeValueActive: true)
        let decoded = try XCTUnwrap(ObscuredInt32Value(data: original.data))
        let next = decoded.replacingValue(22_344)

        XCTAssertEqual(decoded.value, 12_345)
        XCTAssertEqual(ObscuredInt32Value(data: next.data)?.value, 22_344)
        XCTAssertEqual(ObscuredInt32Value(data: next.data)?.fakeValue, 22_344)
        XCTAssertEqual(ObscuredInt32Value(data: next.data)?.currentCryptoKey, 0x1357_2468)
    }

    func testPlayerInfoSaveScannerFindsStableQuantityFields() {
        let baseAddress = UInt64(0x1_0000_0000)
        let objectOffset = 0x80
        var buffer = Data(count: 0x200)
        buffer.writeUInt64(baseAddress + 0x5000, at: objectOffset)
        buffer.writeUInt64(0, at: objectOffset + 0x8)
        buffer.writeObscuredInt32(1_000, at: objectOffset + 0x10)
        buffer.writeObscuredInt32(2_000, at: objectOffset + 0x24)
        buffer.writeObscuredInt32(300, at: objectOffset + 0x38)

        let candidates = PlayerInfoSaveObjectScanner().candidates(in: buffer, baseAddress: baseAddress)

        XCTAssertEqual(candidates, [
            PlayerInfoSaveObjectCandidate(
                objectAddress: baseAddress + UInt64(objectOffset),
                goldAddress: baseAddress + UInt64(objectOffset + 0x10),
                beiAddress: baseAddress + UInt64(objectOffset + 0x24),
                chefFlameAddress: baseAddress + UInt64(objectOffset + 0x38),
                gold: 1_000,
                bei: 2_000,
                chefFlame: 300
            )
        ])
    }

    func testPlayerInfoSaveScannerRejectsInvalidActiveFakeValue() {
        let baseAddress = UInt64(0x2_0000_0000)
        var buffer = Data(count: 0x100)
        buffer.writeUInt64(baseAddress + 0x5000, at: 0)
        buffer.writeObscuredInt32(1_000, at: 0x10)
        buffer.writeObscuredInt32(2_000, at: 0x24, fakeValue: 99)
        buffer.writeObscuredInt32(300, at: 0x38)

        let candidates = PlayerInfoSaveObjectScanner().candidates(in: buffer, baseAddress: baseAddress)

        XCTAssertTrue(candidates.isEmpty)
    }

    func testPlayerInfoSaveScannerRejectsMatchingFieldsWithoutObjectHeader() {
        let baseAddress = UInt64(0x3_0000_0000)
        var buffer = Data(count: 0x100)
        buffer.writeObscuredInt32(1_000, at: 0x10)
        buffer.writeObscuredInt32(2_000, at: 0x24)
        buffer.writeObscuredInt32(300, at: 0x38)

        let candidates = PlayerInfoSaveObjectScanner().candidates(in: buffer, baseAddress: baseAddress)

        XCTAssertTrue(candidates.isEmpty)
    }

    func testSaveDataJungleScannerFindsJungleGoldPointerChain() {
        let baseAddress = UInt64(0x3_0000_0000)
        let objectOffset = 0x40
        let holderAddress = baseAddress + 0x180
        var buffer = Data(count: 0x220)
        buffer.writeUInt64(baseAddress + 0x7000, at: objectOffset)
        buffer.writeUInt64(holderAddress, at: objectOffset + 0xD0)
        buffer.writeUInt64(baseAddress + 0x7100, at: 0x180)
        buffer.writeInt32(777, at: 0x190)
        buffer.writeInt32(30, at: 0x194)

        let candidates = SaveDataJungleObjectScanner().candidates(in: buffer, baseAddress: baseAddress)

        XCTAssertEqual(candidates, [
            SaveDataJungleObjectCandidate(
                objectAddress: baseAddress + UInt64(objectOffset),
                jungleGoldAddress: holderAddress + 0x10,
                jungleChefFlameAddress: holderAddress + 0x14,
                jungleGold: 777,
                jungleChefFlame: 30
            )
        ])
    }

    func testRuntimeIncrementerAutomaticallyIncrementsGoldWithoutAddressBook() throws {
        let fixture = StaticSaveChainFixture()
        let session = InMemoryRuntimeQuantitySession(segments: fixture.segments)

        let result = try RuntimeQuantityIncrementer(moduleResolver: fixture.moduleResolver).increment(
            RuntimeQuantityIncrementRequest(featureID: "gold", delta: 99),
            session: session
        )

        let stored = try session.read(MemoryReadRequest(address: fixture.playerInfoAddress + 0x10, size: 0x14))
        XCTAssertEqual(result.updatedAddressCount, 1)
        XCTAssertEqual(session.regionsCallCount, 0)
        XCTAssertEqual(ObscuredInt32Value(data: stored)?.value, 1_099)
    }

    func testRuntimeIncrementerThrowsVerifyFailedWhenReadbackDoesNotChange() throws {
        let fixture = StaticSaveChainFixture()
        let session = InMemoryRuntimeQuantitySession(
            segments: fixture.segments,
            ignoredWriteAddresses: [fixture.playerInfoAddress + 0x10]
        )

        XCTAssertThrowsError(try RuntimeQuantityIncrementer(moduleResolver: fixture.moduleResolver).increment(
            RuntimeQuantityIncrementRequest(featureID: "gold", delta: 99),
            session: session
        )) { error in
            guard case TrainerError.verifyFailed = error else {
                XCTFail("Expected verifyFailed, got \(error)")
                return
            }
        }
    }

    func testCachedAddressVerifyFailureDoesNotRetryAndDoubleIncrement() throws {
        let fixture = StaticSaveChainFixture()
        let session = InMemoryRuntimeQuantitySession(segments: fixture.segments)
        let incrementer = RuntimeQuantityIncrementer(moduleResolver: fixture.moduleResolver)

        _ = try incrementer.increment(
            RuntimeQuantityIncrementRequest(featureID: "gold", delta: 99),
            session: session
        )
        session.ignoreWrites(to: fixture.playerInfoAddress + 0x10)

        XCTAssertThrowsError(try incrementer.increment(
            RuntimeQuantityIncrementRequest(featureID: "gold", delta: 1),
            session: session
        )) { error in
            guard case TrainerError.verifyFailed = error else {
                XCTFail("Expected verifyFailed, got \(error)")
                return
            }
        }

        let stored = try session.read(MemoryReadRequest(address: fixture.playerInfoAddress + 0x10, size: 0x14))
        XCTAssertEqual(ObscuredInt32Value(data: stored)?.value, 1_099)
        XCTAssertEqual(fixture.moduleResolver.resolveCallCount, 1)
    }

    func testCachedObscuredInt32ReadbackFailureDoesNotRetryAndDoubleIncrement() throws {
        let fixture = StaticSaveChainFixture()
        let session = InMemoryRuntimeQuantitySession(segments: fixture.segments)
        let incrementer = RuntimeQuantityIncrementer(moduleResolver: fixture.moduleResolver)
        let goldAddress = fixture.playerInfoAddress + 0x10

        _ = try incrementer.increment(
            RuntimeQuantityIncrementRequest(featureID: "gold", delta: 99),
            session: session
        )
        session.failReadsAfterSuccessfulWrite(to: goldAddress)

        XCTAssertThrowsError(try incrementer.increment(
            RuntimeQuantityIncrementRequest(featureID: "gold", delta: 1),
            session: session
        )) { error in
            guard case TrainerError.verifyFailed = error else {
                XCTFail("Expected verifyFailed, got \(error)")
                return
            }
        }

        session.allowReads(to: goldAddress)
        let stored = try session.read(MemoryReadRequest(address: goldAddress, size: 0x14))
        XCTAssertEqual(ObscuredInt32Value(data: stored)?.value, 1_100)
        XCTAssertEqual(fixture.moduleResolver.resolveCallCount, 1)
    }

    func testRuntimeIncrementerClampsNegativeGoldDeltaToOne() throws {
        let fixture = StaticSaveChainFixture()
        let session = InMemoryRuntimeQuantitySession(segments: fixture.segments)

        let result = try RuntimeQuantityIncrementer(moduleResolver: fixture.moduleResolver).increment(
            RuntimeQuantityIncrementRequest(featureID: "gold", delta: -9_999),
            session: session
        )

        let stored = try session.read(MemoryReadRequest(address: fixture.playerInfoAddress + 0x10, size: 0x14))
        XCTAssertEqual(result.updatedAddressCount, 1)
        XCTAssertEqual(session.regionsCallCount, 0)
        XCTAssertEqual(ObscuredInt32Value(data: stored)?.value, 1)
    }

    func testRuntimeIncrementerReusesResolvedGoldAddressWithoutHeapScan() throws {
        let fixture = StaticSaveChainFixture()
        let session = InMemoryRuntimeQuantitySession(segments: fixture.segments)
        let incrementer = RuntimeQuantityIncrementer(moduleResolver: fixture.moduleResolver)

        _ = try incrementer.increment(
            RuntimeQuantityIncrementRequest(featureID: "gold", delta: 99),
            session: session
        )
        _ = try incrementer.increment(
            RuntimeQuantityIncrementRequest(featureID: "gold", delta: 1),
            session: session
        )

        let stored = try session.read(MemoryReadRequest(address: fixture.playerInfoAddress + 0x10, size: 0x14))
        XCTAssertEqual(session.regionsCallCount, 0)
        XCTAssertEqual(ObscuredInt32Value(data: stored)?.value, 1_100)
    }

    func testOldCachedAddressFailureClearsCacheAndRetriesOnce() throws {
        let fixture = StaticSaveChainFixture()
        let session = InMemoryRuntimeQuantitySession(segments: fixture.segments)
        let incrementer = RuntimeQuantityIncrementer(moduleResolver: fixture.moduleResolver)

        _ = try incrementer.increment(
            RuntimeQuantityIncrementRequest(featureID: "gold", delta: 99),
            session: session
        )
        try session.write(MemoryWriteRequest(address: fixture.playerInfoAddress + 0x10, data: Data(count: 0x14)))
        var replacementPointer = Data(count: 8)
        replacementPointer.writeUInt64(fixture.replacementPlayerInfoAddress, at: 0)
        try session.write(MemoryWriteRequest(address: fixture.saveDataAddress + 0x220, data: replacementPointer))

        let result = try incrementer.increment(
            RuntimeQuantityIncrementRequest(featureID: "gold", delta: 1),
            session: session
        )

        let stored = try session.read(MemoryReadRequest(address: fixture.replacementPlayerInfoAddress + 0x10, size: 0x14))
        XCTAssertEqual(result.updatedAddressCount, 1)
        XCTAssertEqual(ObscuredInt32Value(data: stored)?.value, 5_001)
        XCTAssertEqual(fixture.moduleResolver.resolveCallCount, 2)
        XCTAssertEqual(session.regionsCallCount, 0)
    }

    func testOldCachedAddressRetryFailureIsExposed() throws {
        let fixture = StaticSaveChainFixture()
        let session = InMemoryRuntimeQuantitySession(segments: fixture.segments)
        let incrementer = RuntimeQuantityIncrementer(moduleResolver: fixture.moduleResolver)

        _ = try incrementer.increment(
            RuntimeQuantityIncrementRequest(featureID: "gold", delta: 99),
            session: session
        )
        try session.write(MemoryWriteRequest(address: fixture.playerInfoAddress + 0x10, data: Data(count: 0x14)))

        XCTAssertThrowsError(try incrementer.increment(
            RuntimeQuantityIncrementRequest(featureID: "gold", delta: 1),
            session: session
        ))
        XCTAssertEqual(fixture.moduleResolver.resolveCallCount, 2)
        XCTAssertEqual(session.regionsCallCount, 0)
    }

    func testRuntimeIncrementerReusesResolvedGameAssemblyAcrossFeatures() throws {
        let fixture = StaticSaveChainFixture()
        let session = InMemoryRuntimeQuantitySession(segments: fixture.segments)
        let incrementer = RuntimeQuantityIncrementer(moduleResolver: fixture.moduleResolver)

        _ = try incrementer.increment(
            RuntimeQuantityIncrementRequest(featureID: "gold", delta: 99),
            session: session
        )
        _ = try incrementer.increment(
            RuntimeQuantityIncrementRequest(featureID: "bei", delta: 1),
            session: session
        )

        let gold = try session.read(MemoryReadRequest(address: fixture.playerInfoAddress + 0x10, size: 0x14))
        let bei = try session.read(MemoryReadRequest(address: fixture.playerInfoAddress + 0x24, size: 0x14))
        XCTAssertEqual(fixture.moduleResolver.resolveCallCount, 1)
        XCTAssertEqual(ObscuredInt32Value(data: gold)?.value, 1_099)
        XCTAssertEqual(ObscuredInt32Value(data: bei)?.value, 2_001)
    }

    func testRuntimeIncrementerInvalidatesResolvedGameAssemblyWhenProcessChanges() throws {
        let fixture = StaticSaveChainFixture()
        let firstSession = InMemoryRuntimeQuantitySession(segments: fixture.segments, runtimeProcessID: 100)
        let secondSession = InMemoryRuntimeQuantitySession(segments: fixture.segments, runtimeProcessID: 200)
        let incrementer = RuntimeQuantityIncrementer(moduleResolver: fixture.moduleResolver)

        _ = try incrementer.increment(
            RuntimeQuantityIncrementRequest(featureID: "gold", delta: 99),
            session: firstSession
        )
        _ = try incrementer.increment(
            RuntimeQuantityIncrementRequest(featureID: "bei", delta: 1),
            session: secondSession
        )

        XCTAssertEqual(fixture.moduleResolver.resolveCallCount, 2)
    }

    func testRuntimeIncrementerClearsResolvedGameAssemblyCache() throws {
        let fixture = StaticSaveChainFixture()
        let session = InMemoryRuntimeQuantitySession(segments: fixture.segments)
        let incrementer = RuntimeQuantityIncrementer(moduleResolver: fixture.moduleResolver)

        _ = try incrementer.increment(
            RuntimeQuantityIncrementRequest(featureID: "gold", delta: 99),
            session: session
        )
        incrementer.clearCachedAddresses()
        _ = try incrementer.increment(
            RuntimeQuantityIncrementRequest(featureID: "bei", delta: 1),
            session: session
        )

        XCTAssertEqual(fixture.moduleResolver.resolveCallCount, 2)
    }

    func testRuntimeIncrementerIncrementsJungleGoldWithoutHeapScan() throws {
        let fixture = StaticSaveChainFixture()
        let session = InMemoryRuntimeQuantitySession(segments: fixture.segments)

        let result = try RuntimeQuantityIncrementer(moduleResolver: fixture.moduleResolver).increment(
            RuntimeQuantityIncrementRequest(featureID: "jungleGold", delta: 999),
            session: session
        )

        XCTAssertEqual(result.updatedAddressCount, 1)
        XCTAssertEqual(session.regionsCallCount, 0)
        XCTAssertEqual(try session.readInt32(address: fixture.jungleGoldAddress), 1_776)
    }

    func testCachedPlainInt32ReadbackFailureDoesNotRetryAndDoubleIncrement() throws {
        let fixture = StaticSaveChainFixture()
        let session = InMemoryRuntimeQuantitySession(segments: fixture.segments)
        let incrementer = RuntimeQuantityIncrementer(moduleResolver: fixture.moduleResolver)

        _ = try incrementer.increment(
            RuntimeQuantityIncrementRequest(featureID: "jungleGold", delta: 999),
            session: session
        )
        session.failReadsAfterSuccessfulWrite(to: fixture.jungleGoldAddress)

        XCTAssertThrowsError(try incrementer.increment(
            RuntimeQuantityIncrementRequest(featureID: "jungleGold", delta: 1),
            session: session
        )) { error in
            guard case TrainerError.verifyFailed = error else {
                XCTFail("Expected verifyFailed, got \(error)")
                return
            }
        }

        session.allowReads(to: fixture.jungleGoldAddress)
        XCTAssertEqual(try session.readInt32(address: fixture.jungleGoldAddress), 1_777)
        XCTAssertEqual(fixture.moduleResolver.resolveCallCount, 1)
    }

    func testRuntimeIncrementerClampsNegativeJungleGoldDeltaToOne() throws {
        let fixture = StaticSaveChainFixture()
        let session = InMemoryRuntimeQuantitySession(segments: fixture.segments)

        let result = try RuntimeQuantityIncrementer(moduleResolver: fixture.moduleResolver).increment(
            RuntimeQuantityIncrementRequest(featureID: "jungleGold", delta: -9_999),
            session: session
        )

        XCTAssertEqual(result.updatedAddressCount, 1)
        XCTAssertEqual(session.regionsCallCount, 0)
        XCTAssertEqual(try session.readInt32(address: fixture.jungleGoldAddress), 1)
    }

    func testRuntimeIncrementerIncrementsMainAndJungleChefFlameWithoutHeapScan() throws {
        let fixture = StaticSaveChainFixture()
        let session = InMemoryRuntimeQuantitySession(segments: fixture.segments)

        let result = try RuntimeQuantityIncrementer(moduleResolver: fixture.moduleResolver).increment(
            RuntimeQuantityIncrementRequest(featureID: "artisan", delta: 99),
            session: session
        )

        let stored = try session.read(MemoryReadRequest(address: fixture.playerInfoAddress + 0x38, size: 0x14))
        XCTAssertEqual(result.updatedAddressCount, 2)
        XCTAssertEqual(session.regionsCallCount, 0)
        XCTAssertEqual(ObscuredInt32Value(data: stored)?.value, 399)
        XCTAssertEqual(try session.readInt32(address: fixture.jungleChefFlameAddress), 129)
    }
}

private struct StaticSaveChainFixture {
    let moduleBaseAddress: UInt64
    let saveDataAddress: UInt64
    let playerInfoAddress: UInt64
    let replacementPlayerInfoAddress: UInt64
    let jungleGoldAddress: UInt64
    let jungleChefFlameAddress: UInt64
    let moduleResolver: StaticModuleResolver
    let segments: [UInt64: Data]

    init(layout: DaveRuntimeLayout = .v106675) {
        let moduleBaseAddress = UInt64(0x1_0000_0000)
        let playerInfoAddress = UInt64(0x8_0000_0000)
        let replacementPlayerInfoAddress = UInt64(0x8_1000_0000)
        let methodVariableAddress = moduleBaseAddress + layout.saveSystemInstanceMethodRVA
        let typeInfoVariableAddress = moduleBaseAddress + 0x987ECF8
        let methodInfoAddress = UInt64(0x2_0000_0000)
        let genericContextAddress = UInt64(0x3_0000_0000)
        let genericClassAddress = UInt64(0x4_0000_0000)
        let saveSystemClassAddress = UInt64(0x5_0000_0000)
        let staticFieldsAddress = UInt64(0x6_0000_0000)
        let saveSystemAddress = UInt64(0x7_0000_0000)
        let gameDataManagerAddress = UInt64(0x7_1000_0000)
        let saveDataAddress = UInt64(0x7_2000_0000)
        let staleCurrentGameSaveAddress = UInt64(0x7_3000_0000)
        let jungleSaveDataAddress = UInt64(0x7_4000_0000)
        let jungleGoldHolderAddress = UInt64(0x7_5000_0000)

        self.moduleBaseAddress = moduleBaseAddress
        self.saveDataAddress = saveDataAddress
        self.playerInfoAddress = playerInfoAddress
        self.replacementPlayerInfoAddress = replacementPlayerInfoAddress
        self.jungleGoldAddress = jungleGoldHolderAddress + 0x10
        self.jungleChefFlameAddress = jungleGoldHolderAddress + 0x14
        self.moduleResolver = StaticModuleResolver(baseAddress: moduleBaseAddress)
        self.segments = [
            methodVariableAddress: Self.pointerData(methodInfoAddress),
            typeInfoVariableAddress: Self.pointerData(saveSystemClassAddress),
            methodInfoAddress: Self.methodInfoData(genericContextAddress: genericContextAddress),
            genericContextAddress: Self.genericContextData(genericClassAddress: genericClassAddress),
            genericClassAddress: Self.genericClassData(classAddress: saveSystemClassAddress),
            saveSystemClassAddress: Self.saveSystemClassData(staticFieldsAddress: staticFieldsAddress),
            staticFieldsAddress: Self.saveSystemStaticFieldsData(
                saveSystemAddress: saveSystemAddress,
                currentGameSaveAddress: staleCurrentGameSaveAddress
            ),
            saveSystemAddress: Self.saveSystemData(gameDataManagerAddress: gameDataManagerAddress),
            gameDataManagerAddress: Self.gameDataManagerData(saveDataAddress: saveDataAddress),
            saveDataAddress: Self.saveDataObjectData(
                playerInfoAddress: playerInfoAddress,
                jungleSaveDataAddress: jungleSaveDataAddress,
                layout: layout
            ),
            playerInfoAddress: Self.playerInfoSaveData(),
            replacementPlayerInfoAddress: Self.playerInfoSaveData(gold: 5_000, bei: 6_000, chefFlame: 700),
            staleCurrentGameSaveAddress: Self.runtimeObjectData(count: 0x2B0),
            jungleSaveDataAddress: Self.jungleSaveData(holderAddress: jungleGoldHolderAddress),
            jungleGoldHolderAddress: Self.jungleGoldHolderData()
        ]
    }

    private static func pointerData(_ value: UInt64) -> Data {
        var data = Data(count: 8)
        data.writeUInt64(value, at: 0)
        return data
    }

    private static func methodInfoData(genericContextAddress: UInt64) -> Data {
        var data = Data(count: 0x28)
        data.writeUInt64(genericContextAddress, at: 0x20)
        return data
    }

    private static func genericContextData(genericClassAddress: UInt64) -> Data {
        var data = Data(count: 0xC8)
        data.writeUInt64(genericClassAddress, at: 0xC0)
        return data
    }

    private static func genericClassData(classAddress: UInt64) -> Data {
        var data = Data(count: 0x18)
        data.writeUInt64(classAddress, at: 0x10)
        return data
    }

    private static func saveSystemClassData(staticFieldsAddress: UInt64) -> Data {
        var data = Data(count: 0xC0)
        data.writeUInt64(staticFieldsAddress, at: 0xB8)
        return data
    }

    private static func saveSystemStaticFieldsData(
        saveSystemAddress: UInt64,
        currentGameSaveAddress: UInt64
    ) -> Data {
        var data = Data(count: 0x18)
        data.writeUInt64(saveSystemAddress, at: 0)
        data.writeUInt64(currentGameSaveAddress, at: 0x10)
        return data
    }

    private static func saveSystemData(gameDataManagerAddress: UInt64) -> Data {
        var data = runtimeObjectData(count: 0x58)
        data.writeUInt64(gameDataManagerAddress, at: 0x50)
        return data
    }

    private static func gameDataManagerData(saveDataAddress: UInt64) -> Data {
        var data = runtimeObjectData(count: 0x58)
        data.writeUInt64(saveDataAddress, at: 0x50)
        return data
    }

    private static func saveDataObjectData(playerInfoAddress: UInt64, jungleSaveDataAddress: UInt64, layout: DaveRuntimeLayout) -> Data {
        var data = runtimeObjectData(count: Int(layout.saveDataJungleOffset) + 8)
        data.writeUInt64(playerInfoAddress, at: Int(layout.saveDataPlayerInfoOffset))
        data.writeUInt64(jungleSaveDataAddress, at: Int(layout.saveDataJungleOffset))
        return data
    }

    private static func playerInfoSaveData(gold: Int32 = 1_000, bei: Int32 = 2_000, chefFlame: Int32 = 300) -> Data {
        var data = runtimeObjectData(count: 0x4C)
        data.writeObscuredInt32(gold, at: 0x10)
        data.writeObscuredInt32(bei, at: 0x24)
        data.writeObscuredInt32(chefFlame, at: 0x38)
        return data
    }

    private static func jungleSaveData(holderAddress: UInt64) -> Data {
        var data = runtimeObjectData(count: 0xD8)
        data.writeUInt64(holderAddress, at: 0xD0)
        return data
    }

    private static func jungleGoldHolderData() -> Data {
        var data = runtimeObjectData(count: 0x18)
        data.writeInt32(777, at: 0x10)
        data.writeInt32(30, at: 0x14)
        return data
    }

    private static func runtimeObjectData(count: Int) -> Data {
        var data = Data(count: count)
        data.writeUInt64(0x9_0000_0000, at: 0)
        data.writeUInt64(0, at: 0x8)
        return data
    }
}

private final class StaticModuleResolver: GameAssemblyResolving {
    let baseAddress: UInt64
    private(set) var resolveCallCount = 0

    init(baseAddress: UInt64) {
        self.baseAddress = baseAddress
    }

    func resolveGameAssembly(session: ModuleMemorySession) throws -> LoadedMachOModule {
        resolveCallCount += 1
        return LoadedMachOModule(name: "GameAssembly.dylib", baseAddress: baseAddress, headerSize: 0)
    }
}

private final class InMemoryRuntimeQuantitySession: RuntimeQuantityMemorySession {
    let runtimeProcessID: Int32
    private let orderedBaseAddresses: [UInt64]
    private var ignoredWriteAddresses: Set<UInt64>
    private var readFailureAddresses: Set<UInt64>
    private var readFailureAfterWriteAddresses: Set<UInt64>
    private var segments: [UInt64: Data]
    private(set) var regionsCallCount = 0

    init(
        segments: [UInt64: Data],
        runtimeProcessID: Int32 = 1,
        ignoredWriteAddresses: Set<UInt64> = []
    ) {
        self.runtimeProcessID = runtimeProcessID
        self.orderedBaseAddresses = segments.keys.sorted()
        self.ignoredWriteAddresses = ignoredWriteAddresses
        self.readFailureAddresses = []
        self.readFailureAfterWriteAddresses = []
        self.segments = segments
    }

    func ignoreWrites(to address: UInt64) {
        ignoredWriteAddresses.insert(address)
    }

    func failReadsAfterSuccessfulWrite(to address: UInt64) {
        readFailureAfterWriteAddresses.insert(address)
    }

    func allowReads(to address: UInt64) {
        readFailureAddresses.remove(address)
        readFailureAfterWriteAddresses.remove(address)
    }

    func regions() throws -> [MemoryRegion] {
        regionsCallCount += 1
        return try orderedBaseAddresses.map { baseAddress in
            let data = try segment(baseAddress: baseAddress)
            return MemoryRegion(descriptor: MemoryRegionDescriptor(
                range: MemoryRange(address: baseAddress, size: UInt64(data.count)),
                protection: MemoryProtectionInfo(
                    current: MemoryProtection.read | MemoryProtection.write,
                    maximum: MemoryProtection.read | MemoryProtection.write
                ),
                flags: MemoryRegionFlags(isSubmap: false, userTag: 0)
            ))
        }
    }

    func read(_ request: MemoryReadRequest) throws -> Data {
        guard !readFailureAddresses.contains(request.address) else {
            throw TrainerError.memoryReadFailed("测试强制读回失败：0x\(String(request.address, radix: 16))。")
        }
        let resolved = try resolvedSegment(address: request.address, size: request.size)
        return resolved.data.subdata(in: resolved.offset..<(resolved.offset + request.size))
    }

    func write(_ request: MemoryWriteRequest) throws {
        guard !ignoredWriteAddresses.contains(request.address) else {
            return
        }
        let resolved = try resolvedSegment(address: request.address, size: request.data.count)
        var data = resolved.data
        data.replaceSubrange(resolved.offset..<(resolved.offset + request.data.count), with: request.data)
        segments[resolved.baseAddress] = data
        if readFailureAfterWriteAddresses.contains(request.address) {
            readFailureAddresses.insert(request.address)
        }
    }

    func readInt32(address: UInt64) throws -> Int32 {
        let data = try read(MemoryReadRequest(address: address, size: MemoryLayout<Int32>.size))
        return data.testInt32(at: 0)
    }

    private func resolvedSegment(address: UInt64, size: Int) throws -> (baseAddress: UInt64, offset: Int, data: Data) {
        guard size > 0 else {
            throw TrainerError.invalidInput("测试内存读写长度必须大于 0。")
        }

        for baseAddress in orderedBaseAddresses {
            let data = try segment(baseAddress: baseAddress)
            let endAddress = baseAddress + UInt64(data.count)
            guard address >= baseAddress, address + UInt64(size) <= endAddress else {
                continue
            }
            return (baseAddress, Int(address - baseAddress), data)
        }

        throw TrainerError.memoryReadFailed("测试内存地址越界：0x\(String(address, radix: 16))。")
    }

    private func segment(baseAddress: UInt64) throws -> Data {
        guard let data = segments[baseAddress] else {
            throw TrainerError.memoryReadFailed("测试内存段不存在：0x\(String(baseAddress, radix: 16))。")
        }
        return data
    }
}

private extension Data {
    mutating func writeObscuredInt32(
        _ value: Int32,
        at offset: Int,
        fakeValue: Int32? = nil
    ) {
        let obscured = ObscuredInt32Value(
            currentCryptoKey: 0x1357_2468,
            value: value,
            fakeValue: fakeValue ?? value,
            fakeValueActive: true
        )
        replaceSubrange(offset..<(offset + obscured.data.count), with: obscured.data)
    }

    mutating func writeInt32(_ value: Int32, at offset: Int) {
        let bytes = Swift.withUnsafeBytes(of: value.littleEndian) { Array($0) }
        replaceSubrange(offset..<(offset + bytes.count), with: bytes)
    }

    mutating func writeUInt64(_ value: UInt64, at offset: Int) {
        let bytes = Swift.withUnsafeBytes(of: value.littleEndian) { Array($0) }
        replaceSubrange(offset..<(offset + bytes.count), with: bytes)
    }

    func testInt32(at offset: Int) -> Int32 {
        let first = UInt32(self[offset])
        let second = UInt32(self[offset + 1]) << 8
        let third = UInt32(self[offset + 2]) << 16
        let fourth = UInt32(self[offset + 3]) << 24
        return Int32(bitPattern: first | second | third | fourth)
    }
}
