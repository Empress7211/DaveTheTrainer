import AppKit
import Darwin
import Foundation
import TrainerCore
import UniformTypeIdentifiers

private let freezeIntervalSeconds = 0.25
private let defaultSetValueText = "999999"
private let defaultFloatFreezeText = "999.0"
private let adminLogFilePrefix = "DaveTheTrainer-admin"
private let osascriptPath = "/usr/bin/osascript"

private enum StaticLocateOutcome: Sendable {
    case success(Il2CppStaticLocationReport)
    case failure(String)
}

private enum CompatibilityReportExportOutcome: Sendable {
    case success(fileName: String, patchPointCount: Int)
    case failure(String)
}

private struct PlayerOperationApplyConfig {
    let request: SimpleTrainerActionRequest
    let payload: TrainerOperationPayload
    let patchIDs: Set<String>
}

private actor QuantityOperationWorker {
    private let trainerOperationService: TrainerOperationService

    init(trainerOperationService: TrainerOperationService) {
        self.trainerOperationService = trainerOperationService
    }

    func clearRuntimeCaches() {
        trainerOperationService.clearRuntimeCaches()
    }

    func apply(
        _ request: TrainerOperationRequest,
        context: TrainerOperationContext
    ) throws -> DaveTrainerOperationResult {
        try trainerOperationService.apply(request, context: context)
    }
}

@MainActor
final class AppStore: ObservableObject {
    struct Dependencies {
        struct Runtime {
            let memoryAccess: MemoryAccess
            let trainerOperationService: TrainerOperationService
            let compatibilityReportGenerator: any DaveCompatibilityReportGenerating

            init(
                memoryAccess: MemoryAccess = MachMemoryAccess(),
                trainerOperationService: TrainerOperationService = TrainerOperationService(),
                compatibilityReportGenerator: any DaveCompatibilityReportGenerating = DaveCompatibilityReportGenerator()
            ) {
                self.memoryAccess = memoryAccess
                self.trainerOperationService = trainerOperationService
                self.compatibilityReportGenerator = compatibilityReportGenerator
            }
        }

        let installResolver: GameInstallResolving
        let processResolver: ProcessResolving
        let runtime: Runtime

        init(
            installResolver: GameInstallResolving = GameInstallResolver(),
            processResolver: ProcessResolving = LibProcProcessResolver(),
            runtime: Runtime = Runtime()
        ) {
            self.installResolver = installResolver
            self.processResolver = processResolver
            self.runtime = runtime
        }
    }

    @Published var selectedSection: NavigationSection = .status
    @Published private(set) var install: GameInstall?
    @Published private(set) var targetProcess: TargetProcess?
    @Published private(set) var isAttached = false
    @Published private(set) var features = DefaultTrainerFeatures.make(requiredBuild: KnownGameBuild.current)
    @Published private(set) var addressBook = AddressBook.empty(build: KnownGameBuild.current)
    @Published private(set) var saveSnapshots: [SaveFileSnapshot] = []
    @Published private(set) var scanCandidates: [ScanCandidate] = []
    @Published private(set) var scanFailures: [ProcessScanFailure] = []
    @Published private(set) var frozenFeatureIDs: Set<String> = []
    @Published private(set) var enabledPatchIDs: Set<String> = []
    @Published private(set) var staticLocationReport: Il2CppStaticLocationReport?
    @Published private(set) var latestOperationResult: DaveTrainerOperationResult?
    @Published private(set) var latestMessage = "尚未操作。"
    @Published private(set) var latestMessageIsError = false
    @Published private(set) var isBusy = false
    @Published private(set) var logs: [String] = []
    @Published var calibrationFeatureID = "gold"
    // Session-only consent; every launch starts with experimental writes gated.
    @Published var allowExperimentalFeatures = false

    var showsExperimentalControls: Bool {
        install?.signature.matchesIdentity(of: KnownGameBuild.v106756) == true
    }

    var isRunningAsAdministrator: Bool {
        geteuid() == 0
    }

