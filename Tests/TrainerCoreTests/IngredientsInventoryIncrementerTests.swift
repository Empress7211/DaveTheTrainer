import XCTest
@testable import TrainerCore

final class IngredientsInventoryIncrementerTests: XCTestCase {
    func testV106756InventoryUpdatesRuntimeAndSaveThroughNewDictionaryOffset() throws {
        for scope in [IngredientsInventoryScope.all, .fish, .vegetable] {
            let fixture = StaticIngredientsStorageFixture(layout: .v106756)
            let session = InMemoryIngredientsInventorySession(segments: fixture.segments)
            let result = try IngredientsInventoryIncrementer(moduleResolver: fixture.moduleResolver, layout: .v106756).increment(
                IngredientsInventoryIncrementRequest(scope: scope, delta: 9), session: session
            )
            let fishCount: Int32 = scope == .vegetable ? 10 : 19
            let vegetableCount: Int32 = scope == .fish ? 20 : 29
            XCTAssertEqual(try session.readInt32(address: fixture.fishCountAddress), fishCount)
            XCTAssertEqual(try session.readInt32(address: fixture.vegetableCountAddress), vegetableCount)
            XCTAssertEqual(try session.readObscuredInt32(address: fixture.fishSaveCountAddress), fishCount)
            XCTAssertEqual(try session.readObscuredInt32(address: fixture.vegetableSaveCountAddress), vegetableCount)
            XCTAssertEqual(result.updatedItemCount, scope == .all ? 2 : 1)
            XCTAssertEqual(try session.readByte(address: fixture.saveDirtyFlagAddress), 1)
            XCTAssertEqual(session.regionsCallCount, 0)
        }
    }

    func testV106756SeasoningAndUpgradeScopesKeepRuntimeAndSaveInSync() throws {
        for (scope, type) in [(IngredientsInventoryScope.seasoning, Int32(3)), (.upgrade, Int32(4))] {
            let fixture = StaticIngredientsStorageFixture(layout: .v106756, secondIngredientType: type)
            let session = InMemoryIngredientsInventorySession(segments: fixture.segments)
            let result = try IngredientsInventoryIncrementer(moduleResolver: fixture.moduleResolver, layout: .v106756).increment(
                IngredientsInventoryIncrementRequest(scope: scope, delta: 9), session: session
            )
            XCTAssertEqual(result.updatedItemCount, 1)
            XCTAssertEqual(try session.readInt32(address: fixture.fishCountAddress), 10)
            XCTAssertEqual(try session.readObscuredInt32(address: fixture.fishSaveCountAddress), 10)
            XCTAssertEqual(try session.readInt32(address: fixture.vegetableCountAddress), 29)
            XCTAssertEqual(try session.readObscuredInt32(address: fixture.vegetableSaveCountAddress), 29)
            XCTAssertEqual(session.regionsCallCount, 0)
        }
    }

    func testObjectScannerFindsVegetableIngredientsDataCandidate() {
        let baseAddress = UInt64(0x1_0000_0000)
        let objectOffset = 0x40
        let countsAddress = baseAddress + 0x200
        let entityAddress = baseAddress + 0x300
        var buffer = Data(count: 0x180)
        buffer.writeInt32(101, at: objectOffset + 0x10)
        buffer.writeInt32(2, at: objectOffset + 0x20)
        buffer.writeUInt64(countsAddress, at: objectOffset + 0x28)
        buffer.writeUInt64(entityAddress, at: objectOffset + 0x50)

        let candidates = IngredientsInventoryObjectScanner().candidates(
            in: buffer,
            baseAddress: baseAddress,
            scope: .vegetable
        )

        XCTAssertEqual(candidates, [
            IngredientsInventoryObjectCandidate(
                objectAddress: baseAddress + UInt64(objectOffset),
                ingredientsID: 101,
                countsAddress: countsAddress,
                entityAddress: entityAddress,
                ingredientsType: 2
            )
        ])
    }

