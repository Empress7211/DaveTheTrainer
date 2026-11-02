import Foundation

private let ingredientsObjectScanStride = 8
private let ingredientsDataObjectByteCount = 0x58
private let ingredientsObscuredInt32ByteCount = 0x14
private let ingredientsIDOffset = 0x10
private let ingredientsTypeOffset = 0x20
private let ingredientsCountsPointerOffset = 0x28
private let ingredientsEntityPointerOffset = 0x50
private let ingredientsEntityTypeOffset = 0x14
private let ingredientsCountsLengthOffset = 0x18
private let ingredientsPrimaryCountOffset = 0x20
private let ingredientsSaveObjectByteCount = 0x60
private let ingredientsSaveIDOffset = 0x10
private let ingredientsSaveCountOffset = 0x4C
private let pointerAlignment = UInt64(8)
private let pointerByteCount = 8
private let saveSystemGameDataManagerOffset = UInt64(0x50)
private let saveSystemGameDataManagerDataOffset = UInt64(0x50)
private let saveDataDirtyFlagOffset = UInt64(0x29)
private let firstFishIngredientsType = Int32(0)
private let lastFishIngredientsType = Int32(1)
private let vegetableIngredientsType = Int32(2)
private let seasoningIngredientsType = Int32(3)
private let upgradeMaterialsType = Int32(4)
private let runtimeMethodGenericContextOffset = UInt64(0x20)
private let runtimeGenericClassContainerOffset = UInt64(0xC0)
private let runtimeGenericClassTypeOffset = UInt64(0x10)
private let il2CppClassStaticFieldsOffset = UInt64(0xB8)
private let singletonInstanceStaticFieldOffset = UInt64(0x0)
private let ingredientsStorageDictionaryOffset = UInt64(0x10)
private let dictionaryEntriesOffset = UInt64(0x18)
private let dictionaryCountOffset = UInt64(0x20)
private let dictionaryEntryArrayDataOffset = 0x20
private let dictionaryEntryHashCodeOffset = 0x0
private let dictionaryEntryKeyOffset = 0x8
private let dictionaryEntryValueOffset = 0x10
private let dictionaryEntryStride = 0x18
private let maximumReasonableIngredientsEntryCount = 10_000
private let maximumReportedMissingIngredientIDCount = 12

public enum IngredientsInventoryScope: Sendable, Equatable {
    case all
    case fish
    case vegetable
    case seasoning
    case upgrade

    func matches(_ ingredientsType: Int32) -> Bool {
        switch self {
        case .all:
            return (firstFishIngredientsType...upgradeMaterialsType).contains(ingredientsType)
        case .fish:
            return (firstFishIngredientsType...lastFishIngredientsType).contains(ingredientsType)
        case .vegetable:
            return ingredientsType == vegetableIngredientsType
        case .seasoning:
            return ingredientsType == seasoningIngredientsType
        case .upgrade:
            return ingredientsType == upgradeMaterialsType
        }
    }
}

public struct IngredientsInventoryObjectCandidate: Equatable, Sendable {
    public let objectAddress: UInt64
    public let ingredientsID: Int32
    public let countsAddress: UInt64
    public let entityAddress: UInt64
    public let ingredientsType: Int32

    public init(
        objectAddress: UInt64,
        ingredientsID: Int32,
        countsAddress: UInt64,
        entityAddress: UInt64,
        ingredientsType: Int32
    ) {
        self.objectAddress = objectAddress
        self.ingredientsID = ingredientsID
        self.countsAddress = countsAddress
        self.entityAddress = entityAddress
        self.ingredientsType = ingredientsType
    }
}

public struct IngredientsInventoryIncrementRequest: Sendable {
    public let scope: IngredientsInventoryScope
    public let delta: Int64

    public init(scope: IngredientsInventoryScope, delta: Int64) {
        self.scope = scope
        self.delta = delta
    }
}

public struct IngredientsInventoryIncrementResult: Sendable, Equatable {
    public let updatedItemCount: Int

    public init(updatedItemCount: Int) {
        self.updatedItemCount = updatedItemCount
    }
}

