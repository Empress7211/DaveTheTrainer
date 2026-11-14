import XCTest
@testable import TrainerCore

final class JungleIngredientsInventoryIncrementerTests: XCTestCase {
    func testNullEntriesAreAcceptedOnlyForEmptyDictionariesWithoutWrites() throws {
        for layout in [DaveRuntimeLayout.v106675, .v106756] {
            for count in [Int32(0), 3] {
                let fixture = StaticJungleIngredientsFixture(storedDictionaryCount: count, layout: layout, nullEntries: true)
                let session = InMemoryJungleIngredientsSession(segments: fixture.segments)
                XCTAssertThrowsError(try JungleIngredientsInventoryIncrementer(moduleResolver: fixture.moduleResolver, layout: layout).increment(
                    JungleIngredientsInventoryIncrementRequest(delta: 1), session: session
                )) { error in
                    if count == 0 {
                        guard case TrainerError.targetMismatch = error else {
                            XCTFail("Empty inventory should report no existing items, got \(error)")
                            return
                        }
                    } else {
                        guard case TrainerError.memoryReadFailed = error else {
                            XCTFail("Nonempty dictionary must reject a null entries pointer, got \(error)")
                            return
                        }
                    }
                }
                XCTAssertEqual(session.writeCallCount, 0)
            }
        }
    }

    func testV106756JungleAndVillageScopesUseNewVillageDictionaryOffset() throws {
        for scope in [JungleDLCInventoryScope.ingredientsAndVillageItems, .villageItems] {
            let fixture = StaticJungleIngredientsFixture(layout: .v106756)
            let session = InMemoryJungleIngredientsSession(segments: fixture.segments)
            let result = try JungleIngredientsInventoryIncrementer(moduleResolver: fixture.moduleResolver, layout: .v106756).increment(
                JungleIngredientsInventoryIncrementRequest(delta: 99, scope: scope), session: session
            )
            XCTAssertEqual(result.updatedItemCount, scope == .villageItems ? 2 : 4)
            XCTAssertEqual(try session.readInt32(address: fixture.firstIngredientCountAddress), scope == .villageItems ? 10 : 109)
            XCTAssertEqual(try session.readInt32(address: fixture.secondIngredientCountAddress), scope == .villageItems ? 20 : 119)
            XCTAssertEqual(try session.readInt32(address: fixture.firstVillageItemCountAddress), 129)
            XCTAssertEqual(try session.readInt32(address: fixture.secondVillageItemCountAddress), 139)
            XCTAssertEqual(try session.readInt32(address: fixture.jungleInsectItemCountAddress), 50)
            XCTAssertEqual(session.regionsCallCount, 0)
        }
    }

    func testIncrementerIncrementsExistingJungleDLCInventoryDictionariesWithoutHeapScan() throws {
        let fixture = StaticJungleIngredientsFixture()
        let session = InMemoryJungleIngredientsSession(segments: fixture.segments)

        let result = try JungleIngredientsInventoryIncrementer(moduleResolver: fixture.moduleResolver).increment(
            JungleIngredientsInventoryIncrementRequest(delta: 99),
            session: session
        )

        XCTAssertEqual(result.updatedItemCount, 4)
        XCTAssertEqual(session.regionsCallCount, 0)
        XCTAssertEqual(try session.readInt32(address: fixture.firstIngredientCountAddress), 109)
        XCTAssertEqual(try session.readInt32(address: fixture.secondIngredientCountAddress), 119)
        XCTAssertEqual(try session.readInt32(address: fixture.firstVillageItemCountAddress), 129)
        XCTAssertEqual(try session.readInt32(address: fixture.secondVillageItemCountAddress), 139)
        XCTAssertEqual(try session.readInt32(address: fixture.jungleInsectItemCountAddress), 50)
    }

