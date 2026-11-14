import Foundation

private let jungleIngredientsRuntimeMethodGenericContextOffset = UInt64(0x20)
private let jungleIngredientsRuntimeGenericClassContainerOffset = UInt64(0xC0)
private let jungleIngredientsRuntimeGenericClassTypeOffset = UInt64(0x10)
private let jungleIngredientsClassStaticFieldsOffset = UInt64(0xB8)
private let jungleIngredientsSingletonInstanceStaticFieldOffset = UInt64(0x0)
private let jungleIngredientsSaveSystemGameDataManagerOffset = UInt64(0x50)
private let jungleIngredientsGameDataManagerDataOffset = UInt64(0x50)
private let jungleIngredientsSaveDictionaryOffset = UInt64(0xA8)
private let jungleIngredientsDictionaryEntriesOffset = UInt64(0x18)
private let jungleIngredientsDictionaryCountOffset = UInt64(0x20)
private let jungleIngredientsDictionaryEntryArrayDataOffset = 0x20
private let jungleIngredientsDictionaryEntryHashCodeOffset = 0x0
private let jungleIngredientsDictionaryEntryKeyOffset = 0x8
private let jungleIngredientsDictionaryEntryValueOffset = 0x10
private let jungleIngredientsDictionaryEntryStride = 0x18
private let jungleIngredientsArrayLengthOffset = 0x18
private let jungleIngredientsSaveObjectByteCount = 0x18
private let jungleIngredientsSaveTIDOffset = 0x10
private let jungleIngredientsSaveCountOffset = 0x14
private let jungleInventorySlotSaveObjectByteCount = 0x28
private let jungleInventorySlotSaveTIDOffset = 0x10
private let jungleInventorySlotSaveCountOffset = 0x14
private let jungleIngredientsPointerByteCount = 8
private let jungleIngredientsPointerAlignment = UInt64(8)
private let jungleBattleInsectItemIDPrefix = Int32(410103)
private let jungleItemIDPrefixDivisor = Int32(100)
private let maximumReasonableJungleIngredientEntryCount = 10_000
private let minimumJungleIngredientQuantity = Int32(0)
private let maximumReasonableJungleIngredientQuantity = Int32(1_000_000_000)

public enum JungleDLCInventoryScope: String, Sendable, Equatable {
    case ingredientsAndVillageItems
    case ingredients
    case villageItems
}

public struct JungleIngredientsInventoryIncrementRequest: Sendable, Equatable {
    public let delta: Int64
    public let scope: JungleDLCInventoryScope

    public init(delta: Int64, scope: JungleDLCInventoryScope = .ingredientsAndVillageItems) {
        self.delta = delta
        self.scope = scope
    }
}

public struct JungleIngredientsInventoryIncrementResult: Sendable, Equatable {
    public let updatedItemCount: Int

    public init(updatedItemCount: Int) {
        self.updatedItemCount = updatedItemCount
    }
}

private struct CachedGameAssembly {
    let processID: Int32
    let module: LoadedMachOModule
}

public protocol JungleIngredientsInventoryMemorySession: ModuleMemorySession {
    var runtimeProcessID: Int32 { get }

    func write(_ request: MemoryWriteRequest) throws
}

extension MemorySession: JungleIngredientsInventoryMemorySession {}

public final class JungleIngredientsInventoryIncrementer {
    private let layout: DaveRuntimeLayout
    private let moduleResolver: GameAssemblyResolving
    private var cachedGameAssembly: CachedGameAssembly?
    private var cachedDictionaryAddresses: [RuntimeAddressCacheKey: UInt64] = [:]

    public init(
        moduleResolver: GameAssemblyResolving = MachOModuleResolver(),
        layout: DaveRuntimeLayout = .v106675
    ) {
        self.moduleResolver = moduleResolver
        self.layout = layout
    }

    public func clearCachedAddresses() {
        cachedGameAssembly = nil
        cachedDictionaryAddresses.removeAll()
    }