public struct IngredientsInventoryObjectScanner {
    public init() {}

    public func candidates(in buffer: Data, baseAddress: UInt64, scope: IngredientsInventoryScope) -> [IngredientsInventoryObjectCandidate] {
        guard buffer.count >= ingredientsDataObjectByteCount else {
            return []
        }

        let upperBound = buffer.count - ingredientsDataObjectByteCount
        return stride(from: 0, through: upperBound, by: ingredientsObjectScanStride).compactMap { offset in
            candidate(in: buffer, baseAddress: baseAddress, offset: offset, scope: scope)
        }
    }

    private func candidate(
        in buffer: Data,
        baseAddress: UInt64,
        offset: Int,
        scope: IngredientsInventoryScope
    ) -> IngredientsInventoryObjectCandidate? {
        guard let ingredientsID = buffer.int32(at: offset + ingredientsIDOffset), ingredientsID > 0 else {
            return nil
        }
        guard let ingredientsType = buffer.int32(at: offset + ingredientsTypeOffset), scope.matches(ingredientsType) else {
            return nil
        }
        guard let countsAddress = buffer.uint64(at: offset + ingredientsCountsPointerOffset), isAlignedPointer(countsAddress) else {
            return nil
        }
        guard let entityAddress = buffer.uint64(at: offset + ingredientsEntityPointerOffset), isAlignedPointer(entityAddress) else {
            return nil
        }
        guard let objectOffset = UInt64(exactly: offset) else {
            return nil
        }

        return IngredientsInventoryObjectCandidate(
            objectAddress: baseAddress + objectOffset,
            ingredientsID: ingredientsID,
            countsAddress: countsAddress,
            entityAddress: entityAddress,
            ingredientsType: ingredientsType
        )
    }

}

private struct CachedGameAssembly {
    let processID: Int32
    let module: LoadedMachOModule
}

public protocol IngredientsInventoryMemorySession: ModuleMemorySession {
    var runtimeProcessID: Int32 { get }

    func write(_ request: MemoryWriteRequest) throws
}

extension MemorySession: IngredientsInventoryMemorySession {}

public final class IngredientsInventoryIncrementer {
    private let scanner: IngredientsInventoryObjectScanner
    private let layout: DaveRuntimeLayout
    private let moduleResolver: GameAssemblyResolving
    private var cachedGameAssembly: CachedGameAssembly?
    private var cachedStorageAddresses: [RuntimeAddressCacheKey: UInt64] = [:]
    private var cachedSaveDataAddresses: [RuntimeAddressCacheKey: UInt64] = [:]
    private var cachedIngredientsSaveDictionaryAddresses: [RuntimeAddressCacheKey: UInt64] = [:]

    public init(
        scanner: IngredientsInventoryObjectScanner = IngredientsInventoryObjectScanner(),
        moduleResolver: GameAssemblyResolving = MachOModuleResolver(),
        layout: DaveRuntimeLayout = .v106675
    ) {
        self.scanner = scanner
        self.moduleResolver = moduleResolver
        self.layout = layout
    }

    public func clearCachedAddresses() {
        cachedGameAssembly = nil
        cachedStorageAddresses.removeAll()
        cachedSaveDataAddresses.removeAll()
        cachedIngredientsSaveDictionaryAddresses.removeAll()
    }

