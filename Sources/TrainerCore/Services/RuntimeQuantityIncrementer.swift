import Foundation

private let obscuredInt32ByteCount = 0x14
private let obscuredInt32KeyOffset = 0x0
private let obscuredInt32HiddenValueOffset = 0x4
private let obscuredInt32InitedOffset = 0x8
private let obscuredInt32FakeValueOffset = 0xC
private let obscuredInt32FakeValueActiveOffset = 0x10
private let playerInfoSaveObjectByteCount = 0x4C
private let playerInfoSaveGoldOffset = 0x10
private let playerInfoSaveBeiOffset = 0x24
private let playerInfoSaveChefFlameOffset = 0x38
private let saveDataJungleObjectByteCount = 0xD8
private let saveDataJungleCurrencyHolderPointerOffset = 0xD0
private let saveDataJungleCurrencyHolderByteCount = 0x18
private let saveDataJungleGoldOffset = 0x10
private let saveDataJungleChefFlameOffset = 0x14
private let runtimeMethodGenericContextOffset = UInt64(0x20)
private let runtimeGenericClassContainerOffset = UInt64(0xC0)
private let runtimeGenericClassTypeOffset = UInt64(0x10)
private let il2CppClassStaticFieldsOffset = UInt64(0xB8)
private let singletonInstanceStaticFieldOffset = UInt64(0x0)
private let saveSystemGameDataManagerOffset = UInt64(0x50)
private let saveSystemGameDataManagerDataOffset = UInt64(0x50)
private let runtimeObjectScanStride = 8
private let pointerByteCount = 8
private let pointerAlignment = UInt64(8)
private let minimumQuantityValue = Int32(0)
private let maximumReasonableQuantityValue = Int32(1_000_000_000)
private let mainChefFlameCacheKey = "artisan.main"
private let jungleChefFlameCacheKey = "artisan.jungle"

private struct RuntimeQuantityReadBackRequest {
    let address: UInt64
    let size: Int
    let descriptor: String
}

public struct ObscuredInt32Value: Equatable, Sendable {
    public let currentCryptoKey: Int32
    public let hiddenValue: Int32
    public let inited: Bool
    public let fakeValue: Int32
    public let fakeValueActive: Bool

    public var value: Int32 {
        hiddenValue ^ currentCryptoKey
    }

    public var data: Data {
        var result = Data(count: obscuredInt32ByteCount)
        result.replaceInt32(currentCryptoKey, at: obscuredInt32KeyOffset)
        result.replaceInt32(hiddenValue, at: obscuredInt32HiddenValueOffset)
        result.replaceBool(inited, at: obscuredInt32InitedOffset)
        result.replaceInt32(fakeValue, at: obscuredInt32FakeValueOffset)
        result.replaceBool(fakeValueActive, at: obscuredInt32FakeValueActiveOffset)
        return result
    }

    public init(
        currentCryptoKey: Int32,
        value: Int32,
        fakeValue: Int32? = nil,
        fakeValueActive: Bool = false
    ) {
        self.currentCryptoKey = currentCryptoKey
        self.hiddenValue = value ^ currentCryptoKey
        self.inited = true
        self.fakeValue = fakeValue ?? value
        self.fakeValueActive = fakeValueActive
    }

    public init?(data: Data, offset: Int = 0) {
        guard let currentCryptoKey = data.int32(at: offset + obscuredInt32KeyOffset) else {
            return nil
        }
        guard let hiddenValue = data.int32(at: offset + obscuredInt32HiddenValueOffset) else {
            return nil
        }
        guard let inited = data.bool(at: offset + obscuredInt32InitedOffset) else {
            return nil
        }
        guard let fakeValue = data.int32(at: offset + obscuredInt32FakeValueOffset) else {
            return nil
        }
        guard let fakeValueActive = data.bool(at: offset + obscuredInt32FakeValueActiveOffset) else {
            return nil
        }

        self.currentCryptoKey = currentCryptoKey
        self.hiddenValue = hiddenValue
        self.inited = inited
        self.fakeValue = fakeValue
        self.fakeValueActive = fakeValueActive
    }