    public func increment(
        _ request: JungleIngredientsInventoryIncrementRequest,
        session: JungleIngredientsInventoryMemorySession
    ) throws -> JungleIngredientsInventoryIncrementResult {
        let dictionaries = try resolveJungleDLCInventoryDictionaries(scope: request.scope, session: session)
        let entries = try dictionaries.flatMap { dictionary in
            try saveEntries(dictionary: dictionary, session: session)
        }
        var updatedAddresses = Set<UInt64>()

        for entry in entries {
            try incrementPlainInt32(address: entry.countAddress, delta: request.delta, session: session)
            updatedAddresses.insert(entry.countAddress)
        }

        guard !updatedAddresses.isEmpty else {
            throw TrainerError.targetMismatch("没有找到可增量修改的丛林DLC库存对象。请先进入丛林烧烤店/丛林库存界面并确保已有食材或材料后重试。")
        }
        return JungleIngredientsInventoryIncrementResult(updatedItemCount: updatedAddresses.count)
    }

    private func resolveJungleDLCInventoryDictionaries(
        scope: JungleDLCInventoryScope,
        session: JungleIngredientsInventoryMemorySession
    ) throws -> [JungleSaveDictionary] {
        let module = try resolveGameAssembly(session: session)
        let gameSave = try resolveGameSave(module: module, session: session)
        let jungleSaveData = try readAlignedPointer(
            address: gameSave + layout.saveDataJungleOffset,
            context: "GameSave.SaveDataJungle",
            session: session
        )
        try validateRuntimeObjectHeader(address: jungleSaveData, session: session)

        var dictionaries: [JungleSaveDictionary] = []

        if scope.includesIngredients {
            let ingredientsDictionary = try resolveJungleSaveDictionary(
                cacheKey: makeCacheKey(featureID: "jungle.ingredients.dictionary", module: module, session: session),
                address: jungleSaveData + jungleIngredientsSaveDictionaryOffset,
                descriptor: .ingredients,
                session: session
            )
            dictionaries.append(ingredientsDictionary)
        }

        if scope.includesVillageItems {
            let villageItemsDictionary = try resolveJungleSaveDictionary(
                cacheKey: makeCacheKey(featureID: "jungle.villageItems.dictionary", module: module, session: session),
                address: jungleSaveData + layout.jungleVillageItemsDictionaryOffset,
                descriptor: .villageItems,
                session: session
            )
            dictionaries.append(villageItemsDictionary)
        }

        return dictionaries
    }

    private func resolveJungleSaveDictionary(
        cacheKey: RuntimeAddressCacheKey,
        address: UInt64,
        descriptor: JungleSaveDictionaryDescriptor,
        session: JungleIngredientsInventoryMemorySession
    ) throws -> JungleSaveDictionary {
        if let cachedAddress = cachedDictionaryAddresses[cacheKey] {
            return JungleSaveDictionary(address: cachedAddress, descriptor: descriptor)
        }

        let dictionary = try readAlignedPointer(address: address, context: descriptor.context, session: session)
        try validateJungleSaveDictionary(address: dictionary, descriptor: descriptor, session: session)
        cachedDictionaryAddresses[cacheKey] = dictionary
        return JungleSaveDictionary(address: dictionary, descriptor: descriptor)
    }

    private func resolveGameAssembly(session: JungleIngredientsInventoryMemorySession) throws -> LoadedMachOModule {
        let processID = session.runtimeProcessID
        if let cachedGameAssembly,
           cachedGameAssembly.processID == processID {
            return cachedGameAssembly.module
        }

        let module = try moduleResolver.resolveGameAssembly(session: session)
        cachedGameAssembly = CachedGameAssembly(
            processID: processID,
            module: module
        )
        return module
    }

    private func makeCacheKey(
        featureID: String,
        module: LoadedMachOModule,
        session: JungleIngredientsInventoryMemorySession
    ) -> RuntimeAddressCacheKey {
        RuntimeAddressCacheKey(
            processID: session.runtimeProcessID,
            buildFingerprint: module.moduleIdentity,
            moduleBaseAddress: module.baseAddress,
            moduleIdentity: module.moduleIdentity,
            featureID: featureID
        )
    }