    private let installResolver: GameInstallResolving
    private let processResolver: ProcessResolving
    private let memoryAccess: MemoryAccess
    private let addressStore: AddressBookStore?
    private let addressStoreInitializationError: String?
    private let backupService: SaveBackupService
    private let scanner: ProcessMemoryScanner
    private let writer: FeatureWriter
    private let quantityWorker: QuantityOperationWorker
    private let staticFeatureLocator: Il2CppStaticFeatureLocator
    private let trainerOperationService: TrainerOperationService
    private let compatibilityReportGenerator: any DaveCompatibilityReportGenerating
    private var session: MemorySession?
    private var freezeTimers: [String: Timer] = [:]
    private var hasRequestedAdministratorRelaunch = false

    init(dependencies: Dependencies = Dependencies()) {
        self.installResolver = dependencies.installResolver
        self.processResolver = dependencies.processResolver
        self.memoryAccess = dependencies.runtime.memoryAccess
        do {
            self.addressStore = try AddressBookStore()
            self.addressStoreInitializationError = nil
        } catch {
            self.addressStore = nil
            self.addressStoreInitializationError = error.localizedDescription
        }
        self.backupService = SaveBackupService()
        self.scanner = ProcessMemoryScanner()
        self.writer = FeatureWriter()
        self.quantityWorker = QuantityOperationWorker(trainerOperationService: dependencies.runtime.trainerOperationService)
        self.staticFeatureLocator = Il2CppStaticFeatureLocator()
        self.trainerOperationService = dependencies.runtime.trainerOperationService
        self.compatibilityReportGenerator = dependencies.runtime.compatibilityReportGenerator
        refreshAll()
    }

    func refreshAll() {
        refreshGameContext()
        refreshAddressBook()
        refreshSaves()
    }

    func refreshInstall() {
        do {
            let resolvedInstall: GameInstall
            if let targetProcess {
                resolvedInstall = try installResolver.resolveRunningGame(targetProcess)
            } else {
                resolvedInstall = try installResolver.resolveInstalledGame()
            }
            install = resolvedInstall
            features = DefaultTrainerFeatures.make(requiredBuild: resolvedInstall.signature)
            if let summary = trainerOperationService.profileSummary(for: resolvedInstall.signature) {
                log(summary)
                return
            }
            log("已识别 Dave 安装：\(resolvedInstall.signature.version) / \(resolvedInstall.signature.buildGUID)。当前构建没有已验证补丁 profile，玩家写入已禁用；请导出兼容报告。", isError: true)
        } catch {
            install = nil
            features = DefaultTrainerFeatures.make(requiredBuild: KnownGameBuild.current)
            clearAttachment()
            log(error.localizedDescription, isError: true)
        }
    }

    func refreshProcess() {
        do {
            let signature = install?.signature ?? KnownGameBuild.current
            let request = ProcessResolveRequest(
                bundleID: signature.bundleID,
                executableName: "DAVE THE DIVER",
                executablePath: signature.executablePath
            )
            let resolvedProcess = try processResolver.resolve(request)
            if let targetProcess, targetProcess.pid != resolvedProcess.pid {
                clearAttachment()
            }
            targetProcess = resolvedProcess
            log("已找到进程：PID \(targetProcess?.pid ?? 0)")
        } catch {
            targetProcess = nil
            clearAttachment()
            log(error.localizedDescription, isError: true)
        }
    }

    func attach() {
        do {
            if targetProcess == nil {
                refreshProcess()
            }
            guard let targetProcess else {
                throw TrainerError.processNotFound
            }
            let verifiedInstall = try installResolver.resolveRunningGame(targetProcess)
            install = verifiedInstall
            features = DefaultTrainerFeatures.make(requiredBuild: verifiedInstall.signature)
            session = try memoryAccess.attach(to: targetProcess)
            clearRuntimeQuantityCaches()
            isAttached = true
            log("已附加进程：PID \(targetProcess.pid)")
        } catch {
            clearAttachment()
            log(error.localizedDescription, isError: true)
        }
    }

    func quickPrepare() {
        log("开始一键准备：刷新状态、备份存档、附加进程。")
        refreshGameContext()
        refreshAddressBook()
        refreshSaves()
        guard let build = install?.signature else {
            log("尚未识别游戏安装，无法完成一键准备。", isError: true)
            return
        }
        if let failure = trainerOperationService.buildSupportFailure(
            featureID: .divingGod,
            gameBuild: build
        ) {
            publishOperationResult(failure)
            return
        }
        createBackup()
        attach()
    }