    public func replacingValue(_ nextValue: Int32) -> ObscuredInt32Value {
        ObscuredInt32Value(
            currentCryptoKey: currentCryptoKey,
            value: nextValue,
            fakeValue: nextValue,
            fakeValueActive: fakeValueActive
        )
    }

    var isValidQuantity: Bool {
        guard inited else {
            return false
        }
        guard (minimumQuantityValue...maximumReasonableQuantityValue).contains(value) else {
            return false
        }
        return !fakeValueActive || fakeValue == value
    }
}

public struct PlayerInfoSaveObjectCandidate: Equatable, Sendable {
    public let objectAddress: UInt64
    public let goldAddress: UInt64
    public let beiAddress: UInt64
    public let chefFlameAddress: UInt64
    public let gold: Int32
    public let bei: Int32
    public let chefFlame: Int32

    public init(
        objectAddress: UInt64,
        goldAddress: UInt64,
        beiAddress: UInt64,
        chefFlameAddress: UInt64,
        gold: Int32,
        bei: Int32,
        chefFlame: Int32
    ) {
        self.objectAddress = objectAddress
        self.goldAddress = goldAddress
        self.beiAddress = beiAddress
        self.chefFlameAddress = chefFlameAddress
        self.gold = gold
        self.bei = bei
        self.chefFlame = chefFlame
    }
}

public struct PlayerInfoSaveObjectScanner {
    public init() {}

    public func candidates(in buffer: Data, baseAddress: UInt64) -> [PlayerInfoSaveObjectCandidate] {
        guard buffer.count >= playerInfoSaveObjectByteCount else {
            return []
        }

        let upperBound = buffer.count - playerInfoSaveObjectByteCount
        return stride(from: 0, through: upperBound, by: runtimeObjectScanStride).compactMap { offset in
            candidate(in: buffer, baseAddress: baseAddress, offset: offset)
        }
    }

    private func candidate(in buffer: Data, baseAddress: UInt64, offset: Int) -> PlayerInfoSaveObjectCandidate? {
        guard hasRuntimeObjectHeader(buffer, at: offset) else {
            return nil
        }
        guard let gold = validObscuredQuantity(in: buffer, at: offset + playerInfoSaveGoldOffset) else {
            return nil
        }
        guard let bei = validObscuredQuantity(in: buffer, at: offset + playerInfoSaveBeiOffset) else {
            return nil
        }
        guard let chefFlame = validObscuredQuantity(in: buffer, at: offset + playerInfoSaveChefFlameOffset) else {
            return nil
        }
        guard let objectOffset = UInt64(exactly: offset) else {
            return nil
        }

        let objectAddress = baseAddress + objectOffset
        return PlayerInfoSaveObjectCandidate(
            objectAddress: objectAddress,
            goldAddress: objectAddress + UInt64(playerInfoSaveGoldOffset),
            beiAddress: objectAddress + UInt64(playerInfoSaveBeiOffset),
            chefFlameAddress: objectAddress + UInt64(playerInfoSaveChefFlameOffset),
            gold: gold.value,
            bei: bei.value,
            chefFlame: chefFlame.value
        )
    }

    private func validObscuredQuantity(in buffer: Data, at offset: Int) -> ObscuredInt32Value? {
        guard let value = ObscuredInt32Value(data: buffer, offset: offset), value.isValidQuantity else {
            return nil
        }
        return value
    }
}

public struct SaveDataJungleObjectCandidate: Equatable, Sendable {
    public let objectAddress: UInt64
    public let jungleGoldAddress: UInt64
    public let jungleChefFlameAddress: UInt64
    public let jungleGold: Int32
    public let jungleChefFlame: Int32