    private func resolveGameSave(
        module: LoadedMachOModule,
        session: JungleIngredientsInventoryMemorySession
    ) throws -> UInt64 {
        var failures: [String] = []
        let methodRVAs = [
            layout.saveSystemInstanceMethodRVA,
            layout.saveSystemHasInstanceMethodRVA
        ]
        for methodRVA in methodRVAs {
            do {
                let saveSystem = try resolveSingletonInstance(
                    methodVariableAddress: module.baseAddress + methodRVA,
                    session: session
                )
                let gameSave = try resolveGameSave(saveSystem: saveSystem, session: session)
                try validateGameSave(address: gameSave, session: session)
                return gameSave
            } catch {
                failures.append("0x\(String(methodRVA, radix: 16)): \(error.localizedDescription)")
            }
        }

        throw TrainerError.invalidInput("静态 SaveSystem 指针链未解析：\(failures.joined(separator: "；"))")
    }

    private func resolveSingletonInstance(
        methodVariableAddress: UInt64,
        session: JungleIngredientsInventoryMemorySession
    ) throws -> UInt64 {
        let methodInfo = try readAlignedPointer(address: methodVariableAddress, context: "Singleton RuntimeMethod", session: session)
        let genericContext = try readAlignedPointer(
            address: methodInfo + jungleIngredientsRuntimeMethodGenericContextOffset,
            context: "Singleton RuntimeMethod generic context",
            session: session
        )
        let classCandidates = try singletonClassCandidates(genericContext: genericContext, session: session)
        var failures: [String] = []

        for candidate in classCandidates {
            do {
                return try singletonInstance(classCandidate: candidate, session: session)
            } catch {
                failures.append("\(candidate.name)=0x\(String(candidate.address, radix: 16)): \(error.localizedDescription)")
            }
        }

        throw TrainerError.invalidInput("Singleton 实例未解析：\(failures.joined(separator: "；"))")
    }

    private func singletonClassCandidates(
        genericContext: UInt64,
        session: JungleIngredientsInventoryMemorySession
    ) throws -> [(name: String, address: UInt64)] {
        let genericClass = try readAlignedPointer(
            address: genericContext + jungleIngredientsRuntimeGenericClassContainerOffset,
            context: "Singleton generic class container",
            session: session
        )
        let classFromGeneric = try readAlignedPointer(
            address: genericClass + jungleIngredientsRuntimeGenericClassTypeOffset,
            context: "Singleton generic class type",
            session: session
        )
        return [(name: "genericContext", address: genericContext), (name: "genericContext.c0.10", address: classFromGeneric)]
    }

    private func singletonInstance(
        classCandidate: (name: String, address: UInt64),
        session: JungleIngredientsInventoryMemorySession
    ) throws -> UInt64 {
        let staticFields = try readAlignedPointer(
            address: classCandidate.address + jungleIngredientsClassStaticFieldsOffset,
            context: "\(classCandidate.name).static_fields",
            session: session
        )
        let instance = try readAlignedPointer(
            address: staticFields + jungleIngredientsSingletonInstanceStaticFieldOffset,
            context: "\(classCandidate.name).instance",
            session: session
        )
        try validateRuntimeObjectHeader(address: instance, session: session)
        return instance
    }

    private func resolveGameSave(
        saveSystem: UInt64,
        session: JungleIngredientsInventoryMemorySession
    ) throws -> UInt64 {
        let gameDataManager = try readAlignedPointer(
            address: saveSystem + jungleIngredientsSaveSystemGameDataManagerOffset,
            context: "SaveSystem.m_GameDataManager",
            session: session
        )
        try validateRuntimeObjectHeader(address: gameDataManager, session: session)
        return try readAlignedPointer(
            address: gameDataManager + jungleIngredientsGameDataManagerDataOffset,
            context: "SaveSystemGameDataManager.Data",
            session: session
        )
    }

    private func validateGameSave(address: UInt64, session: JungleIngredientsInventoryMemorySession) throws {
        try validateRuntimeObjectHeader(address: address, session: session)
        _ = try readAlignedPointer(
            address: address + layout.saveDataPlayerInfoOffset,
            context: "GameSave.playerInfo",
            session: session
        )
    }