    func unsupportedReason(for option: SimpleTrainerOption) -> String? {
        guard option.isAvailable, let build = install?.signature else {
            return option.unavailableReason
        }
        guard let featureID = DaveTrainerFeatureID(rawValue: option.manifestFeatureID) else {
            return "功能没有有效的 manifest ID。"
        }
        return trainerOperationService.unsupportedReason(
            featureID: featureID, gameBuild: build, allowExperimentalFeatures: allowExperimentalFeatures
        )
    }

    func refreshStaticFeatures() {
        guard !isBusy else {
            log("正在处理上一项操作，请等待完成。", isError: true)
            return
        }

        isBusy = true
        log("正在后台解析 GameAssembly.dylib 和 global-metadata.dat 的 IL2CPP 静态特征。")
        Task {
            let build = install?.signature ?? KnownGameBuild.current
            let outcome = await Task.detached(priority: .userInitiated) {
                Self.locateStaticFeatures(build: build)
            }.value

            isBusy = false
            switch outcome {
            case .success(let report):
                staticLocationReport = report
                log(Self.staticFeatureSummary(report))
            case .failure(let message):
                staticLocationReport = nil
                log(message, isError: true)
            }
        }
    }

    func exportCompatibilityReport() {
        guard !isBusy else {
            log("正在处理上一项操作，请等待完成。", isError: true)
            return
        }
        guard let build = install?.signature else {
            log("尚未识别游戏安装，无法生成兼容报告。请先启动游戏并刷新。", isError: true)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = Self.compatibilityReportFileName(for: build.version)
        panel.title = "导出 DaveTheTrainer 兼容报告"
        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        let request = DaveCompatibilityReportRequest(
            build: build,
            trainer: trainerReleaseIdentity(),
            profile: .current
        )
        let generator = compatibilityReportGenerator
        isBusy = true
        log("正在读取游戏构建指纹和 manifest 补丁证据；不会写入游戏或上传数据。")
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Self.writeCompatibilityReport(
                    request: request,
                    destination: destination,
                    generator: generator
                )
            }.value
            isBusy = false
            switch outcome {
            case .success(let fileName, let patchPointCount):
                log("兼容报告已导出：\(fileName)，包含 \(patchPointCount) 个 manifest 补丁点。请将该 JSON 附到 issue #2。")
            case .failure(let message):
                log(message, isError: true)
            }
        }
    }

    func restartAsAdministrator() {
        do {
            let executablePath = try currentExecutablePath()
            try launchWithAdministratorPrompt(executablePath: executablePath)
            log("已请求管理员权限重启。输入密码后会打开管理员版修改器。")
            NSApp.terminate(nil)
        } catch {
            log(error.localizedDescription, isError: true)
        }
    }

    func requestAdministratorRelaunchIfNeeded() {
        guard !isRunningAsAdministrator else {
            log("管理员模式已启用。")
            return
        }
        guard !hasRequestedAdministratorRelaunch else {
            return
        }

        hasRequestedAdministratorRelaunch = true
        log("管理员模式未启用。请先点“一键准备”连接游戏；若附加失败，再按报错提示处理权限。", isError: false)
    }

    func refreshAddressBook() {
        do {
            guard let addressStore else {
                throw TrainerError.fileOperationFailed("功能配置初始化失败：\(addressStoreInitializationError ?? "未知错误")")
            }
            let build = install?.signature ?? KnownGameBuild.current
            addressBook = try addressStore.load(build: build)
            log("功能配置已加载：\(addressBook.entries.count) 项")
        } catch {
            addressBook = .empty(build: install?.signature ?? KnownGameBuild.current)
            log(error.localizedDescription, isError: true)
        }
    }

    func saveAddress(entry: AddressEntry) {
        do {
            try persistAddress(entry: entry)
            log("地址已保存：\(entry.featureID) -> 0x\(String(entry.address, radix: 16))")
        } catch {
            log(error.localizedDescription, isError: true)
        }
    }

    func writeFeature(_ feature: TrainerFeature, text: String) {
        do {
            try write(feature: feature, text: text)
        } catch {
            log(error.localizedDescription, isError: true)
        }
    }

    func toggleFreeze(_ feature: TrainerFeature, text: String) {
        frozenFeatureIDs.contains(feature.id) ? stopFreeze(feature.id) : startFreeze(feature, text: text)
    }

    func isPatchEnabled(id: String) -> Bool {
        enabledPatchIDs.contains(id)
    }

    func applySimpleOption(_ request: SimpleTrainerActionRequest, completion: @escaping @MainActor (Bool) -> Void) {
        guard !isBusy else {
            log("正在处理上一项操作，请等待完成。", isError: true)
            completion(false)
            return
        }

        do {
            switch request.option.action {
            case .unavailable(let reason):
                throw TrainerError.invalidInput("\(request.option.title) 暂未接入：\(reason)。")
            case .patch(let patchID):
                let succeeded = try applyTrainerOperation(PlayerOperationApplyConfig(
                    request: request,
                    payload: .staticPatch(patchID: patchID),
                    patchIDs: [patchID]
                ))
                completion(succeeded)
            case .patchGroup(let patchIDs):
                let succeeded = try applyTrainerOperation(PlayerOperationApplyConfig(
                    request: request,
                    payload: .staticPatchGroup(patchIDs: patchIDs),
                    patchIDs: Set(patchIDs)
                ))
                completion(succeeded)
            case .valuePatch(let patchID):
                let succeeded = try applyTrainerOperation(PlayerOperationApplyConfig(
                    request: request,
                    payload: .valuePatch(patchID: patchID, valueText: request.valueText),
                    patchIDs: [patchID]
                ))
                completion(succeeded)
            case .increment(let featureID):
                guard request.isEnabled else {
                    completion(true)
                    return
                }
                guard let resourceID = DaveTrainerFeatureID(rawValue: featureID) else {
                    throw TrainerError.invalidInput("未知资源功能：\(featureID)")
                }
                startResourceOperation(
                    request: request,
                    payload: .runtimeQuantity(resourceID: resourceID, valueText: request.valueText),
                    completion: completion
                )
                return
            case .incrementInventory(let scope):
                guard request.isEnabled else {
                    completion(true)
                    return
                }
                startResourceOperation(
                    request: request,
                    payload: .inventory(scope: scope, valueText: request.valueText),
                    completion: completion
                )
                return
            case .incrementJungleInventory(let scope):
                guard request.isEnabled else {
                    completion(true)
                    return
                }
                startResourceOperation(
                    request: request,
                    payload: .jungleInventory(scope: scope, valueText: request.valueText),
                    completion: completion
                )
                return
            case .write(let featureID):
                guard request.isEnabled else {
                    log("\(request.option.title) 不需要关闭。")
                    completion(true)
                    return
                }
                let feature = try requiredFeature(id: featureID)
                applyResolvedOrLocate(request, feature: feature, completion: completion)
            case .freeze(let featureID):
                let feature = try requiredFeature(id: featureID)
                if request.isEnabled {
                    applyResolvedOrLocate(request, feature: feature, completion: completion)
                } else {
                    stopFreeze(feature.id)
                    completion(true)
                }
            }
        } catch TrainerError.addressNotCalibrated(let featureID) {
            log(addressNotCalibratedMessage(for: request, featureID: featureID), isError: true)
            completion(false)
        } catch {
            log(error.localizedDescription, isError: true)
            completion(false)
        }
    }

    func scanExact(kind: ScanValueKind, text: String) {
        do {
            let activeSession = try requireSession()
            let value = try ScanValue.parse(kind: kind, text: text)
            let report = try scanner.scanExact(ProcessScanRequest(target: value), session: activeSession)
            scanCandidates = report.candidates
            scanFailures = report.failures
            log("扫描完成：候选 \(report.candidates.count)，读取失败区域 \(report.failures.count)")
        } catch {
            log(error.localizedDescription, isError: true)
        }
    }

    func saveCandidate(_ candidate: ScanCandidate, forFeatureID featureID: String) {
        do {
            guard let feature = feature(for: featureID) else {
                throw TrainerError.invalidInput("未知功能：\(featureID)")
            }
            guard candidate.value.kind == feature.valueKind else {
                throw TrainerError.invalidInput("候选类型 \(candidate.value.kind.rawValue) 与 \(feature.title) 需要的 \(feature.valueKind.rawValue) 不一致。")
            }

            let details = AddressEntryDetails(
                address: candidate.address,
                valueKind: candidate.value.kind,
                note: "扫描器候选"
            )
            let entry = AddressEntry(featureID: feature.id, details: details)
            try persistAddress(entry: entry)
            log("已将候选地址保存给 \(feature.title)：0x\(String(candidate.address, radix: 16))")
            selectedSection = .trainer
        } catch {
            log(error.localizedDescription, isError: true)
        }
    }

    func refreshSaves() {
        do {
            saveSnapshots = try backupService.inspectSaves(at: backupService.defaultSaveDirectory)
            log("存档只读识别完成：\(saveSnapshots.count) 个 .sav 文件")
        } catch {
            saveSnapshots = []
            log(error.localizedDescription, isError: true)
        }
    }

    func createBackup() {
        do {
            let destinationRoot = try SaveBackupService.defaultBackupRoot()
            let request = BackupRequest(sourceDirectory: backupService.defaultSaveDirectory, destinationRoot: destinationRoot)
            let backupURL = try backupService.createBackup(request)
            log("已创建备份：\(backupURL.path)")
        } catch {
            log(error.localizedDescription, isError: true)
        }
    }

    func defaultValueText(for feature: TrainerFeature) -> String {
        feature.valueKind == .float32 || feature.valueKind == .double ? defaultFloatFreezeText : defaultSetValueText
    }

    func addressEntry(for feature: TrainerFeature) -> AddressEntry? {
        addressBook.entries[feature.id]
    }

    func feature(for id: String) -> TrainerFeature? {
        features.first { $0.id == id }
    }

    func beginCalibration(for feature: TrainerFeature) {
        calibrationFeatureID = feature.id
        selectedSection = .scanner
        log("开始校准：\(feature.title)。输入游戏里的当前数值后点扫描。")
    }

    func recordInputError(_ message: String) {
        log(message, isError: true)
    }

    private func requireSession() throws -> MemorySession {
        if let session {
            return session
        }
        attach()
        guard let session else {
            throw TrainerError.permissionDenied("尚未附加游戏进程。")
        }
        return session
    }

    private func startFreeze(_ feature: TrainerFeature, text: String) {
        do {
            try startFreezeOrThrow(feature, text: text)
        } catch {
            log(error.localizedDescription, isError: true)
        }
    }

    private func applyTrainerOperation(_ config: PlayerOperationApplyConfig) throws -> Bool {
        guard let featureID = DaveTrainerFeatureID(rawValue: config.request.option.manifestFeatureID) else {
            throw TrainerError.invalidInput("未知 manifest feature：\(config.request.option.manifestFeatureID)")
        }

        let gameBuild = try currentOperationBuild()
        if let failure = trainerOperationService.buildCompatibilityFailure(
            featureID: featureID,
            gameBuild: gameBuild,
            allowExperimentalFeatures: allowExperimentalFeatures || !config.request.isEnabled
        ) {
            publishOperationResult(failure)
            return false
        }
        let context = TrainerOperationContext(
            session: try requireSession(), gameBuild: gameBuild, allowExperimentalFeatures: allowExperimentalFeatures
        )
        let result = try trainerOperationService.apply(TrainerOperationRequest(
            featureID: featureID,
            isEnabled: config.request.isEnabled,
            payload: config.payload
        ), context: context)

        publishOperationResult(result)
        guard result.isMemoryApplied else {
            return false
        }

        if config.request.isEnabled {
            enabledPatchIDs.formUnion(config.patchIDs)
        } else {
            enabledPatchIDs.subtract(config.patchIDs)
        }
        return true
    }

    private func publishOperationResult(_ result: DaveTrainerOperationResult) {
        latestOperationResult = result
        let presentation = TrainerOperationResultPresenter.presentation(for: result)
        log(presentation.logMessage, isError: presentation.isError)
    }

    private func currentOperationBuild() throws -> GameBuildSignature {
        guard let signature = install?.signature else {
            let detail = targetProcess == nil
                ? "尚未找到正在运行的 Dave 进程，禁止执行玩家写入。"
                : "已找到进程，但无法从其 executable 验证 Dave app bundle，禁止执行玩家写入。"
            throw TrainerError.installNotFound(detail)
        }
        return signature
    }

    private func refreshGameContext() {
        refreshProcess()
        refreshInstall()
        guard targetProcess == nil, install != nil else {
            return
        }
        refreshProcess()
    }

    private func clearAttachment() {
        isAttached = false
        session = nil
        enabledPatchIDs.removeAll()
        clearRuntimeQuantityCaches()
    }

    private func startFreezeOrThrow(_ feature: TrainerFeature, text: String) throws {
        let value = try ScanValue.parse(kind: feature.valueKind, text: text)
        let activeSession = try requireSession()
        let request = FeatureWriteRequest(feature: feature, value: value, addressBook: addressBook)
        try writer.write(request, session: activeSession)
        let timer = Timer.scheduledTimer(withTimeInterval: freezeIntervalSeconds, repeats: true) { [weak self] timer in
            Task { @MainActor in
                self?.tickFreeze(timer: timer, request: request)
            }
        }
        freezeTimers[feature.id] = timer
        frozenFeatureIDs.insert(feature.id)
        log("已开启：\(feature.title)")
    }

    private func tickFreeze(timer: Timer, request: FeatureWriteRequest) {
        do {
            let activeSession = try requireSession()
            try writer.write(request, session: activeSession)
        } catch {
            timer.invalidate()
            freezeTimers[request.feature.id] = nil
            frozenFeatureIDs.remove(request.feature.id)
            log(error.localizedDescription, isError: true)
        }
    }

    private func stopFreeze(_ featureID: String) {
        freezeTimers[featureID]?.invalidate()
        freezeTimers[featureID] = nil
        frozenFeatureIDs.remove(featureID)
        log("已停止冻结：\(featureID)")
    }

    private func write(feature: TrainerFeature, text: String) throws {
        let activeSession = try requireSession()
        let value = try ScanValue.parse(kind: feature.valueKind, text: text)
        try writer.write(FeatureWriteRequest(feature: feature, value: value, addressBook: addressBook), session: activeSession)
        log("已写入 \(feature.title)：\(text)")
    }

    private func clearRuntimeQuantityCaches() {
        Task {
            await quantityWorker.clearRuntimeCaches()
        }
    }

    private func startResourceOperation(
        request: SimpleTrainerActionRequest,
        payload: TrainerOperationPayload,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        do {
            guard let featureID = DaveTrainerFeatureID(rawValue: request.option.manifestFeatureID) else {
                throw TrainerError.invalidInput("未知 manifest feature：\(request.option.manifestFeatureID)")
            }
            let gameBuild = try currentOperationBuild()
            if let failure = trainerOperationService.buildCompatibilityFailure(
                featureID: featureID,
                gameBuild: gameBuild,
                allowExperimentalFeatures: allowExperimentalFeatures
            ) {
                publishOperationResult(failure)
                completion(false)
                return
            }
            let activeSession = try requireSession()
            isBusy = true
            log("正在后台调整 \(request.option.title)：\(request.valueText)。")
            Task {
                do {
                    let result = try await quantityWorker.apply(
                        TrainerOperationRequest(
                            featureID: featureID,
                            isEnabled: request.isEnabled,
                            payload: payload
                        ),
                        context: TrainerOperationContext(
                            session: activeSession, gameBuild: gameBuild, allowExperimentalFeatures: allowExperimentalFeatures
                        )
                    )
                    isBusy = false
                    publishOperationResult(result)
                    completion(result.isMemoryApplied)
                } catch {
                    isBusy = false
                    log(error.localizedDescription, isError: true)
                    completion(false)
                }
            }
        } catch {
            log(error.localizedDescription, isError: true)
            completion(false)
        }
    }

    private func addressNotCalibratedMessage(for request: SimpleTrainerActionRequest, featureID: String) -> String {
        switch request.option.action {
        case .increment:
            return "\(request.option.title) 需要先校准当前数值地址：到扫描器选择 \(featureID)，输入游戏中当前显示的数值并保存地址。"
        case .write, .freeze:
            return "\(request.option.title) 需要先自动定位：把输入框改成游戏里当前显示的数值，再点应用或开关。"
        case .incrementInventory, .incrementJungleInventory, .patch, .patchGroup, .valuePatch, .unavailable:
            return "功能 \(featureID) 尚未校准地址，禁止写入。"
        }
    }

    private func requiredFeature(id: String) throws -> TrainerFeature {
        guard let feature = feature(for: id) else {
            throw TrainerError.invalidInput("未知功能：\(id)")
        }
        return feature
    }

    private func persistAddress(entry: AddressEntry) throws {
        guard let addressStore else {
            throw TrainerError.fileOperationFailed("功能配置初始化失败：\(addressStoreInitializationError ?? "未知错误")")
        }
        let nextBook = try addressBook.updating(entry, expectedBuild: addressBook.build)
        try addressStore.save(nextBook)
        addressBook = nextBook
    }

    private func applyResolvedOrLocate(
        _ request: SimpleTrainerActionRequest,
        feature: TrainerFeature,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        if addressBook.entries[feature.id] != nil {
            do {
                log("使用已缓存地址直接写入 \(feature.title)，不重新扫描。")
                let succeeded = try applyResolved(request, feature: feature)
                completion(succeeded)
            } catch {
                log(error.localizedDescription, isError: true)
                completion(false)
            }
            return
        }

        startStaticLocateForMissingAddress(request, feature: feature, completion: completion)
    }

    private func applyResolved(_ request: SimpleTrainerActionRequest, feature: TrainerFeature) throws -> Bool {
        switch request.option.action {
        case .unavailable(let reason):
            throw TrainerError.invalidInput("\(request.option.title) 暂未接入：\(reason)。")
        case .write:
            guard request.isEnabled else {
                return true
            }
            try write(feature: feature, text: request.valueText)
            return true
        case .freeze:
            request.isEnabled ? try startFreezeOrThrow(feature, text: request.valueText) : stopFreeze(feature.id)
            return true
        case .increment(let featureID):
            guard request.isEnabled else {
                return true
            }
            guard let resourceID = DaveTrainerFeatureID(rawValue: featureID) else {
                throw TrainerError.invalidInput("未知资源功能：\(featureID)")
            }
            return try applyTrainerOperation(PlayerOperationApplyConfig(
                request: request,
                payload: .runtimeQuantity(resourceID: resourceID, valueText: request.valueText),
                patchIDs: []
            ))
        case .incrementInventory(let scope):
            guard request.isEnabled else {
                return true
            }
            return try applyTrainerOperation(PlayerOperationApplyConfig(
                request: request,
                payload: .inventory(scope: scope, valueText: request.valueText),
                patchIDs: []
            ))
        case .incrementJungleInventory(let scope):
            guard request.isEnabled else {
                return true
            }
            return try applyTrainerOperation(PlayerOperationApplyConfig(
                request: request,
                payload: .jungleInventory(scope: scope, valueText: request.valueText),
                patchIDs: []
            ))
        case .patch(let patchID):
            return try applyTrainerOperation(PlayerOperationApplyConfig(
                request: request,
                payload: .staticPatch(patchID: patchID),
                patchIDs: [patchID]
            ))
        case .patchGroup(let patchIDs):
            return try applyTrainerOperation(PlayerOperationApplyConfig(
                request: request,
                payload: .staticPatchGroup(patchIDs: patchIDs),
                patchIDs: Set(patchIDs)
            ))
        case .valuePatch(let patchID):
            return try applyTrainerOperation(PlayerOperationApplyConfig(
                request: request,
                payload: .valuePatch(patchID: patchID, valueText: request.valueText),
                patchIDs: [patchID]
            ))
        }
    }

    private func startStaticLocateForMissingAddress(
        _ request: SimpleTrainerActionRequest,
        feature: TrainerFeature,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard !isBusy else {
            log("正在处理上一项操作，请等待完成。", isError: true)
            completion(false)
            return
        }

        isBusy = true
        log("\(feature.title) 没有缓存地址，改用 IL2CPP 静态特征定位，不执行慢速全内存数值扫描。")
        Task {
            let build = install?.signature ?? feature.requiredBuild
            let outcome = await Task.detached(priority: .userInitiated) {
                Self.locateStaticFeatures(build: build)
            }.value

            isBusy = false
            switch outcome {
            case .success(let report):
                staticLocationReport = report
                log(Self.staticFeatureMessage(featureID: feature.id, report: report), isError: true)
            case .failure(let message):
                staticLocationReport = nil
                log(message, isError: true)
            }
            completion(false)
        }
    }

    nonisolated private static func locateStaticFeatures(build: GameBuildSignature) -> StaticLocateOutcome {
        do {
            let report = try Il2CppStaticFeatureLocator().locate(build: build)
            return .success(report)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    nonisolated private static func staticFeatureSummary(_ report: Il2CppStaticLocationReport) -> String {
        let matchedCount = report.features.filter { $0.status == .matched }.count
        return "IL2CPP 静态特征解析完成：metadata v\(report.metadataVersion)，匹配 \(matchedCount)/\(report.features.count) 项。"
    }

    nonisolated private static func staticFeatureMessage(featureID: String, report: Il2CppStaticLocationReport) -> String {
        guard let feature = report.features.first(where: { $0.featureID == featureID }) else {
            return "IL2CPP 静态特征缺少功能 \(featureID)。"
        }

        let tokens = feature.metadataMatches.values.compactMap { match in
            match.method.map { "\(match.name)=method 0x\(String($0.token, radix: 16))" }
                ?? match.field.map { "\(match.name)=field 0x\(String($0.token, radix: 16))" }
        }
        let tokenText = tokens.isEmpty ? "未得到 method/field token" : tokens.joined(separator: ", ")
        return "\(feature.title) 静态特征 \(feature.status.rawValue)：\(tokenText)。当前未执行慢速数值扫描；还需要把 token 映射到运行时对象/函数写入点后才能直接修改。"
    }

    nonisolated private static func writeCompatibilityReport(
        request: DaveCompatibilityReportRequest,
        destination: URL,
        generator: any DaveCompatibilityReportGenerating
    ) -> CompatibilityReportExportOutcome {
        do {
            let report = try generator.generate(request)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(report)
            try data.write(to: destination, options: .atomic)
            return .success(fileName: destination.lastPathComponent, patchPointCount: report.patches.count)
        } catch {
            return .failure("兼容报告导出失败：\(error.localizedDescription)")
        }
    }

    private func trainerReleaseIdentity() -> DaveTrainerReleaseIdentity {
        let info = Bundle.main.infoDictionary ?? [:]
        return DaveTrainerReleaseIdentity(
            version: info["CFBundleShortVersionString"] as? String ?? "development",
            build: info["CFBundleVersion"] as? String ?? "local",
            commit: info["DaveTrainerGitCommit"] as? String ?? "unknown"
        )
    }

    nonisolated private static func compatibilityReportFileName(for version: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let safeVersion = version.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        return "DaveTheTrainer-compatibility-\(String(safeVersion)).json"
    }

    private func log(_ message: String, isError: Bool = false) {
        latestMessage = message
        latestMessageIsError = isError
        logs.append("[\(Self.timeFormatter.string(from: Date()))] \(message)")
    }

    private func currentExecutablePath() throws -> String {
        if let path = Bundle.main.executablePath {
            return path
        }
        guard let path = CommandLine.arguments.first, !path.isEmpty else {
            throw TrainerError.fileOperationFailed("无法定位当前可执行文件。")
        }
        return path
    }

    private func launchWithAdministratorPrompt(executablePath: String) throws {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(adminLogFilePrefix)-\(UUID().uuidString).log")
        let shellCommand = "\(shellQuoted(executablePath)) > \(shellQuoted(logURL.path)) 2>&1 &"
        let script = "do shell script \(appleScriptLiteral(shellCommand)) with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: osascriptPath)
        process.arguments = ["-e", script]
        try process.run()
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptLiteral(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