    public init(
        objectAddress: UInt64,
        jungleGoldAddress: UInt64,
        jungleChefFlameAddress: UInt64,
        jungleGold: Int32,
        jungleChefFlame: Int32
    ) {
        self.objectAddress = objectAddress
        self.jungleGoldAddress = jungleGoldAddress
        self.jungleChefFlameAddress = jungleChefFlameAddress
        self.jungleGold = jungleGold
        self.jungleChefFlame = jungleChefFlame
    }
}

public struct SaveDataJungleObjectScanner {
    public init() {}

    public func candidates(in buffer: Data, baseAddress: UInt64) -> [SaveDataJungleObjectCandidate] {
        guard buffer.count >= saveDataJungleObjectByteCount else {
            return []
        }

        let upperBound = buffer.count - saveDataJungleObjectByteCount
        return stride(from: 0, through: upperBound, by: runtimeObjectScanStride).compactMap { offset in
            candidate(in: buffer, baseAddress: baseAddress, offset: offset)
        }
    }

    private func candidate(in buffer: Data, baseAddress: UInt64, offset: Int) -> SaveDataJungleObjectCandidate? {
        guard hasRuntimeObjectHeader(buffer, at: offset) else {
            return nil
        }
        guard let holderAddress = buffer.uint64(at: offset + saveDataJungleCurrencyHolderPointerOffset) else {
            return nil
        }
        guard holderAddress >= baseAddress, isAlignedPointer(holderAddress) else {
            return nil
        }
        guard let holderOffset = Int(exactly: holderAddress - baseAddress) else {
            return nil
        }
        guard holderOffset >= 0, holderOffset + saveDataJungleCurrencyHolderByteCount <= buffer.count else {
            return nil
        }
        guard hasRuntimeObjectHeader(buffer, at: holderOffset) else {
            return nil
        }
        guard let jungleGold = buffer.int32(at: holderOffset + saveDataJungleGoldOffset) else {
            return nil
        }
        guard (minimumQuantityValue...maximumReasonableQuantityValue).contains(jungleGold) else {
            return nil
        }
        guard let jungleChefFlame = buffer.int32(at: holderOffset + saveDataJungleChefFlameOffset) else {
            return nil
        }
        guard (minimumQuantityValue...maximumReasonableQuantityValue).contains(jungleChefFlame) else {
            return nil
        }
        guard let objectOffset = UInt64(exactly: offset) else {
            return nil
        }

        return SaveDataJungleObjectCandidate(
            objectAddress: baseAddress + objectOffset,
            jungleGoldAddress: holderAddress + UInt64(saveDataJungleGoldOffset),
            jungleChefFlameAddress: holderAddress + UInt64(saveDataJungleChefFlameOffset),
            jungleGold: jungleGold,
            jungleChefFlame: jungleChefFlame
        )
    }
}

public struct RuntimeQuantityIncrementRequest: Sendable, Equatable {
    public let featureID: String
    public let delta: Int64

    public init(featureID: String, delta: Int64) {
        self.featureID = featureID
        self.delta = delta
    }
}

public struct RuntimeQuantityIncrementResult: Sendable, Equatable {
    public let updatedAddressCount: Int

    public init(updatedAddressCount: Int) {
        self.updatedAddressCount = updatedAddressCount
    }
}

private struct CachedGameAssembly {
    let processID: Int32
    let module: LoadedMachOModule
}

public protocol RuntimeQuantityMemorySession: ModuleMemorySession {
    var runtimeProcessID: Int32 { get }

    func write(_ request: MemoryWriteRequest) throws
}

extension MemorySession: RuntimeQuantityMemorySession {}

public extension MemorySession {
    var runtimeProcessID: Int32 {
        process.pid
    }
}

public final class RuntimeQuantityIncrementer {
    private let layout: DaveRuntimeLayout
    private let moduleResolver: GameAssemblyResolving
    private var cachedFeatureAddresses: [RuntimeAddressCacheKey: Set<UInt64>] = [:]
    private var cachedGameAssembly: CachedGameAssembly?

    public init(
        moduleResolver: GameAssemblyResolving = MachOModuleResolver(),
        layout: DaveRuntimeLayout = .v106675
    ) {
        self.moduleResolver = moduleResolver
        self.layout = layout
    }