    private func validateJungleSaveDictionary(
        address: UInt64,
        descriptor: JungleSaveDictionaryDescriptor,
        session: JungleIngredientsInventoryMemorySession
    ) throws {
        try validateRuntimeObjectHeader(address: address, session: session)
        // An empty managed Dictionary may have no allocated entries array.
        let dictionary = JungleSaveDictionary(address: address, descriptor: descriptor)
        guard try readDictionaryEntryCount(dictionary: dictionary, session: session) > 0 else {
            return
        }
        _ = try readAlignedPointer(
            address: address + jungleIngredientsDictionaryEntriesOffset,
            context: "\(descriptor.context).entries",
            session: session
        )
    }

    private func saveEntries(
        dictionary: JungleSaveDictionary,
        session: JungleIngredientsInventoryMemorySession
    ) throws -> [JungleIngredientSaveEntry] {
        let entryCount = try readDictionaryEntryCount(dictionary: dictionary, session: session)
        guard entryCount > 0 else {
            return []
        }

        let entriesArray = try readAlignedPointer(
            address: dictionary.address + jungleIngredientsDictionaryEntriesOffset,
            context: "\(dictionary.descriptor.context).entries",
            session: session
        )
        let entriesData = try readDictionaryEntriesData(
            entriesArrayAddress: entriesArray,
            entryCount: entryCount,
            descriptor: dictionary.descriptor,
            session: session
        )
        return try (0..<entryCount).compactMap { index in
            try saveEntry(
                entriesData: entriesData,
                index: index,
                descriptor: dictionary.descriptor,
                session: session
            )
        }
    }

    private func readDictionaryEntryCount(
        dictionary: JungleSaveDictionary,
        session: JungleIngredientsInventoryMemorySession
    ) throws -> Int {
        let headerSize = Int(jungleIngredientsDictionaryCountOffset) + MemoryLayout<Int32>.size
        let data = try session.read(MemoryReadRequest(address: dictionary.address, size: headerSize))
        guard let count = data.int32(at: Int(jungleIngredientsDictionaryCountOffset)) else {
            throw TrainerError.memoryReadFailed("无法读取\(dictionary.descriptor.title)字典数量：0x\(String(dictionary.address + jungleIngredientsDictionaryCountOffset, radix: 16))。")
        }
        guard (0...Int32(maximumReasonableJungleIngredientEntryCount)).contains(count) else {
            throw TrainerError.memoryReadFailed("\(dictionary.descriptor.title)字典数量异常：\(count)。")
        }
        return Int(count)
    }

    private func readDictionaryEntriesData(
        entriesArrayAddress: UInt64,
        entryCount: Int,
        descriptor: JungleSaveDictionaryDescriptor,
        session: JungleIngredientsInventoryMemorySession
    ) throws -> Data {
        let arrayHeader = try session.read(MemoryReadRequest(
            address: entriesArrayAddress,
            size: jungleIngredientsDictionaryEntryArrayDataOffset
        ))
        guard let arrayLength = arrayHeader.uint64(at: jungleIngredientsArrayLengthOffset) else {
            throw TrainerError.memoryReadFailed("无法读取\(descriptor.title)字典 entries 长度：0x\(String(entriesArrayAddress, radix: 16))。")
        }
        let maximumLength = UInt64(maximumReasonableJungleIngredientEntryCount)
        guard arrayLength >= UInt64(entryCount), arrayLength <= maximumLength else {
            throw TrainerError.memoryReadFailed("\(descriptor.title)字典 entries 长度异常：\(arrayLength)，count=\(entryCount)。")
        }
        let dataSize = jungleIngredientsDictionaryEntryArrayDataOffset + Int(arrayLength) * jungleIngredientsDictionaryEntryStride
        return try session.read(MemoryReadRequest(address: entriesArrayAddress, size: dataSize))
    }

