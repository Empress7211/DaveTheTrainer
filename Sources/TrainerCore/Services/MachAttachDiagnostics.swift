import Foundation
import Security

// Inspect only the selected target executable after task_for_pid fails.
// This diagnoses signing policy; it never changes signatures or system settings.
enum MachTargetDebugPolicy: Equatable {
    case hardenedWithoutDebugPermission
    case other
    case unavailable
}

struct MachAttachDiagnostics {
    private static let hardenedRuntimeFlag = UInt32(0x10000)

    static func targetPolicy(executablePath: String) -> MachTargetDebugPolicy {
        var code: SecStaticCode?
        let url = URL(fileURLWithPath: executablePath) as CFURL
        guard SecStaticCodeCreateWithPath(url, SecCSFlags(rawValue: 0), &code) == errSecSuccess,
              let code else {
            return .unavailable
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let information = information as? [String: Any],
              let flags = information[kSecCodeInfoFlags as String] as? NSNumber else {
            return .unavailable
        }
        let entitlements = information[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
        let allowsDebugging = entitlements["com.apple.security.get-task-allow"] as? Bool == true
        return flags.uint32Value & hardenedRuntimeFlag != 0 && !allowsDebugging
            ? .hardenedWithoutDebugPermission : .other
    }

    static func failureDetail(
        pid: Int32,
        machError: String,
        isAdministrator: Bool,
        targetPolicy: MachTargetDebugPolicy
    ) -> String {
        let context = "task_for_pid(\(pid)) failed: \(machError)"
        if targetPolicy == .hardenedWithoutDebugPermission {
            let mode = isAdministrator ? "管理员模式已启用。" : "当前还未启用管理员模式。"
            return "\(mode)目标游戏启用了 Hardened Runtime，但签名未允许调试附加（get-task-allow）；仅输入管理员密码不能解除该保护。请先保存并退出游戏，按权限说明为 Steam 安装启用调试权限，再重新从 Steam 启动并连接。\(context)"
        }
        if !isAdministrator {
            return "当前修改器未以管理员身份运行，请点击“管理员模式”授权后重试。\(context)"
        }
        return "管理员模式已启用，但 macOS 仍拒绝附加目标进程。请核对目标的代码签名与调试权限。\(context)"
    }
}