    public func clearCachedAddresses() {
        cachedFeatureAddresses.removeAll()
        cachedGameAssembly = nil
    }

    public func increment(
        _ request: RuntimeQuantityIncrementRequest,
        session: RuntimeQuantityMemorySession
    ) throws -> RuntimeQuantityIncrementResult {
        switch request.featureID {
        case "gold", "bei":
            return try incrementPlayerInfoSaveQuantity(request, session: session)
        case "artisan":
            return try incrementChefFlame(request, session: session)
        case "jungleGold":
            return try incrementJungleGold(request, session: session)
        default:
            throw TrainerError.addressNotCalibrated(featureID: request.featureID)
        }
    }

    private func incrementPlayerInfoSaveQuantity(
        _ request: RuntimeQuantityIncrementRequest,
        session: RuntimeQuantityMemorySession
    ) throws -> RuntimeQuantityIncrementResult {
        let module = try resolveGameAssembly(session: session)
        let cacheKey = makeCacheKey(featureID: request.featureID, module: module, session: session)
        if let cachedAddresses = cachedFeatureAddresses[cacheKey] {
            do {
                return try incrementCachedObscuredInt32Addresses(cachedAddresses, cacheKey: cacheKey, request: request, session: session)
            } catch {
                return try retryPlayerInfoSaveQuantityAfterCachedFailure(
                    error,
                    request: request,
                    session: session
                )
            }
        }

        let address = try resolvePlayerInfoSaveFieldAddress(featureID: request.featureID, module: module, session: session)
        try incrementObscuredInt32(address: address, delta: request.delta, session: session)
        cachedFeatureAddresses[cacheKey] = [address]
        return RuntimeQuantityIncrementResult(updatedAddressCount: 1)
    }

    private func incrementChefFlame(
        _ request: RuntimeQuantityIncrementRequest,
        session: RuntimeQuantityMemorySession
    ) throws -> RuntimeQuantityIncrementResult {
        let module = try resolveGameAssembly(session: session)
        if let cachedResult = try incrementCachedChefFlameAddresses(module: module, request: request, session: session) {
            return cachedResult
        }

        let mainAddress = try resolvePlayerInfoSaveFieldAddress(featureID: request.featureID, module: module, session: session)
        let jungleAddress = try resolveJunglePlainInt32Address(
            fieldOffset: saveDataJungleChefFlameOffset,
            descriptor: "丛林匠人火焰",
            module: module,
            session: session
        )
        try incrementObscuredInt32(address: mainAddress, delta: request.delta, session: session)
        try incrementPlainInt32(address: jungleAddress, delta: request.delta, session: session)

        cachedFeatureAddresses[makeCacheKey(featureID: mainChefFlameCacheKey, module: module, session: session)] = [mainAddress]
        cachedFeatureAddresses[makeCacheKey(featureID: jungleChefFlameCacheKey, module: module, session: session)] = [jungleAddress]
        return RuntimeQuantityIncrementResult(updatedAddressCount: 2)
    }

    private func incrementJungleGold(
        _ request: RuntimeQuantityIncrementRequest,
        session: RuntimeQuantityMemorySession
    ) throws -> RuntimeQuantityIncrementResult {
        let module = try resolveGameAssembly(session: session)
        let cacheKey = makeCacheKey(featureID: request.featureID, module: module, session: session)
        if let cachedAddresses = cachedFeatureAddresses[cacheKey] {
            do {
                return try incrementCachedPlainInt32Addresses(cachedAddresses, cacheKey: cacheKey, request: request, session: session)
            } catch {
                return try retryJungleGoldAfterCachedFailure(
                    error,
                    request: request,
                    session: session
                )
            }
        }

        let address = try resolveJunglePlainInt32Address(
            fieldOffset: saveDataJungleGoldOffset,
            descriptor: "丛林货币",
            module: module,
            session: session
        )
        try incrementPlainInt32(address: address, delta: request.delta, session: session)
        cachedFeatureAddresses[cacheKey] = [address]
        return RuntimeQuantityIncrementResult(updatedAddressCount: 1)
    }