    private func saveEntry(
        entriesData: Data,
        index: Int,
        descriptor: JungleSaveDictionaryDescriptor,
        session: JungleIngredientsInventoryMemorySession
    ) throws -> JungleIngredientSaveEntry? {
        let offset = jungleIngredientsDictionaryEntryArrayDataOffset + index * jungleIngredientsDictionaryEntryStride
        guard let hashCode = entriesData.int32(at: offset + jungleIngredientsDictionaryEntryHashCodeOffset), hashCode >= 0 else {
            return nil
        }
        guard let key = entriesData.int32(at: offset + jungleIngredientsDictionaryEntryKeyOffset),
              let objectAddress = entriesData.uint64(at: offset + jungleIngredientsDictionaryEntryValueOffset) else {
            throw TrainerError.memoryReadFailed("\(descriptor.title)字典 entry 读取失败：index=\(index)。")
        }
        guard key > 0 || objectAddress != 0 || hashCode != 0 else {
            return nil
        }
        guard key > 0 else {
            throw TrainerError.memoryReadFailed("\(descriptor.title)字典 key 无效：index=\(index)，key=\(key)。")
        }
        guard isAlignedPointer(objectAddress) else {
            throw TrainerError.memoryReadFailed("\(descriptor.title)字典 value 指针无效：index=\(index)。")
        }
        let entry = try validateJungleSave(address: objectAddress, descriptor: descriptor, session: session)
        guard entry.tid == key else {
            throw TrainerError.memoryReadFailed("\(descriptor.title)字典 key 与保存对象 TID 不匹配：key=\(key)，tid=\(entry.tid)。")
        }
        guard shouldIncrementJungleSave(tid: entry.tid, descriptor: descriptor) else {
            return nil
        }
        return entry
    }

    private func validateJungleSave(
        address: UInt64,
        descriptor: JungleSaveDictionaryDescriptor,
        session: JungleIngredientsInventoryMemorySession
    ) throws -> JungleIngredientSaveEntry {
        let data = try session.read(MemoryReadRequest(address: address, size: descriptor.objectByteCount))
        guard hasRuntimeObjectHeader(data, at: 0) else {
            throw TrainerError.memoryReadFailed("\(descriptor.title)保存对象头校验失败：0x\(String(address, radix: 16))。")
        }
        guard let tid = data.int32(at: descriptor.tidOffset), tid > 0 else {
            throw TrainerError.memoryReadFailed("\(descriptor.title) TID 字段无效：0x\(String(address + UInt64(descriptor.tidOffset), radix: 16))。")
        }
        guard let count = data.int32(at: descriptor.countOffset), isValidQuantity(count) else {
            throw TrainerError.memoryReadFailed("\(descriptor.title)数量字段无效：0x\(String(address + UInt64(descriptor.countOffset), radix: 16))。")
        }
        return JungleIngredientSaveEntry(
            objectAddress: address,
            tid: tid,
            countAddress: address + UInt64(descriptor.countOffset)
        )
    }

    private func incrementPlainInt32(
        address: UInt64,
        delta: Int64,
        session: JungleIngredientsInventoryMemorySession
    ) throws {
        let data = try session.read(MemoryReadRequest(address: address, size: MemoryLayout<Int32>.size))
        guard let current = data.int32(at: 0), isValidQuantity(current) else {
            throw TrainerError.memoryReadFailed("无法读取丛林DLC库存数量：0x\(String(address, radix: 16))。")
        }
        let nextValue = try incrementedInt32(current, delta: delta)
        let expected = Data(littleEndianBytes: nextValue.littleEndian)
        try session.write(MemoryWriteRequest(address: address, data: expected))
        let verified = try session.read(MemoryReadRequest(address: address, size: MemoryLayout<Int32>.size))
        guard verified == expected else {
            throw TrainerError.verifyFailed("丛林DLC库存数量写后校验失败：0x\(String(address, radix: 16))。")
        }
    }

    private func incrementedInt32(_ current: Int32, delta: Int64) throws -> Int32 {
        let next = try adjustedQuantity(
            current: current,
            delta: delta,
            overflowMessage: "丛林DLC库存数量增量结果越界。"
        )
        guard isValidQuantity(next) else {
            throw TrainerError.invalidInput("丛林DLC库存数量增量结果越界。")
        }
        return next
    }