    func testObjectScannerFiltersDifferentIngredientsType() {
        let baseAddress = UInt64(0x2_0000_0000)
        var buffer = Data(count: 0x100)
        buffer.writeInt32(102, at: 0x10)
        buffer.writeInt32(3, at: 0x20)
        buffer.writeUInt64(baseAddress + 0x200, at: 0x28)
        buffer.writeUInt64(baseAddress + 0x300, at: 0x50)

        let candidates = IngredientsInventoryObjectScanner().candidates(
            in: buffer,
            baseAddress: baseAddress,
            scope: .vegetable
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    func testObjectScannerDoesNotTreatNegativeTypeAsFish() {
        let baseAddress = UInt64(0x3_0000_0000)
        var buffer = Data(count: 0x100)
        buffer.writeInt32(103, at: 0x10)
        buffer.writeInt32(-1, at: 0x20)
        buffer.writeUInt64(baseAddress + 0x200, at: 0x28)
        buffer.writeUInt64(baseAddress + 0x300, at: 0x50)

        let candidates = IngredientsInventoryObjectScanner().candidates(
            in: buffer,
            baseAddress: baseAddress,
            scope: .fish
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    func testIncrementerIncrementsVegetableFromStaticIngredientsStorageWithoutHeapScan() throws {
        let fixture = StaticIngredientsStorageFixture()
        let session = InMemoryIngredientsInventorySession(segments: fixture.segments)

        let result = try IngredientsInventoryIncrementer(moduleResolver: fixture.moduleResolver).increment(
            IngredientsInventoryIncrementRequest(scope: .vegetable, delta: 9),
            session: session
        )

        XCTAssertEqual(result.updatedItemCount, 1)
        XCTAssertEqual(session.regionsCallCount, 0)
        XCTAssertEqual(try session.readInt32(address: fixture.fishCountAddress), 10)
        XCTAssertEqual(try session.readInt32(address: fixture.vegetableCountAddress), 29)
        XCTAssertEqual(try session.readObscuredInt32(address: fixture.fishSaveCountAddress), 10)
        XCTAssertEqual(try session.readObscuredInt32(address: fixture.vegetableSaveCountAddress), 29)
        XCTAssertEqual(try session.readByte(address: fixture.saveDirtyFlagAddress), 1)
    }

    func testIncrementerThrowsVerifyFailedWhenRuntimeCountReadbackDoesNotChange() throws {
        let fixture = StaticIngredientsStorageFixture()
        let session = InMemoryIngredientsInventorySession(
            segments: fixture.segments,
            ignoredWriteAddresses: [fixture.vegetableCountAddress]
        )

        XCTAssertThrowsError(try IngredientsInventoryIncrementer(moduleResolver: fixture.moduleResolver).increment(
            IngredientsInventoryIncrementRequest(scope: .vegetable, delta: 9),
            session: session
        )) { error in
            guard case TrainerError.verifyFailed = error else {
                XCTFail("Expected verifyFailed, got \(error)")
                return
            }
        }
    }

    func testIncrementerClampsNegativeIngredientDeltaToOne() throws {
        let fixture = StaticIngredientsStorageFixture()
        let session = InMemoryIngredientsInventorySession(segments: fixture.segments)

        let result = try IngredientsInventoryIncrementer(moduleResolver: fixture.moduleResolver).increment(
            IngredientsInventoryIncrementRequest(scope: .vegetable, delta: -999),
            session: session
        )

        XCTAssertEqual(result.updatedItemCount, 1)
        XCTAssertEqual(session.regionsCallCount, 0)
        XCTAssertEqual(try session.readInt32(address: fixture.fishCountAddress), 10)
        XCTAssertEqual(try session.readInt32(address: fixture.vegetableCountAddress), 1)
        XCTAssertEqual(try session.readObscuredInt32(address: fixture.fishSaveCountAddress), 10)
        XCTAssertEqual(try session.readObscuredInt32(address: fixture.vegetableSaveCountAddress), 1)
        XCTAssertEqual(try session.readByte(address: fixture.saveDirtyFlagAddress), 1)
    }

    func testIncrementerIncrementsAllIngredientsFromStaticDictionaryWithoutHeapScan() throws {
        let fixture = StaticIngredientsStorageFixture()
        let session = InMemoryIngredientsInventorySession(segments: fixture.segments)

        let result = try IngredientsInventoryIncrementer(moduleResolver: fixture.moduleResolver).increment(
            IngredientsInventoryIncrementRequest(scope: .all, delta: 5),
            session: session
        )

        XCTAssertEqual(result.updatedItemCount, 2)
        XCTAssertEqual(session.regionsCallCount, 0)
        XCTAssertEqual(try session.readInt32(address: fixture.fishCountAddress), 15)
        XCTAssertEqual(try session.readInt32(address: fixture.vegetableCountAddress), 25)
        XCTAssertEqual(try session.readObscuredInt32(address: fixture.fishSaveCountAddress), 15)
        XCTAssertEqual(try session.readObscuredInt32(address: fixture.vegetableSaveCountAddress), 25)
        XCTAssertEqual(try session.readByte(address: fixture.saveDirtyFlagAddress), 1)
    }

    func testIncrementerReusesResolvedIngredientsStorageWithoutHeapScan() throws {
        let fixture = StaticIngredientsStorageFixture()
        let session = InMemoryIngredientsInventorySession(segments: fixture.segments)
        let incrementer = IngredientsInventoryIncrementer(moduleResolver: fixture.moduleResolver)

        _ = try incrementer.increment(
            IngredientsInventoryIncrementRequest(scope: .vegetable, delta: 9),
            session: session
        )
        _ = try incrementer.increment(
            IngredientsInventoryIncrementRequest(scope: .fish, delta: 1),
            session: session
        )

        XCTAssertEqual(fixture.moduleResolver.resolveCallCount, 1)
        XCTAssertEqual(session.regionsCallCount, 0)
        XCTAssertEqual(try session.readInt32(address: fixture.fishCountAddress), 11)
        XCTAssertEqual(try session.readInt32(address: fixture.vegetableCountAddress), 29)
        XCTAssertEqual(try session.readObscuredInt32(address: fixture.fishSaveCountAddress), 11)
        XCTAssertEqual(try session.readObscuredInt32(address: fixture.vegetableSaveCountAddress), 29)
    }

    func testIncrementerInvalidatesResolvedIngredientsStorageWhenProcessChanges() throws {
        let fixture = StaticIngredientsStorageFixture()
        let firstSession = InMemoryIngredientsInventorySession(segments: fixture.segments, runtimeProcessID: 100)
        let secondSession = InMemoryIngredientsInventorySession(segments: fixture.segments, runtimeProcessID: 200)
        let incrementer = IngredientsInventoryIncrementer(moduleResolver: fixture.moduleResolver)

        _ = try incrementer.increment(
            IngredientsInventoryIncrementRequest(scope: .vegetable, delta: 9),
            session: firstSession
        )
        _ = try incrementer.increment(
            IngredientsInventoryIncrementRequest(scope: .fish, delta: 1),
            session: secondSession
        )

        XCTAssertEqual(fixture.moduleResolver.resolveCallCount, 2)
    }

    func testIncrementerClearsResolvedIngredientsStorageCache() throws {
        let fixture = StaticIngredientsStorageFixture()
        let session = InMemoryIngredientsInventorySession(segments: fixture.segments)
        let incrementer = IngredientsInventoryIncrementer(moduleResolver: fixture.moduleResolver)

        _ = try incrementer.increment(
            IngredientsInventoryIncrementRequest(scope: .vegetable, delta: 9),
            session: session
        )
        incrementer.clearCachedAddresses()
        _ = try incrementer.increment(
            IngredientsInventoryIncrementRequest(scope: .fish, delta: 1),
            session: session
        )

        XCTAssertEqual(fixture.moduleResolver.resolveCallCount, 2)
    }
}

private struct StaticIngredientsStorageFixture {
    let moduleResolver: StaticIngredientsModuleResolver
    let segments: [UInt64: Data]
    let fishCountAddress: UInt64
    let vegetableCountAddress: UInt64
    let fishSaveCountAddress: UInt64
    let vegetableSaveCountAddress: UInt64
    let saveDirtyFlagAddress: UInt64

    init(layout: DaveRuntimeLayout = .v106675, secondIngredientType: Int32 = 2) {
        let moduleBaseAddress = UInt64(0x1_0000_0000)
        let methodVariableAddress = moduleBaseAddress + layout.ingredientsInstanceMethodRVA
        let saveMethodVariableAddress = moduleBaseAddress + layout.saveSystemInstanceMethodRVA
        let methodInfoAddress = UInt64(0x2_0000_0000)
        let saveMethodInfoAddress = UInt64(0x2_1000_0000)
        let genericContextAddress = UInt64(0x3_0000_0000)
        let saveGenericContextAddress = UInt64(0x3_1000_0000)
        let genericClassAddress = UInt64(0x4_0000_0000)
        let saveGenericClassAddress = UInt64(0x4_1000_0000)
        let storageClassAddress = UInt64(0x5_0000_0000)
        let saveSystemClassAddress = UInt64(0x5_1000_0000)
        let staticFieldsAddress = UInt64(0x6_0000_0000)
        let saveStaticFieldsAddress = UInt64(0x6_1000_0000)
        let storageAddress = UInt64(0x7_0000_0000)
        let dictionaryAddress = UInt64(0x7_1000_0000)
        let entriesArrayAddress = UInt64(0x7_2000_0000)
        let saveSystemAddress = UInt64(0x7_3000_0000)
        let gameDataManagerAddress = UInt64(0x7_4000_0000)
        let saveDataAddress = UInt64(0x7_5000_0000)
        let playerInfoAddress = UInt64(0x7_6000_0000)
        let ingredientsSaveDictionaryAddress = UInt64(0x7_7000_0000)
        let ingredientsSaveEntriesArrayAddress = UInt64(0x7_8000_0000)
        let fishSaveAddress = UInt64(0x7_9000_0000)
        let vegetableSaveAddress = UInt64(0x7_A000_0000)
        let fishDataAddress = UInt64(0x8_0000_0000)
        let vegetableDataAddress = UInt64(0x8_1000_0000)
        let fishCountsAddress = UInt64(0x8_2000_0000)
        let vegetableCountsAddress = UInt64(0x8_3000_0000)
        let fishEntityAddress = UInt64(0x8_4000_0000)
        let vegetableEntityAddress = UInt64(0x8_5000_0000)

        self.moduleResolver = StaticIngredientsModuleResolver(baseAddress: moduleBaseAddress)
        self.fishCountAddress = fishCountsAddress + 0x20
        self.vegetableCountAddress = vegetableCountsAddress + 0x20
        self.fishSaveCountAddress = fishSaveAddress + 0x4C
        self.vegetableSaveCountAddress = vegetableSaveAddress + 0x4C
        self.saveDirtyFlagAddress = saveDataAddress + 0x29
        self.segments = [
            methodVariableAddress: Self.pointerData(methodInfoAddress),
            saveMethodVariableAddress: Self.pointerData(saveMethodInfoAddress),
            methodInfoAddress: Self.methodInfoData(genericContextAddress: genericContextAddress),
            saveMethodInfoAddress: Self.methodInfoData(genericContextAddress: saveGenericContextAddress),
            genericContextAddress: Self.genericContextData(genericClassAddress: genericClassAddress),
            saveGenericContextAddress: Self.genericContextData(genericClassAddress: saveGenericClassAddress),
            genericClassAddress: Self.genericClassData(classAddress: storageClassAddress),
            saveGenericClassAddress: Self.genericClassData(classAddress: saveSystemClassAddress),
            storageClassAddress: Self.storageClassData(staticFieldsAddress: staticFieldsAddress),
            saveSystemClassAddress: Self.storageClassData(staticFieldsAddress: saveStaticFieldsAddress),
            staticFieldsAddress: Self.staticFieldsData(storageAddress: storageAddress),
            saveStaticFieldsAddress: Self.staticFieldsData(storageAddress: saveSystemAddress),
            storageAddress: Self.storageData(dictionaryAddress: dictionaryAddress),
            dictionaryAddress: Self.dictionaryData(entriesArrayAddress: entriesArrayAddress),
            entriesArrayAddress: Self.entriesArrayData(
                fishDataAddress: fishDataAddress,
                vegetableDataAddress: vegetableDataAddress
            ),
            saveSystemAddress: Self.saveSystemData(gameDataManagerAddress: gameDataManagerAddress),
            gameDataManagerAddress: Self.gameDataManagerData(saveDataAddress: saveDataAddress),
            saveDataAddress: Self.saveDataObjectData(
                playerInfoAddress: playerInfoAddress,
                ingredientsSaveDictionaryAddress: ingredientsSaveDictionaryAddress,
                layout: layout
            ),
            playerInfoAddress: Self.runtimeObjectData(count: 0x4C),
            ingredientsSaveDictionaryAddress: Self.saveDictionaryData(entriesArrayAddress: ingredientsSaveEntriesArrayAddress),
            ingredientsSaveEntriesArrayAddress: Self.saveEntriesArrayData(
                fishSaveAddress: fishSaveAddress,
                vegetableSaveAddress: vegetableSaveAddress
            ),
            fishSaveAddress: Self.ingredientsSaveData(id: 101, count: 10),
            vegetableSaveAddress: Self.ingredientsSaveData(id: 102, count: 20),
            fishDataAddress: Self.ingredientsData(
                id: 101,
                type: 0,
                countsAddress: fishCountsAddress,
                entityAddress: fishEntityAddress
            ),
            vegetableDataAddress: Self.ingredientsData(
                id: 102,
                type: secondIngredientType,
                countsAddress: vegetableCountsAddress,
                entityAddress: vegetableEntityAddress
            ),
            fishCountsAddress: Self.countsArrayData(count: 10),
            vegetableCountsAddress: Self.countsArrayData(count: 20),
            fishEntityAddress: Self.entityData(type: 0),
            vegetableEntityAddress: Self.entityData(type: secondIngredientType)
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

    private static func storageClassData(staticFieldsAddress: UInt64) -> Data {
        var data = Data(count: 0xC0)
        data.writeUInt64(staticFieldsAddress, at: 0xB8)
        return data
    }

    private static func staticFieldsData(storageAddress: UInt64) -> Data {
        var data = Data(count: 0x8)
        data.writeUInt64(storageAddress, at: 0)
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

    private static func saveDataObjectData(playerInfoAddress: UInt64, ingredientsSaveDictionaryAddress: UInt64, layout: DaveRuntimeLayout) -> Data {
        var data = runtimeObjectData(count: Int(layout.saveDataPlayerInfoOffset) + 8)
        data.writeUInt64(ingredientsSaveDictionaryAddress, at: Int(layout.saveDataIngredientsDictionaryOffset))
        data.writeUInt64(playerInfoAddress, at: Int(layout.saveDataPlayerInfoOffset))
        return data
    }

    private static func storageData(dictionaryAddress: UInt64) -> Data {
        var data = runtimeObjectData(count: 0x18)
        data.writeUInt64(dictionaryAddress, at: 0x10)
        return data
    }

    private static func dictionaryData(entriesArrayAddress: UInt64) -> Data {
        var data = runtimeObjectData(count: 0x28)
        data.writeUInt64(entriesArrayAddress, at: 0x18)
        data.writeInt32(3, at: 0x20)
        return data
    }

    private static func saveDictionaryData(entriesArrayAddress: UInt64) -> Data {
        dictionaryData(entriesArrayAddress: entriesArrayAddress)
    }

    private static func entriesArrayData(fishDataAddress: UInt64, vegetableDataAddress: UInt64) -> Data {
        var data = runtimeObjectData(count: 0x68)
        data.writeUInt64(3, at: 0x18)
        data.writeInt32(1, at: 0x20)
        data.writeInt32(101, at: 0x28)
        data.writeUInt64(fishDataAddress, at: 0x30)
        data.writeInt32(1, at: 0x38)
        data.writeInt32(102, at: 0x40)
        data.writeUInt64(vegetableDataAddress, at: 0x48)
        data.writeInt32(-1, at: 0x50)
        return data
    }

    private static func saveEntriesArrayData(fishSaveAddress: UInt64, vegetableSaveAddress: UInt64) -> Data {
        var data = runtimeObjectData(count: 0x68)
        data.writeUInt64(3, at: 0x18)
        data.writeInt32(1, at: 0x20)
        data.writeInt32(101, at: 0x28)
        data.writeUInt64(fishSaveAddress, at: 0x30)
        data.writeInt32(1, at: 0x38)
        data.writeInt32(102, at: 0x40)
        data.writeUInt64(vegetableSaveAddress, at: 0x48)
        data.writeInt32(-1, at: 0x50)
        return data
    }

    private static func ingredientsData(
        id: Int32,
        type: Int32,
        countsAddress: UInt64,
        entityAddress: UInt64
    ) -> Data {
        var data = runtimeObjectData(count: 0x58)
        data.writeInt32(id, at: 0x10)
        data.writeInt32(type, at: 0x20)
        data.writeUInt64(countsAddress, at: 0x28)
        data.writeUInt64(entityAddress, at: 0x50)
        return data
    }

    private static func countsArrayData(count: Int32) -> Data {
        var data = runtimeObjectData(count: 0x24)
        data.writeUInt64(1, at: 0x18)
        data.writeInt32(count, at: 0x20)
        return data
    }

    private static func ingredientsSaveData(id: Int32, count: Int32) -> Data {
        var data = runtimeObjectData(count: 0x60)
        data.writeObscuredInt32(id, at: 0x10)
        data.writeObscuredInt32(count, at: 0x4C)
        return data
    }

    private static func entityData(type: Int32) -> Data {
        var data = runtimeObjectData(count: 0x18)
        data.writeInt32(type, at: 0x14)
        return data
    }

    private static func runtimeObjectData(count: Int) -> Data {
        var data = Data(count: count)
        data.writeUInt64(0x9_0000_0000, at: 0)
        data.writeUInt64(0, at: 0x8)
        return data
    }
}

private final class StaticIngredientsModuleResolver: GameAssemblyResolving {
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

private final class InMemoryIngredientsInventorySession: IngredientsInventoryMemorySession {
    let runtimeProcessID: Int32
    private let orderedBaseAddresses: [UInt64]
    private let ignoredWriteAddresses: Set<UInt64>
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
        self.segments = segments
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
    }

    func readInt32(address: UInt64) throws -> Int32 {
        let data = try read(MemoryReadRequest(address: address, size: MemoryLayout<Int32>.size))
        return data.testInt32(at: 0)
    }

    func readByte(address: UInt64) throws -> UInt8 {
        try read(MemoryReadRequest(address: address, size: 1))[0]
    }

    func readObscuredInt32(address: UInt64) throws -> Int32 {
        let data = try read(MemoryReadRequest(address: address, size: 0x14))
        guard let value = ObscuredInt32Value(data: data) else {
            throw TrainerError.memoryReadFailed("测试 ObscuredInt32 解码失败。")
        }
        return value.value
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
    mutating func writeInt32(_ value: Int32, at offset: Int) {
        let bytes = Swift.withUnsafeBytes(of: value.littleEndian) { Array($0) }
        replaceSubrange(offset..<(offset + bytes.count), with: bytes)
    }

    mutating func writeObscuredInt32(_ value: Int32, at offset: Int) {
        let obscured = ObscuredInt32Value(currentCryptoKey: 0x1357_2468, value: value)
        replaceSubrange(offset..<(offset + obscured.data.count), with: obscured.data)
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