    private func resolvePlayerInfoSaveFieldAddress(
        featureID: String,
        module: LoadedMachOModule,
        session: RuntimeQuantityMemorySession
    ) throws -> UInt64 {
        let saveData = try resolveSaveData(module: module, session: session)
        let playerInfoSave = try readAlignedPointer(
            address: saveData + layout.saveDataPlayerInfoOffset,
            context: "SaveData.playerInfo"
        ) { request in
            try session.read(request)
        }
        try validatePlayerInfoSave(address: playerInfoSave, session: session)
        return try playerInfoSaveFieldAddress(for: featureID, objectAddress: playerInfoSave)
    }

    private func resolveJunglePlainInt32Address(
        fieldOffset: Int,
        descriptor: String,
        module: LoadedMachOModule,
        session: RuntimeQuantityMemorySession
    ) throws -> UInt64 {
        let gameSave = try resolveSaveData(module: module, session: session)
        let jungleSaveData = try readAlignedPointer(
            address: gameSave + layout.saveDataJungleOffset,
            context: "GameSave.SaveDataJungle"
        ) { request in
            try session.read(request)
        }
        try validateRuntimeObjectHeader(address: jungleSaveData, session: session)

        let currencyHolder = try readAlignedPointer(
            address: jungleSaveData + UInt64(saveDataJungleCurrencyHolderPointerOffset),
            context: "SaveDataJungle.currencyHolder"
        ) { request in
            try session.read(request)
        }
        try validateRuntimeObjectHeader(address: currencyHolder, session: session)
        let address = currencyHolder + UInt64(fieldOffset)
        try validateJunglePlainInt32Address(address: address, descriptor: descriptor, session: session)
        return address
    }

    private func resolveGameAssembly(session: RuntimeQuantityMemorySession) throws -> LoadedMachOModule {
        let processID = processID(for: session)
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
        session: RuntimeQuantityMemorySession
    ) -> RuntimeAddressCacheKey {
        RuntimeAddressCacheKey(
            processID: processID(for: session),
            buildFingerprint: module.moduleIdentity,
            moduleBaseAddress: module.baseAddress,
            moduleIdentity: module.moduleIdentity,
            featureID: featureID
        )
    }

    private func retryPlayerInfoSaveQuantityAfterCachedFailure(
        _ error: Error,
        request: RuntimeQuantityIncrementRequest,
        session: RuntimeQuantityMemorySession
    ) throws -> RuntimeQuantityIncrementResult {
        guard Self.isRecoverableCachedAddressFailure(error) else {
            throw error
        }

        cachedGameAssembly = nil
        let module = try resolveGameAssembly(session: session)
        let address = try resolvePlayerInfoSaveFieldAddress(featureID: request.featureID, module: module, session: session)
        try incrementObscuredInt32(address: address, delta: request.delta, session: session)
        cachedFeatureAddresses[makeCacheKey(featureID: request.featureID, module: module, session: session)] = [address]
        return RuntimeQuantityIncrementResult(updatedAddressCount: 1)
    }

    private func retryJungleGoldAfterCachedFailure(
        _ error: Error,
        request: RuntimeQuantityIncrementRequest,
        session: RuntimeQuantityMemorySession
    ) throws -> RuntimeQuantityIncrementResult {
        guard Self.isRecoverableCachedAddressFailure(error) else {
            throw error
        }

        cachedGameAssembly = nil
        let module = try resolveGameAssembly(session: session)
        let address = try resolveJunglePlainInt32Address(
            fieldOffset: saveDataJungleGoldOffset,
            descriptor: "丛林货币",
            module: module,
            session: session
        )
        try incrementPlainInt32(address: address, delta: request.delta, session: session)
        cachedFeatureAddresses[makeCacheKey(featureID: request.featureID, module: module, session: session)] = [address]
        return RuntimeQuantityIncrementResult(updatedAddressCount: 1)
    }