    private func readAlignedPointer(
        address: UInt64,
        context: String,
        session: JungleIngredientsInventoryMemorySession
    ) throws -> UInt64 {
        let data = try session.read(MemoryReadRequest(address: address, size: jungleIngredientsPointerByteCount))
        guard let pointer = data.uint64(at: 0), isAlignedPointer(pointer) else {
            throw TrainerError.memoryReadFailed("\(context) 指针无效：0x\(String(address, radix: 16))。")
        }
        return pointer
    }

    private func validateRuntimeObjectHeader(address: UInt64, session: JungleIngredientsInventoryMemorySession) throws {
        let data = try session.read(MemoryReadRequest(address: address, size: jungleIngredientsPointerByteCount * 2))
        guard hasRuntimeObjectHeader(data, at: 0) else {
            throw TrainerError.memoryReadFailed("运行时对象头校验失败：0x\(String(address, radix: 16))。")
        }
    }
}

private struct JungleSaveDictionary: Equatable, Sendable {
    let address: UInt64
    let descriptor: JungleSaveDictionaryDescriptor
}

private struct JungleSaveDictionaryDescriptor: Equatable, Sendable {
    let title: String
    let context: String
    let objectByteCount: Int
    let tidOffset: Int
    let countOffset: Int

    static let ingredients = JungleSaveDictionaryDescriptor(
        title: "丛林食材",
        context: "SaveDataJungle.JungleIngredientsSave",
        objectByteCount: jungleIngredientsSaveObjectByteCount,
        tidOffset: jungleIngredientsSaveTIDOffset,
        countOffset: jungleIngredientsSaveCountOffset
    )

    static let villageItems = JungleSaveDictionaryDescriptor(
        title: "丛林DLC物品/材料",
        context: "SaveDataJungle.IvenData",
        objectByteCount: jungleInventorySlotSaveObjectByteCount,
        tidOffset: jungleInventorySlotSaveTIDOffset,
        countOffset: jungleInventorySlotSaveCountOffset
    )
}

private struct JungleIngredientSaveEntry: Equatable, Sendable {
    let objectAddress: UInt64
    let tid: Int32
    let countAddress: UInt64
}

private func hasRuntimeObjectHeader(_ data: Data, at offset: Int) -> Bool {
    guard let classPointer = data.uint64(at: offset), isAlignedPointer(classPointer) else {
        return false
    }
    guard let monitorPointer = data.uint64(at: offset + jungleIngredientsPointerByteCount) else {
        return false
    }
    return monitorPointer == 0 || isAlignedPointer(monitorPointer)
}

private func isValidQuantity(_ value: Int32) -> Bool {
    (minimumJungleIngredientQuantity...maximumReasonableJungleIngredientQuantity).contains(value)
}

private func shouldIncrementJungleSave(tid: Int32, descriptor: JungleSaveDictionaryDescriptor) -> Bool {
    guard descriptor == .villageItems else {
        return true
    }
    return tid / jungleItemIDPrefixDivisor != jungleBattleInsectItemIDPrefix
}

private extension JungleDLCInventoryScope {
    var includesIngredients: Bool {
        self == .ingredientsAndVillageItems || self == .ingredients
    }

    var includesVillageItems: Bool {
        self == .ingredientsAndVillageItems || self == .villageItems
    }
}

private func isAlignedPointer(_ value: UInt64) -> Bool {
    value != 0 && value.isMultiple(of: jungleIngredientsPointerAlignment)
}

private extension Data {
    func int32(at offset: Int) -> Int32? {
        guard let bytes = bytes(offset: offset, count: MemoryLayout<Int32>.size) else {
            return nil
        }
        return Int32(littleEndianBytes: bytes)
    }

    func uint64(at offset: Int) -> UInt64? {
        guard let bytes = bytes(offset: offset, count: MemoryLayout<UInt64>.size) else {
            return nil
        }
        return UInt64(littleEndianBytes: bytes)
    }
}