    public func increment(
        _ request: IngredientsInventoryIncrementRequest,
        session: IngredientsInventoryMemorySession
    ) throws -> IngredientsInventoryIncrementResult {
        let storage = try resolveIngredientsStorage(session: session)
        let candidates = try validatedRuntimeCandidates(storageAddress: storage, scope: request.scope, session: session)

        guard !candidates.isEmpty else {
            throw TrainerError.invalidInput("没有找到可增量修改的食材/素材对象。请先进入游戏存档并打开背包/寿司店相关界面后重试。")
        }

        let ingredientsIDs = Set(candidates.map(\.ingredientsID))
        let saveEntries = try matchingMainSaveEntries(ingredientsIDs: ingredientsIDs, session: session)
        let saveIngredientsIDs = Set(saveEntries.entries.map(\.ingredientsID))
        let missingIngredientsIDs = ingredientsIDs.subtracting(saveIngredientsIDs)

        guard missingIngredientsIDs.isEmpty else {
            throw TrainerError.memoryReadFailed("主存档 IngredientsSave 缺少运行时食材ID：\(formattedIngredientsIDs(missingIngredientsIDs))。")
        }

        for candidate in candidates {
            try incrementPrimaryCount(countsAddress: candidate.countsAddress, delta: request.delta, session: session)
        }
        for entry in saveEntries.entries {
            try incrementIngredientsSaveCount(countAddress: entry.countAddress, delta: request.delta, session: session)
        }
        try markIngredientsSaveDirty(saveDataAddress: saveEntries.saveDataAddress, session: session)

        return IngredientsInventoryIncrementResult(updatedItemCount: ingredientsIDs.count)
    }

    private func resolveIngredientsStorage(session: IngredientsInventoryMemorySession) throws -> UInt64 {
        let module = try resolveGameAssembly(session: session)
        let cacheKey = makeCacheKey(featureID: "ingredients.storage", module: module, session: session)
        if let cachedStorageAddress = cachedStorageAddresses[cacheKey] {
            return cachedStorageAddress
        }

        var failures: [String] = []
        for methodRVA in [layout.ingredientsInstanceMethodRVA, layout.ingredientsConstructorMethodRVA] {
            do {
                let storage = try resolveSingletonInstance(
                    methodVariableAddress: module.baseAddress + methodRVA,
                    session: session
                )
                try validateIngredientsStorage(address: storage, session: session)
                cachedStorageAddresses[cacheKey] = storage
                return storage
            } catch {
                failures.append("0x\(String(methodRVA, radix: 16)): \(error.localizedDescription)")
            }
        }

        throw TrainerError.invalidInput("静态 IngredientsStorage 指针链未解析：\(failures.joined(separator: "；"))")
    }