    private func processID(for session: RuntimeQuantityMemorySession) -> Int32 {
        session.runtimeProcessID
    }

    private func resolveSaveData(
        module: LoadedMachOModule,
        session: RuntimeQuantityMemorySession
    ) throws -> UInt64 {
        var failures: [String] = []
        for methodRVA in [layout.saveSystemInstanceMethodRVA, layout.saveSystemHasInstanceMethodRVA] {
            do {
                let saveSystem = try resolveSingletonInstance(
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

    private func resolveSingletonInstance(
        methodVariableAddress: UInt64,
        session: RuntimeQuantityMemorySession
    ) throws -> UInt64 {
        let methodInfo = try readAlignedPointer(
            address: methodVariableAddress,
            context: "Singleton RuntimeMethod"
        ) { request in
            try session.read(request)
        }
        let genericContext = try readAlignedPointer(
            address: methodInfo + runtimeMethodGenericContextOffset,
            context: "Singleton RuntimeMethod generic context"
        ) { request in
            try session.read(request)
        }
        let classCandidates = try singletonClassCandidates(genericContext: genericContext, session: session)
        var failures: [String] = []

        for candidate in classCandidates {
            do {
                let staticFields = try readAlignedPointer(
                    address: candidate.address + il2CppClassStaticFieldsOffset,
                    context: "\(candidate.name).static_fields"
                ) { request in
                    try session.read(request)
                }
                let instance = try readAlignedPointer(
                    address: staticFields + singletonInstanceStaticFieldOffset,
                    context: "\(candidate.name).instance"
                ) { request in
                    try session.read(request)
                }
                try validateRuntimeObjectHeader(address: instance, session: session)
                return instance
            } catch {
                failures.append("\(candidate.name)=0x\(String(candidate.address, radix: 16)): \(error.localizedDescription)")
            }
        }

        throw TrainerError.invalidInput("Singleton 实例未解析：\(failures.joined(separator: "；"))")
    }

    private func singletonClassCandidates(
        genericContext: UInt64,
        session: RuntimeQuantityMemorySession
    ) throws -> [(name: String, address: UInt64)] {
        var candidates = [(name: "genericContext", address: genericContext)]
        let genericClass = try readAlignedPointer(
            address: genericContext + runtimeGenericClassContainerOffset,
            context: "Singleton generic class container"
        ) { request in
            try session.read(request)
        }
        let classFromGeneric = try readAlignedPointer(
            address: genericClass + runtimeGenericClassTypeOffset,
            context: "Singleton generic class type"
        ) { request in
            try session.read(request)
        }
        candidates.append((name: "genericContext.c0.10", address: classFromGeneric))
        return candidates
    }

    private func resolveSaveData(saveSystem: UInt64, session: RuntimeQuantityMemorySession) throws -> UInt64 {
        let gameDataManager = try readAlignedPointer(
            address: saveSystem + saveSystemGameDataManagerOffset,
            context: "SaveSystem.m_GameDataManager"
        ) { request in
            try session.read(request)
        }
        try validateRuntimeObjectHeader(address: gameDataManager, session: session)
        return try readAlignedPointer(
            address: gameDataManager + saveSystemGameDataManagerDataOffset,
            context: "SaveSystemGameDataManager.Data"
        ) { request in
            try session.read(request)
        }
    }

    private func validateSaveData(address: UInt64, session: RuntimeQuantityMemorySession) throws {
        try validateRuntimeObjectHeader(address: address, session: session)
        _ = try readAlignedPointer(
            address: address + layout.saveDataPlayerInfoOffset,
            context: "SaveData.playerInfo"
        ) { request in
            try session.read(request)
        }
    }

    private func validatePlayerInfoSave(address: UInt64, session: RuntimeQuantityMemorySession) throws {
        try validateRuntimeObjectHeader(address: address, session: session)
        let data = try session.read(MemoryReadRequest(address: address, size: playerInfoSaveObjectByteCount))
        guard PlayerInfoSaveObjectScanner().candidates(in: data, baseAddress: address).count == 1 else {
            throw TrainerError.memoryReadFailed("PlayerInfoSave 字段校验失败：0x\(String(address, radix: 16))。")
        }
    }

    private func validateJunglePlainInt32Address(
        address: UInt64,
        descriptor: String,
        session: RuntimeQuantityMemorySession
    ) throws {
        let data = try session.read(MemoryReadRequest(address: address, size: MemoryLayout<Int32>.size))
        guard let value = data.int32(at: 0), (minimumQuantityValue...maximumReasonableQuantityValue).contains(value) else {
            throw TrainerError.memoryReadFailed("\(descriptor)字段校验失败：0x\(String(address, radix: 16))。")
        }
    }

    private func validateRuntimeObjectHeader(address: UInt64, session: RuntimeQuantityMemorySession) throws {
        let data = try session.read(MemoryReadRequest(address: address, size: pointerByteCount * 2))
        guard hasRuntimeObjectHeader(data, at: 0) else {
            throw TrainerError.memoryReadFailed("运行时对象头校验失败：0x\(String(address, radix: 16))。")
        }
    }

    private func playerInfoSaveFieldAddress(for featureID: String, objectAddress: UInt64) throws -> UInt64 {
        switch featureID {
        case "gold":
            return objectAddress + UInt64(playerInfoSaveGoldOffset)
        case "bei":
            return objectAddress + UInt64(playerInfoSaveBeiOffset)
        case "artisan":
            return objectAddress + UInt64(playerInfoSaveChefFlameOffset)
        default:
            throw TrainerError.addressNotCalibrated(featureID: featureID)
        }
    }

    private func incrementCachedObscuredInt32Addresses(
        _ addresses: Set<UInt64>,
        cacheKey: RuntimeAddressCacheKey,
        request: RuntimeQuantityIncrementRequest,
        session: RuntimeQuantityMemorySession
    ) throws -> RuntimeQuantityIncrementResult {
        do {
            for address in addresses {
                try incrementObscuredInt32(address: address, delta: request.delta, session: session)
            }
            return RuntimeQuantityIncrementResult(updatedAddressCount: addresses.count)
        } catch {
            cachedFeatureAddresses[cacheKey] = nil
            throw error
        }
    }

    private func incrementCachedPlainInt32Addresses(
        _ addresses: Set<UInt64>,
        cacheKey: RuntimeAddressCacheKey,
        request: RuntimeQuantityIncrementRequest,
        session: RuntimeQuantityMemorySession
    ) throws -> RuntimeQuantityIncrementResult {
        do {
            for address in addresses {
                try incrementPlainInt32(address: address, delta: request.delta, session: session)
            }
            return RuntimeQuantityIncrementResult(updatedAddressCount: addresses.count)
        } catch {
            cachedFeatureAddresses[cacheKey] = nil
            throw error
        }
    }

    private func incrementCachedChefFlameAddresses(
        module: LoadedMachOModule,
        request: RuntimeQuantityIncrementRequest,
        session: RuntimeQuantityMemorySession
    ) throws -> RuntimeQuantityIncrementResult? {
        let mainKey = makeCacheKey(featureID: mainChefFlameCacheKey, module: module, session: session)
        let jungleKey = makeCacheKey(featureID: jungleChefFlameCacheKey, module: module, session: session)
        guard let mainAddresses = cachedFeatureAddresses[mainKey],
              let jungleAddresses = cachedFeatureAddresses[jungleKey] else {
            return nil
        }

        do {
            for address in mainAddresses {
                try incrementObscuredInt32(address: address, delta: request.delta, session: session)
            }
            for address in jungleAddresses {
                try incrementPlainInt32(address: address, delta: request.delta, session: session)
            }
            return RuntimeQuantityIncrementResult(updatedAddressCount: mainAddresses.count + jungleAddresses.count)
        } catch {
            cachedFeatureAddresses[mainKey] = nil
            cachedFeatureAddresses[jungleKey] = nil
            throw error
        }
    }

    private func incrementObscuredInt32(
        address: UInt64,
        delta: Int64,
        session: RuntimeQuantityMemorySession
    ) throws {
        let data = try session.read(MemoryReadRequest(address: address, size: obscuredInt32ByteCount))
        guard let current = ObscuredInt32Value(data: data), current.isValidQuantity else {
            throw TrainerError.memoryReadFailed("无法解码 ObscuredInt32 数量：0x\(String(address, radix: 16))。")
        }
        let nextValue = try incrementedInt32(current.value, delta: delta)
        let expected = current.replacingValue(nextValue).data
        try session.write(MemoryWriteRequest(address: address, data: expected))
        let verified = try readBackVerifiedBytes(
            RuntimeQuantityReadBackRequest(address: address, size: obscuredInt32ByteCount, descriptor: "ObscuredInt32"),
            session: session
        )
        guard verified == expected else {
            throw TrainerError.verifyFailed("ObscuredInt32 数量写后校验失败：0x\(String(address, radix: 16))。")
        }
    }

    private func incrementPlainInt32(
        address: UInt64,
        delta: Int64,
        session: RuntimeQuantityMemorySession
    ) throws {
        let data = try session.read(MemoryReadRequest(address: address, size: MemoryLayout<Int32>.size))
        guard let current = data.int32(at: 0) else {
            throw TrainerError.memoryReadFailed("无法读取 Int32 数量：0x\(String(address, radix: 16))。")
        }
        let nextValue = try incrementedInt32(current, delta: delta)
        let expected = Data(littleEndianBytes: nextValue.littleEndian)
        try session.write(MemoryWriteRequest(address: address, data: expected))
        let verified = try readBackVerifiedBytes(
            RuntimeQuantityReadBackRequest(address: address, size: MemoryLayout<Int32>.size, descriptor: "Int32"),
            session: session
        )
        guard verified == expected else {
            throw TrainerError.verifyFailed("Int32 数量写后校验失败：0x\(String(address, radix: 16))。")
        }
    }

    private func readBackVerifiedBytes(
        _ request: RuntimeQuantityReadBackRequest,
        session: RuntimeQuantityMemorySession
    ) throws -> Data {
        do {
            return try session.read(MemoryReadRequest(address: request.address, size: request.size))
        } catch {
            throw TrainerError.verifyFailed("\(request.descriptor) 数量写后读回失败：0x\(String(request.address, radix: 16))。\(error.localizedDescription)")
        }
    }

    private func incrementedInt32(_ current: Int32, delta: Int64) throws -> Int32 {
        try adjustedQuantity(
            current: current,
            delta: delta,
            overflowMessage: "数量增量结果越界。"
        )
    }

    private static func isRecoverableCachedAddressFailure(_ error: Error) -> Bool {
        if case TrainerError.memoryReadFailed = error {
            return true
        }
        return false
    }
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

private func readAlignedPointer(
    address: UInt64,
    context: String,
    read: (MemoryReadRequest) throws -> Data
) throws -> UInt64 {
    let data = try read(MemoryReadRequest(address: address, size: pointerByteCount))
    guard let pointer = data.uint64(at: 0), isAlignedPointer(pointer) else {
        throw TrainerError.memoryReadFailed("\(context) 指针无效：0x\(String(address, radix: 16))。")
    }
    return pointer
}

private func isAlignedPointer(_ value: UInt64) -> Bool {
    value != 0 && value.isMultiple(of: pointerAlignment)
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

    func bool(at offset: Int) -> Bool? {
        guard let byte = bytes(offset: offset, count: 1)?.first else {
            return nil
        }
        return byte != 0
    }

    mutating func replaceInt32(_ value: Int32, at offset: Int) {
        replaceSubrange(offset..<(offset + MemoryLayout<Int32>.size), with: Data(littleEndianBytes: value.littleEndian))
    }

    mutating func replaceBool(_ value: Bool, at offset: Int) {
        replaceSubrange(offset..<(offset + 1), with: [value ? 1 : 0])
    }
}