    func testSeaPeopleVillageExistingEntriesIncrementWithoutCreatingNewEntries() throws {
        let fixture = StaticJungleIngredientsFixture()
        let session = InMemoryJungleIngredientsSession(segments: fixture.segments)

        let result = try JungleIngredientsInventoryIncrementer(moduleResolver: fixture.moduleResolver).increment(
            JungleIngredientsInventoryIncrementRequest(delta: 99, scope: .villageItems),
            session: session
        )

        XCTAssertEqual(result.updatedItemCount, 2)
        XCTAssertEqual(session.regionsCallCount, 0)
        XCTAssertEqual(try session.readInt32(address: fixture.firstIngredientCountAddress), 10)
        XCTAssertEqual(try session.readInt32(address: fixture.secondIngredientCountAddress), 20)
        XCTAssertEqual(try session.readInt32(address: fixture.firstVillageItemCountAddress), 129)
        XCTAssertEqual(try session.readInt32(address: fixture.secondVillageItemCountAddress), 139)
        XCTAssertEqual(try session.readInt32(address: fixture.jungleInsectItemCountAddress), 50)
    }

    func testSeaPeopleVillageMissingEntryFailsLoud() throws {
        let fixture = StaticJungleIngredientsFixture(storedDictionaryCount: 0)
        let session = InMemoryJungleIngredientsSession(segments: fixture.segments)

        XCTAssertThrowsError(try JungleIngredientsInventoryIncrementer(moduleResolver: fixture.moduleResolver).increment(
            JungleIngredientsInventoryIncrementRequest(delta: 99, scope: .villageItems),
            session: session
        )) { error in
            guard case TrainerError.targetMismatch = error else {
                XCTFail("Expected targetMismatch, got \(error)")
                return
            }
        }
    }

    func testIncrementerThrowsVerifyFailedWhenJungleCountReadbackDoesNotChange() throws {
        let fixture = StaticJungleIngredientsFixture()
        let session = InMemoryJungleIngredientsSession(
            segments: fixture.segments,
            ignoredWriteAddresses: [fixture.firstIngredientCountAddress]
        )

        XCTAssertThrowsError(try JungleIngredientsInventoryIncrementer(moduleResolver: fixture.moduleResolver).increment(
            JungleIngredientsInventoryIncrementRequest(delta: 99),
            session: session
        )) { error in
            guard case TrainerError.verifyFailed = error else {
                XCTFail("Expected verifyFailed, got \(error)")
                return
            }
        }
    }

    func testIncrementerClampsNegativeJungleDLCInventoryDeltaToOneWithoutChangingInsects() throws {
        let fixture = StaticJungleIngredientsFixture()
        let session = InMemoryJungleIngredientsSession(segments: fixture.segments)

        let result = try JungleIngredientsInventoryIncrementer(moduleResolver: fixture.moduleResolver).increment(
            JungleIngredientsInventoryIncrementRequest(delta: -999),
            session: session
        )

        XCTAssertEqual(result.updatedItemCount, 4)
        XCTAssertEqual(session.regionsCallCount, 0)
        XCTAssertEqual(try session.readInt32(address: fixture.firstIngredientCountAddress), 1)
        XCTAssertEqual(try session.readInt32(address: fixture.secondIngredientCountAddress), 1)
        XCTAssertEqual(try session.readInt32(address: fixture.firstVillageItemCountAddress), 1)
        XCTAssertEqual(try session.readInt32(address: fixture.secondVillageItemCountAddress), 1)
        XCTAssertEqual(try session.readInt32(address: fixture.jungleInsectItemCountAddress), 50)
    }