    private func resolveGameAssembly(session: IngredientsInventoryMemorySession) throws -> LoadedMachOModule {
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

    private func validatedRuntimeCandidates(
        storageAddress: UInt64,
        scope: IngredientsInventoryScope,
        session: IngredientsInventoryMemorySession
    ) throws -> [IngredientsInventoryObjectCandidate] {
        let candidates = try dictionaryCandidates(storageAddress: storageAddress, scope: scope, session: session)
        var validatedCandidates: [IngredientsInventoryObjectCandidate] = []
        var countsAddresses = Set<UInt64>()

        for candidate in candidates {
            guard !countsAddresses.contains(candidate.countsAddress) else {
                continue
            }
            guard try isValid(candidate, session: session) else {
                continue
            }

            countsAddresses.insert(candidate.countsAddress)
            validatedCandidates.append(candidate)
        }

        return validatedCandidates
    }

    private func matchingMainSaveEntries(
        ingredientsIDs: Set<Int32>,
        session: IngredientsInventoryMemorySession
    ) throws -> MainSaveIngredientsEntries {
        let dictionary = try resolveMainSaveIngredientsDictionary(session: session)
        let entries = try ingredientsSaveEntries(
            dictionaryAddress: dictionary.dictionaryAddress,
            ingredientsIDs: ingredientsIDs,
            session: session
        )
        return MainSaveIngredientsEntries(saveDataAddress: dictionary.saveDataAddress, entries: entries)
    }

    private func resolveMainSaveIngredientsDictionary(
        session: IngredientsInventoryMemorySession
    ) throws -> MainSaveIngredientsDictionary {
        let module = try resolveGameAssembly(session: session)
        let saveDataKey = makeCacheKey(featureID: "ingredients.saveData", module: module, session: session)
        let dictionaryKey = makeCacheKey(featureID: "ingredients.saveDictionary", module: module, session: session)
        if let cachedSaveDataAddress = cachedSaveDataAddresses[saveDataKey],
           let cachedIngredientsSaveDictionaryAddress = cachedIngredientsSaveDictionaryAddresses[dictionaryKey] {
            return MainSaveIngredientsDictionary(
                saveDataAddress: cachedSaveDataAddress,
                dictionaryAddress: cachedIngredientsSaveDictionaryAddress
            )
        }

        let saveData = try resolveSaveData(module: module, session: session)
        let dictionary = try readAlignedPointer(
            address: saveData + layout.saveDataIngredientsDictionaryOffset,
            context: "SaveData.IngredientsData",
            session: session
        )
        try validateRuntimeObjectHeader(address: dictionary, session: session)

        cachedSaveDataAddresses[saveDataKey] = saveData
        cachedIngredientsSaveDictionaryAddresses[dictionaryKey] = dictionary
        return MainSaveIngredientsDictionary(saveDataAddress: saveData, dictionaryAddress: dictionary)
    }

    private func makeCacheKey(
        featureID: String,
        module: LoadedMachOModule,
        session: IngredientsInventoryMemorySession
    ) -> RuntimeAddressCacheKey {
        RuntimeAddressCacheKey(
            processID: session.runtimeProcessID,
            buildFingerprint: module.moduleIdentity,
            moduleBaseAddress: module.baseAddress,
            moduleIdentity: module.moduleIdentity,
            featureID: featureID
        )
    }

    private func resolveSaveData(
        module: LoadedMachOModule,
        session: IngredientsInventoryMemorySession
    ) throws -> UInt64 {
        var failures: [String] = []
        for methodRVA in [layout.saveSystemInstanceMethodRVA, layout.saveSystemHasInstanceMethodRVA] {
            do {
                let saveSystem = try resolveSaveSystemInstance(
                    methodVariableAddress: module.baseAddress + methodRVA,
                    session: session
                )
                let saveData = try resolveSaveData(saveSystem: saveSystem, session: session)
                try validateSaveData(address: saveData, session: session)
                return saveData
            } catch {
                failures.append("0x\(String(methodRVA, radix: 16)): \(error.localizedDescription)")
            }
        }

        throw TrainerError.invalidInput("静态 SaveSystem 指针链未解析：\(failures.joined(separator: "；"))")
    }

    private func resolveSaveSystemInstance(
        methodVariableAddress: UInt64,
        session: IngredientsInventoryMemorySession
    ) throws -> UInt64 {
        let methodInfo = try readAlignedPointer(address: methodVariableAddress, context: "Singleton RuntimeMethod", session: session)
        let genericContext = try readAlignedPointer(
            address: methodInfo + runtimeMethodGenericContextOffset,
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
        session: IngredientsInventoryMemorySession
    ) throws -> [(name: String, address: UInt64)] {
        let genericClass = try readAlignedPointer(
            address: genericContext + runtimeGenericClassContainerOffset,
            context: "Singleton generic class container",
            session: session
        )
        let classFromGeneric = try readAlignedPointer(
            address: genericClass + runtimeGenericClassTypeOffset,
            context: "Singleton generic class type",
            session: session
        )
        return [(name: "genericContext", address: genericContext), (name: "genericContext.c0.10", address: classFromGeneric)]
    }

    private func singletonInstance(
        classCandidate: (name: String, address: UInt64),
        session: IngredientsInventoryMemorySession
    ) throws -> UInt64 {
        let staticFields = try readAlignedPointer(
            address: classCandidate.address + il2CppClassStaticFieldsOffset,
            context: "\(classCandidate.name).static_fields",
            session: session
        )
        let instance = try readAlignedPointer(
            address: staticFields + singletonInstanceStaticFieldOffset,
            context: "\(classCandidate.name).instance",
            session: session
        )
        try validateRuntimeObjectHeader(address: instance, session: session)
        return instance
    }

    private func resolveSaveData(
        saveSystem: UInt64,
        session: IngredientsInventoryMemorySession
    ) throws -> UInt64 {
        let gameDataManager = try readAlignedPointer(
            address: saveSystem + saveSystemGameDataManagerOffset,
            context: "SaveSystem.m_GameDataManager",
            session: session
        )
        try validateRuntimeObjectHeader(address: gameDataManager, session: session)
        return try readAlignedPointer(
            address: gameDataManager + saveSystemGameDataManagerDataOffset,
            context: "SaveSystemGameDataManager.Data",
            session: session
        )
    }

    private func validateSaveData(address: UInt64, session: IngredientsInventoryMemorySession) throws {
        try validateRuntimeObjectHeader(address: address, session: session)
        _ = try readAlignedPointer(address: address + layout.saveDataPlayerInfoOffset, context: "SaveData.playerInfo", session: session)
        _ = try readAlignedPointer(
            address: address + layout.saveDataIngredientsDictionaryOffset,
            context: "SaveData.IngredientsData",
            session: session
        )
    }

    private func resolveSingletonInstance(
        methodVariableAddress: UInt64,
        session: IngredientsInventoryMemorySession
    ) throws -> UInt64 {
        let methodInfo = try readAlignedPointer(
            address: methodVariableAddress,
            context: "SingletonNoMono RuntimeMethod",
            session: session
        )
        let genericContext = try readAlignedPointer(
            address: methodInfo + runtimeMethodGenericContextOffset,
            context: "SingletonNoMono RuntimeMethod generic context",
            session: session
        )
        let genericClass = try readAlignedPointer(
            address: genericContext + runtimeGenericClassContainerOffset,
            context: "SingletonNoMono generic class container",
            session: session
        )
        let singletonClass = try readAlignedPointer(
            address: genericClass + runtimeGenericClassTypeOffset,
            context: "SingletonNoMono generic class type",
            session: session
        )
        let staticFields = try readAlignedPointer(
            address: singletonClass + il2CppClassStaticFieldsOffset,
            context: "SingletonNoMono.static_fields",
            session: session
        )
        let instance = try readAlignedPointer(
            address: staticFields + singletonInstanceStaticFieldOffset,
            context: "SingletonNoMono.s_Instance",
            session: session
        )
        try validateRuntimeObjectHeader(address: instance, session: session)
        return instance
    }

    private func validateIngredientsStorage(
        address: UInt64,
        session: IngredientsInventoryMemorySession
    ) throws {
        try validateRuntimeObjectHeader(address: address, session: session)
        let dictionary = try readAlignedPointer(
            address: address + ingredientsStorageDictionaryOffset,
            context: "IngredientsStorage.dictionary",
            session: session
        )
        try validateRuntimeObjectHeader(address: dictionary, session: session)
    }

    private func dictionaryCandidates(
        storageAddress: UInt64,
        scope: IngredientsInventoryScope,
        session: IngredientsInventoryMemorySession
    ) throws -> [IngredientsInventoryObjectCandidate] {
        let dictionary = try readAlignedPointer(
            address: storageAddress + ingredientsStorageDictionaryOffset,
            context: "IngredientsStorage.dictionary",
            session: session
        )
        let entriesArray = try readAlignedPointer(
            address: dictionary + dictionaryEntriesOffset,
            context: "IngredientsStorage.dictionary.entries",
            session: session
        )
        let dictionaryHeader = try session.read(MemoryReadRequest(address: dictionary, size: Int(dictionaryCountOffset) + MemoryLayout<Int32>.size))
        guard let entryCount = dictionaryHeader.int32(at: Int(dictionaryCountOffset)) else {
            throw TrainerError.memoryReadFailed("无法读取食材字典数量：0x\(String(dictionary + dictionaryCountOffset, radix: 16))。")
        }
        let entryCountValue = Int(entryCount)
        guard (0...maximumReasonableIngredientsEntryCount).contains(entryCountValue) else {
            throw TrainerError.memoryReadFailed("食材字典数量异常：\(entryCount)。")
        }

        let arrayHeader = try session.read(MemoryReadRequest(address: entriesArray, size: dictionaryEntryArrayDataOffset))
        guard let arrayLength = arrayHeader.uint64(at: ingredientsCountsLengthOffset) else {
            throw TrainerError.memoryReadFailed("无法读取食材字典 entries 长度：0x\(String(entriesArray, radix: 16))。")
        }
        guard arrayLength >= UInt64(entryCountValue), arrayLength <= UInt64(maximumReasonableIngredientsEntryCount) else {
            throw TrainerError.memoryReadFailed("食材字典 entries 长度异常：\(arrayLength)，count=\(entryCount)。")
        }

        let entryBytes = dictionaryEntryArrayDataOffset + Int(arrayLength) * dictionaryEntryStride
        let entriesData = try session.read(MemoryReadRequest(address: entriesArray, size: entryBytes))
        var candidates: [IngredientsInventoryObjectCandidate] = []
        for index in 0..<Int(arrayLength) {
            let offset = dictionaryEntryArrayDataOffset + index * dictionaryEntryStride
            guard let hashCode = entriesData.int32(at: offset + dictionaryEntryHashCodeOffset), hashCode >= 0 else {
                continue
            }
            guard let key = entriesData.int32(at: offset + dictionaryEntryKeyOffset), key > 0 else {
                continue
            }
            guard let dataAddress = entriesData.uint64(at: offset + dictionaryEntryValueOffset), isAlignedPointer(dataAddress) else {
                continue
            }
            guard let candidate = try candidate(dataAddress: dataAddress, scope: scope, session: session) else {
                continue
            }
            candidates.append(candidate)
        }
        return candidates
    }

    private func ingredientsSaveEntries(
        dictionaryAddress: UInt64,
        ingredientsIDs: Set<Int32>,
        session: IngredientsInventoryMemorySession
    ) throws -> [IngredientsSaveEntry] {
        guard !ingredientsIDs.isEmpty else {
            return []
        }

        let entriesData = try dictionaryEntriesData(dictionaryAddress: dictionaryAddress, session: session)
        var entries: [IngredientsSaveEntry] = []

        for index in 0..<entriesData.arrayLength {
            let offset = dictionaryEntryArrayDataOffset + index * dictionaryEntryStride
            guard isLiveDictionaryEntry(entriesData.data, offset: offset) else {
                continue
            }
            guard let key = entriesData.data.int32(at: offset + dictionaryEntryKeyOffset), ingredientsIDs.contains(key) else {
                continue
            }
            guard let valueAddress = entriesData.data.uint64(at: offset + dictionaryEntryValueOffset), isAlignedPointer(valueAddress) else {
                continue
            }
            guard let entry = try ingredientsSaveEntry(ingredientsID: key, objectAddress: valueAddress, session: session) else {
                continue
            }
            entries.append(entry)
        }

        return entries
    }

    private func dictionaryEntriesData(
        dictionaryAddress: UInt64,
        session: IngredientsInventoryMemorySession
    ) throws -> DictionaryEntriesData {
        let entriesArray = try readAlignedPointer(
            address: dictionaryAddress + dictionaryEntriesOffset,
            context: "Dictionary.entries",
            session: session
        )
        let dictionaryHeaderSize = Int(dictionaryCountOffset) + MemoryLayout<Int32>.size
        let dictionaryHeader = try session.read(MemoryReadRequest(address: dictionaryAddress, size: dictionaryHeaderSize))
        guard let entryCount = dictionaryHeader.int32(at: Int(dictionaryCountOffset)) else {
            throw TrainerError.memoryReadFailed("无法读取食材存档字典数量：0x\(String(dictionaryAddress + dictionaryCountOffset, radix: 16))。")
        }
        let entryCountValue = Int(entryCount)
        guard (0...maximumReasonableIngredientsEntryCount).contains(entryCountValue) else {
            throw TrainerError.memoryReadFailed("食材存档字典数量异常：\(entryCount)。")
        }

        let arrayHeader = try session.read(MemoryReadRequest(address: entriesArray, size: dictionaryEntryArrayDataOffset))
        guard let arrayLength = arrayHeader.uint64(at: ingredientsCountsLengthOffset) else {
            throw TrainerError.memoryReadFailed("无法读取食材存档字典 entries 长度：0x\(String(entriesArray, radix: 16))。")
        }
        guard arrayLength >= UInt64(entryCountValue), arrayLength <= UInt64(maximumReasonableIngredientsEntryCount) else {
            throw TrainerError.memoryReadFailed("食材存档字典 entries 长度异常：\(arrayLength)，count=\(entryCount)。")
        }

        let arrayLengthValue = Int(arrayLength)
        let entryBytes = dictionaryEntryArrayDataOffset + arrayLengthValue * dictionaryEntryStride
        let data = try session.read(MemoryReadRequest(address: entriesArray, size: entryBytes))
        return DictionaryEntriesData(data: data, arrayLength: arrayLengthValue)
    }

    private func ingredientsSaveEntry(
        ingredientsID: Int32,
        objectAddress: UInt64,
        session: IngredientsInventoryMemorySession
    ) throws -> IngredientsSaveEntry? {
        try validateRuntimeObjectHeader(address: objectAddress, session: session)
        let data = try session.read(MemoryReadRequest(address: objectAddress, size: ingredientsSaveObjectByteCount))
        guard let storedID = ObscuredInt32Value(data: data, offset: ingredientsSaveIDOffset), storedID.value == ingredientsID else {
            return nil
        }
        guard let count = ObscuredInt32Value(data: data, offset: ingredientsSaveCountOffset), count.isValidQuantity else {
            return nil
        }
        return IngredientsSaveEntry(
            ingredientsID: ingredientsID,
            countAddress: objectAddress + UInt64(ingredientsSaveCountOffset)
        )
    }

    private func candidate(
        dataAddress: UInt64,
        scope: IngredientsInventoryScope,
        session: IngredientsInventoryMemorySession
    ) throws -> IngredientsInventoryObjectCandidate? {
        try validateRuntimeObjectHeader(address: dataAddress, session: session)
        let data = try session.read(MemoryReadRequest(address: dataAddress, size: ingredientsDataObjectByteCount))
        return scanner.candidates(in: data, baseAddress: dataAddress, scope: scope).first
    }

    private func isValid(_ candidate: IngredientsInventoryObjectCandidate, session: IngredientsInventoryMemorySession) throws -> Bool {
        let entity = try session.read(MemoryReadRequest(address: candidate.entityAddress, size: ingredientsEntityTypeOffset + MemoryLayout<Int32>.size))
        guard entity.int32(at: ingredientsEntityTypeOffset) == candidate.ingredientsType else {
            return false
        }

        let countsHeaderSize = ingredientsPrimaryCountOffset + MemoryLayout<Int32>.size
        let counts = try session.read(MemoryReadRequest(address: candidate.countsAddress, size: countsHeaderSize))
        guard let length = counts.uint64(at: ingredientsCountsLengthOffset), length > 0 else {
            return false
        }
        guard let current = counts.int32(at: ingredientsPrimaryCountOffset), current >= 0 else {
            return false
        }
        return true
    }

    private func incrementPrimaryCount(countsAddress: UInt64, delta: Int64, session: IngredientsInventoryMemorySession) throws {
        let countAddress = countsAddress + UInt64(ingredientsPrimaryCountOffset)
        let data = try session.read(MemoryReadRequest(address: countAddress, size: MemoryLayout<Int32>.size))
        guard let current = data.int32(at: 0) else {
            throw TrainerError.memoryReadFailed("无法读取食材数量：0x\(String(countAddress, radix: 16))。")
        }

        let next = try incrementedInt32(current, delta: delta)
        let expected = Data(littleEndianBytes: next.littleEndian)

        try session.write(MemoryWriteRequest(address: countAddress, data: expected))
        let verified = try session.read(MemoryReadRequest(address: countAddress, size: MemoryLayout<Int32>.size))
        guard verified == expected else {
            throw TrainerError.verifyFailed("食材运行时数量写后校验失败：0x\(String(countAddress, radix: 16))。")
        }
    }

    private func incrementIngredientsSaveCount(
        countAddress: UInt64,
        delta: Int64,
        session: IngredientsInventoryMemorySession
    ) throws {
        let data = try session.read(MemoryReadRequest(address: countAddress, size: ingredientsObscuredInt32ByteCount))
        guard let current = ObscuredInt32Value(data: data), current.isValidQuantity else {
            throw TrainerError.memoryReadFailed("无法解码 IngredientsSave.Count：0x\(String(countAddress, radix: 16))。")
        }

        let next = try incrementedInt32(current.value, delta: delta)
        let expected = current.replacingValue(next).data
        try session.write(MemoryWriteRequest(address: countAddress, data: expected))
        let verified = try session.read(MemoryReadRequest(address: countAddress, size: ingredientsObscuredInt32ByteCount))
        guard verified == expected else {
            throw TrainerError.verifyFailed("IngredientsSave.Count 写后校验失败：0x\(String(countAddress, radix: 16))。")
        }
    }

    private func markIngredientsSaveDirty(saveDataAddress: UInt64, session: IngredientsInventoryMemorySession) throws {
        let address = saveDataAddress + saveDataDirtyFlagOffset
        let expected = Data([1])
        try session.write(MemoryWriteRequest(address: address, data: expected))
        let verified = try session.read(MemoryReadRequest(address: address, size: expected.count))
        guard verified == expected else {
            throw TrainerError.verifyFailed("SaveData dirty flag 写后校验失败：0x\(String(address, radix: 16))。")
        }
    }

    private func incrementedInt32(_ current: Int32, delta: Int64) throws -> Int32 {
        try adjustedQuantity(
            current: current,
            delta: delta,
            overflowMessage: "食材数量增量结果越界。"
        )
    }

    private func readAlignedPointer(
        address: UInt64,
        context: String,
        session: IngredientsInventoryMemorySession
    ) throws -> UInt64 {
        let data = try session.read(MemoryReadRequest(address: address, size: pointerByteCount))
        guard let pointer = data.uint64(at: 0), isAlignedPointer(pointer) else {
            throw TrainerError.memoryReadFailed("\(context) 指针无效：0x\(String(address, radix: 16))。")
        }
        return pointer
    }

    private func validateRuntimeObjectHeader(address: UInt64, session: IngredientsInventoryMemorySession) throws {
        let data = try session.read(MemoryReadRequest(address: address, size: pointerByteCount * 2))
        guard hasRuntimeObjectHeader(data, at: 0) else {
            throw TrainerError.memoryReadFailed("运行时对象头校验失败：0x\(String(address, radix: 16))。")
        }
    }
}

private struct MainSaveIngredientsDictionary {
    let saveDataAddress: UInt64
    let dictionaryAddress: UInt64
}

private struct MainSaveIngredientsEntries {
    let saveDataAddress: UInt64
    let entries: [IngredientsSaveEntry]
}

private struct IngredientsSaveEntry {
    let ingredientsID: Int32
    let countAddress: UInt64
}

private struct DictionaryEntriesData {
    let data: Data
    let arrayLength: Int
}

private func hasRuntimeObjectHeader(_ data: Data, at offset: Int) -> Bool {
    guard let classPointer = data.uint64(at: offset), isAlignedPointer(classPointer) else {
        return false
    }
    guard let monitorPointer = data.uint64(at: offset + pointerByteCount) else {
        return false
    }
    return monitorPointer == 0 || isAlignedPointer(monitorPointer)
}

private func isAlignedPointer(_ value: UInt64) -> Bool {
    value != 0 && value.isMultiple(of: pointerAlignment)
}

private func isLiveDictionaryEntry(_ data: Data, offset: Int) -> Bool {
    guard let hashCode = data.int32(at: offset + dictionaryEntryHashCodeOffset) else {
        return false
    }
    return hashCode >= 0
}

private func formattedIngredientsIDs(_ ids: Set<Int32>) -> String {
    let sortedIDs = ids.sorted()
    let visibleIDs = sortedIDs.prefix(maximumReportedMissingIngredientIDCount).map(String.init)
    let suffix = sortedIDs.count > maximumReportedMissingIngredientIDCount ? "..." : ""
    return (visibleIDs + [suffix]).filter { !$0.isEmpty }.joined(separator: ", ")
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
