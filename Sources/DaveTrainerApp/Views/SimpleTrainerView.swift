import SwiftUI

struct SimpleTrainerView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 0) {
            SimpleSidePanel()
                .frame(width: 300)
            Divider()
                .overlay(Color.white.opacity(0.14))
            SimpleOptionsPanel()
        }
        .background(Color(red: 0.10, green: 0.11, blue: 0.12))
        .foregroundStyle(.white)
    }
}

private struct SimpleSidePanel: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LogoBlock()
            statusText
            actionButtons
            Spacer()
            Text(trainerVersionText)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(22)
    }

    private var trainerVersionText: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return "Trainer Version: development"
        }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return "Trainer Version: \(version) (\(build ?? "local"))"
    }

    private var statusText: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Game Process Name:\nDAVE THE DIVER")
            Text("Process ID: \(store.targetProcess.map { String($0.pid) } ?? "Not Found")")
            Text("Attach: \(store.isAttached ? "Ready" : "Not Attached")")
                .foregroundStyle(store.isAttached ? .green : .orange)
            Text("Admin: \(store.isRunningAsAdministrator ? "Enabled" : "Not Enabled")")
                .foregroundStyle(store.isRunningAsAdministrator ? .green : .orange)
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(.white.opacity(0.78))
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                store.quickPrepare()
            } label: {
                Label("一键准备", systemImage: "bolt.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if !store.isRunningAsAdministrator {
                Button {
                    store.restartAsAdministrator()
                } label: {
                    Label("管理员模式重启", systemImage: "lock.open.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Button("刷新") {
                    store.refreshAll()
                }
                Button("备份") {
                    store.createBackup()
                }
            }

            Button {
                store.exportCompatibilityReport()
            } label: {
                Label("导出兼容报告", systemImage: "doc.badge.gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(store.install == nil || store.isBusy)
        }
        .controlSize(.large)
    }
}

private struct LogoBlock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DAVE")
                .font(.system(size: 58, weight: .black, design: .rounded))
                .foregroundStyle(.cyan)
                .shadow(color: .orange, radius: 0, x: 2, y: 2)
            Text("THE DIVER")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .tracking(8)
                .foregroundStyle(.white)
            Text("Adaptive Mac Trainer")
                .font(.title3.bold())
                .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .bottomLeading)
        .padding(18)
        .background {
            LinearGradient(
                colors: [.cyan.opacity(0.55), .blue.opacity(0.40), .black.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SimpleOptionsPanel: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                SimpleMessageBanner()
                if store.showsExperimentalControls {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("启用 .756 实验功能", isOn: $store.allowExperimentalFeatures)
                            .disabled(store.isBusy || !store.enabledPatchIDs.isEmpty || !store.frozenFeatureIDs.isEmpty)
                        Text("完整游戏效果尚待验证。请先备份存档，逐项测试；关闭功能并恢复补丁后才能关闭实验模式。")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                SimpleOptionSection(title: "Diving Options", options: SimpleTrainerOptions.diving)
                SimpleOptionSection(title: "Currency Options", options: SimpleTrainerOptions.currencies)
                SimpleOptionSection(title: "Inventory Options", options: SimpleTrainerOptions.inventory)
                SimpleOptionSection(title: "Sushi Bar Options", options: SimpleTrainerOptions.sushiBar)
            }
            .padding(28)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dave The Diver")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.orange)
                Text("No Hotkeys. Click options directly.")
                    .font(.title3.bold())
                    .foregroundStyle(.white.opacity(0.86))
            }
            Spacer()
            Text(gameStatusText)
                .font(.headline.monospaced())
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var gameStatusText: String {
        if let version = store.install?.signature.version {
            return version
        }
        return store.targetProcess == nil ? "Game Not Running" : "Install Not Resolved"
    }
}

private struct SimpleMessageBanner: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: store.latestMessageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(store.latestMessageIsError ? .orange : .green)
            Text(store.latestMessage)
                .lineLimit(3)
                .textSelection(.enabled)
            Spacer()
            if store.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            if !store.isRunningAsAdministrator {
                Button("管理员模式") {
                    store.restartAsAdministrator()
                }
            }
        }
        .font(.callout.weight(.semibold))
        .padding(12)
        .background(store.latestMessageIsError ? Color.orange.opacity(0.18) : Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SimpleOptionSection: View {
    let title: String
    let options: [SimpleTrainerOption]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.orange)
            VStack(spacing: 0) {
                ForEach(options) { option in
                    SimpleOptionRow(option: option)
                    Divider()
                        .overlay(Color.white.opacity(0.16))
                }
            }
            .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

private struct SimpleOptionRow: View {
    @EnvironmentObject private var store: AppStore
    let option: SimpleTrainerOption
    @State private var isOn = false
    @State private var valueText = ""
    @State private var isPending = false

    var body: some View {
        HStack(spacing: 14) {
            if option.usesToggle {
                Toggle("", isOn: binding)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!isAvailable || store.isBusy || isPending)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(option.title)
                    .font(.title3.bold())
                    .foregroundStyle(isAvailable ? .white.opacity(0.90) : .white.opacity(0.52))
                if let reason = unavailableReason {
                    Text(reason)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange.opacity(0.72))
                        .lineLimit(2)
                }
            }
            if isPending {
                ProgressView()
                    .controlSize(.small)
            }
            if !isAvailable {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.gray)
            }
            Spacer()
            if option.showsValue {
                TextField("", text: $valueText)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.title3.monospaced().bold())
                    .foregroundStyle(.orange)
                    .frame(width: 110)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 6))
                    .disabled(!isAvailable || store.isBusy || isPending)
                Button("应用") {
                    apply(enabled: true)
                }
                .disabled(!isAvailable || store.isBusy || isPending)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onAppear {
            guard valueText.isEmpty else {
                syncEnabledState(with: store.enabledPatchIDs)
                return
            }
            valueText = option.defaultValue
            syncEnabledState(with: store.enabledPatchIDs)
        }
        .onReceive(store.$enabledPatchIDs) { patchIDs in
            syncEnabledState(with: patchIDs)
        }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { nextValue in
                apply(enabled: nextValue)
            }
        )
    }

    private var unavailableReason: String? {
        option.unavailableReason ?? store.unsupportedReason(for: option)
    }

    private var isAvailable: Bool {
        unavailableReason == nil
    }

    private func apply(enabled: Bool) {
        guard !isPending else {
            return
        }

        let request = SimpleTrainerActionRequest(
            option: option,
            isEnabled: enabled,
            valueText: valueText.isEmpty ? option.defaultValue : valueText
        )
        isPending = true
        store.applySimpleOption(request) { success in
            isPending = false
            isOn = success && !option.isMomentary ? enabled : false
        }
    }

    private func syncEnabledState(with patchIDs: Set<String>) {
        let enabledStateIDs = option.enabledStateIDs
        guard !enabledStateIDs.isEmpty else {
            return
        }

        isOn = enabledStateIDs.isSubset(of: patchIDs)
    }
}