    func testIncrementerDoesNotReadUnusedDictionaryCapacityAsJungleDLCItems() throws {
        let fixture = StaticJungleIngredientsFixture(
            storedDictionaryCount: 47,
            entriesArrayLength: 64,
            firstDefaultSlotIndex: 46
        )
        let session = InMemoryJungleIngredientsSession(segments: fixture.segments)

        let result = try JungleIngredientsInventoryIncrementer(moduleResolver: fixture.moduleResolver).increment(
            JungleIngredientsInventoryIncrementRequest(delta: 99),
            session: session
        )

        XCTAssertEqual(result.updatedItemCount, 4)
        XCTAssertEqual(session.regionsCallCount, 0)
        XCTAssertEqual(try session.readInt32(address: fixture.firstIngredientCountAddress), 109)
        XCTAssertEqual(try session.readInt32(address: fixture.secondIngredientCountAddress), 119)
        XCTAssertEqual(try session.readInt32(address: fixture.firstVillageItemCountAddress), 129)
        XCTAssertEqual(try session.readInt32(address: fixture.secondVillageItemCountAddress), 139)
        XCTAssertEqual(try session.readInt32(address: fixture.jungleInsectItemCountAddress), 50)
    }

    func testIncrementerInvalidatesResolvedJungleInventoryWhenProcessChanges() throws {
        let fixture = StaticJungleIngredientsFixture()
        let firstSession = InMemoryJungleIngredientsSession(segments: fixture.segments, runtimeProcessID: 100)
        let secondSession = InMemoryJungleIngredientsSession(segments: fixture.segments, runtimeProcessID: 200)
        let incrementer = JungleIngredientsInventoryIncrementer(moduleResolver: fixture.moduleResolver)

        _ = try incrementer.increment(JungleIngredientsInventoryIncrementRequest(delta: 9), session: firstSession)
        _ = try incrementer.increment(JungleIngredientsInventoryIncrementRequest(delta: 1), session: secondSession)

        XCTAssertEqual(fixture.moduleResolver.resolveCallCount, 2)
    }
}

private struct StaticJungleIngredientsFixture {
    let firstIngredientCountAddress: UInt64
    let secondIngredientCountAddress: UInt64
    let firstVillageItemCountAddress: UInt64
    let secondVillageItemCountAddress: UInt64
    let jungleInsectItemCountAddress: UInt64
    let moduleResolver: StaticJungleIngredientsModuleResolver
    let segments: [UInt64: Data]

    init(storedDictionaryCount: Int32 = 3, entriesArrayLength: Int = 4, firstDefaultSlotIndex: Int = 3, layout: DaveRuntimeLayout = .v106675, nullEntries: Bool = false) {
        let moduleBaseAddress = UInt64(0x1_0000_0000)
        let methodVariableAddress = moduleBaseAddress + layout.saveSystemInstanceMethodRVA
        let methodInfoAddress = UInt64(0x2_0000_0000)
        let genericContextAddress = UInt64(0x3_0000_0000)
        let genericClassAddress = UInt64(0x4_0000_0000)
        let saveSystemClassAddress = UInt64(0x5_0000_0000)
        let staticFieldsAddress = UInt64(0x6_0000_0000)
        let saveSystemAddress = UInt64(0x7_0000_0000)
        let gameDataManagerAddress = UInt64(0x7_1000_0000)
        let gameSaveAddress = UInt64(0x7_2000_0000)
        let playerInfoAddress = UInt64(0x7_3000_0000)
        let jungleSaveDataAddress = UInt64(0x7_4000_0000)
        let ingredientsDictionaryAddress = UInt64(0x7_5000_0000)
        let ingredientsEntriesArrayAddress = UInt64(0x7_6000_0000)
        let villageItemsDictionaryAddress = UInt64(0x7_7000_0000)
        let villageItemsEntriesArrayAddress = UInt64(0x7_8000_0000)
        let firstSaveAddress = UInt64(0x8_0000_0000)
        let secondSaveAddress = UInt64(0x8_1000_0000)
        let firstVillageItemAddress = UInt64(0x8_2000_0000)
        let secondVillageItemAddress = UInt64(0x8_3000_0000)
        let jungleInsectItemAddress = UInt64(0x8_4000_0000)

        self.firstIngredientCountAddress = firstSaveAddress + 0x14
        self.secondIngredientCountAddress = secondSaveAddress + 0x14
        self.firstVillageItemCountAddress = firstVillageItemAddress + 0x14
        self.secondVillageItemCountAddress = secondVillageItemAddress + 0x14
        self.jungleInsectItemCountAddress = jungleInsectItemAddress + 0x14
        self.moduleResolver = StaticJungleIngredientsModuleResolver(baseAddress: moduleBaseAddress)
        self.segments = [
            methodVariableAddress: Self.pointerData(methodInfoAddress),
            methodInfoAddress: Self.methodInfoData(genericContextAddress: genericContextAddress),
            genericContextAddress: Self.genericContextData(genericClassAddress: genericClassAddress),
            genericClassAddress: Self.genericClassData(classAddress: saveSystemClassAddress),
            saveSystemClassAddress: Self.saveSystemClassData(staticFieldsAddress: staticFieldsAddress),
            staticFieldsAddress: Self.staticFieldsData(saveSystemAddress: saveSystemAddress),
            saveSystemAddress: Self.saveSystemData(gameDataManagerAddress: gameDataManagerAddress),
            gameDataManagerAddress: Self.gameDataManagerData(gameSaveAddress: gameSaveAddress),
            gameSaveAddress: Self.gameSaveData(
                playerInfoAddress: playerInfoAddress,
                jungleSaveDataAddress: jungleSaveDataAddress,
                layout: layout
            ),
            playerInfoAddress: Self.runtimeObjectData(count: 0x18),
            jungleSaveDataAddress: Self.jungleSaveData(
                ingredientsDictionaryAddress: ingredientsDictionaryAddress,
                villageItemsDictionaryAddress: villageItemsDictionaryAddress,
                layout: layout
            ),
            ingredientsDictionaryAddress: Self.dictionaryData(
                entriesArrayAddress: nullEntries ? 0 : ingredientsEntriesArrayAddress,
                count: storedDictionaryCount
            ),
            ingredientsEntriesArrayAddress: Self.entriesArrayData(
                entries: [
                    DictionaryEntryFixture(key: 410210106, valueAddress: firstSaveAddress),
                    DictionaryEntryFixture(key: 410210111, valueAddress: secondSaveAddress)
                ],
                arrayLength: entriesArrayLength,
                firstDefaultSlotIndex: firstDefaultSlotIndex
            ),
            villageItemsDictionaryAddress: Self.dictionaryData(
                entriesArrayAddress: nullEntries ? 0 : villageItemsEntriesArrayAddress,
                count: storedDictionaryCount
            ),
            villageItemsEntriesArrayAddress: Self.entriesArrayData(
                entries: [
                    DictionaryEntryFixture(key: 41014101, valueAddress: firstVillageItemAddress),
                    DictionaryEntryFixture(key: 41014701, valueAddress: secondVillageItemAddress),
                    DictionaryEntryFixture(key: 41010317, valueAddress: jungleInsectItemAddress)
                ],
                arrayLength: entriesArrayLength,
                firstDefaultSlotIndex: firstDefaultSlotIndex
            ),
            firstSaveAddress: Self.jungleIngredientSaveData(tid: 410210106, count: 10),
            secondSaveAddress: Self.jungleIngredientSaveData(tid: 410210111, count: 20),
            firstVillageItemAddress: Self.jungleInventorySlotSaveData(tid: 41014101, count: 30),
            secondVillageItemAddress: Self.jungleInventorySlotSaveData(tid: 41014701, count: 40),
            jungleInsectItemAddress: Self.jungleInventorySlotSaveData(tid: 41010317, count: 50)
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

    private static func staticFieldsData(saveSystemAddress: UInt64) -> Data {
        var data = Data(count: 0x8)
        data.writeUInt64(saveSystemAddress, at: 0)
        return data
    }

    private static func saveSystemData(gameDataManagerAddress: UInt64) -> Data {
        var data = runtimeObjectData(count: 0x58)
        data.writeUInt64(gameDataManagerAddress, at: 0x50)
        return data
    }

    private static func gameDataManagerData(gameSaveAddress: UInt64) -> Data {
        var data = runtimeObjectData(count: 0x58)
        data.writeUInt64(gameSaveAddress, at: 0x50)
        return data
    }

    private static func gameSaveData(playerInfoAddress: UInt64, jungleSaveDataAddress: UInt64, layout: DaveRuntimeLayout) -> Data {
        var data = runtimeObjectData(count: Int(layout.saveDataJungleOffset) + 8)
        data.writeUInt64(playerInfoAddress, at: Int(layout.saveDataPlayerInfoOffset))
        data.writeUInt64(jungleSaveDataAddress, at: Int(layout.saveDataJungleOffset))
        return data
    }

    private static func jungleSaveData(ingredientsDictionaryAddress: UInt64, villageItemsDictionaryAddress: UInt64, layout: DaveRuntimeLayout) -> Data {
        var data = runtimeObjectData(count: Int(layout.jungleVillageItemsDictionaryOffset) + 8)
        data.writeUInt64(ingredientsDictionaryAddress, at: 0xA8)
        data.writeUInt64(villageItemsDictionaryAddress, at: Int(layout.jungleVillageItemsDictionaryOffset))
        return data
    }

    private static func dictionaryData(entriesArrayAddress: UInt64, count: Int32) -> Data {
        var data = runtimeObjectData(count: 0x28)
        data.writeUInt64(entriesArrayAddress, at: 0x18)
        data.writeInt32(count, at: 0x20)
        return data
    }

    private static func entriesArrayData(
        entries: [DictionaryEntryFixture],
        arrayLength: Int,
        firstDefaultSlotIndex: Int
    ) -> Data {
        var data = runtimeObjectData(count: 0x20 + arrayLength * 0x18)
        data.writeUInt64(UInt64(arrayLength), at: 0x18)

        for index in 0..<arrayLength {
            let offset = 0x20 + index * 0x18
            guard index < entries.count else {
                if index < firstDefaultSlotIndex {
                    data.writeInt32(-1, at: offset)
                }
                continue
            }

            let entry = entries[index]
            data.writeInt32(1, at: offset)
            data.writeInt32(entry.key, at: offset + 0x8)
            data.writeUInt64(entry.valueAddress, at: offset + 0x10)
        }
        return data
    }

    private static func jungleIngredientSaveData(tid: Int32, count: Int32) -> Data {
        var data = runtimeObjectData(count: 0x20)
        data.writeInt32(tid, at: 0x10)
        data.writeInt32(count, at: 0x14)
        return data
    }

    private static func jungleInventorySlotSaveData(tid: Int32, count: Int32) -> Data {
        var data = runtimeObjectData(count: 0x30)
        data.writeInt32(tid, at: 0x10)
        data.writeInt32(count, at: 0x14)
        return data
    }

    private static func runtimeObjectData(count: Int) -> Data {
        var data = Data(count: count)
        data.writeUInt64(0x9_0000_0000, at: 0)
        data.writeUInt64(0, at: 0x8)
        return data
    }
}

private struct DictionaryEntryFixture {
    let key: Int32
    let valueAddress: UInt64
}

private final class StaticJungleIngredientsModuleResolver: GameAssemblyResolving {
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

private final class InMemoryJungleIngredientsSession: JungleIngredientsInventoryMemorySession {
    let runtimeProcessID: Int32
    private let orderedBaseAddresses: [UInt64]
    private let ignoredWriteAddresses: Set<UInt64>
    private var segments: [UInt64: Data]
    private(set) var regionsCallCount = 0
    private(set) var writeCallCount = 0

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
        writeCallCount += 1
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
