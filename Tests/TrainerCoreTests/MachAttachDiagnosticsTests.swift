import XCTest
@testable import TrainerCore

final class MachAttachDiagnosticsTests: XCTestCase {
    func testHardenedGameDenialExplainsWhyElevationIsInsufficient() {
        let detail = MachAttachDiagnostics.failureDetail(
            pid: 42, machError: "failure (5)", isAdministrator: true,
            targetPolicy: .hardenedWithoutDebugPermission
        )
        XCTAssertTrue(detail.contains("管理员模式已启用"))
        XCTAssertTrue(detail.contains("get-task-allow"))
        XCTAssertTrue(detail.contains("从 Steam 启动"))
        XCTAssertTrue(detail.contains("task_for_pid(42) failed"))
        XCTAssertFalse(detail.contains("请点击“管理员模式”"))
    }

    func testNonAdministratorDenialIncludesRelaunchGuidance() {
        let detail = MachAttachDiagnostics.failureDetail(
            pid: 42, machError: "failure (5)", isAdministrator: false, targetPolicy: .other
        )
        XCTAssertTrue(detail.contains("请点击“管理员模式”"))
        XCTAssertFalse(detail.contains("Hardened Runtime"))
    }

    func testUnknownSigningPolicyDoesNotClaimAHardenedRuntimeCause() {
        let detail = MachAttachDiagnostics.failureDetail(
            pid: 42, machError: "failure (5)", isAdministrator: true, targetPolicy: .unavailable
        )
        XCTAssertTrue(detail.contains("macOS 仍拒绝附加"))
        XCTAssertFalse(detail.contains("get-task-allow"))
    }

    func testMissingExecutableReturnsUnavailablePolicy() {
        XCTAssertEqual(MachAttachDiagnostics.targetPolicy(executablePath: "/nonexistent/davetrainer-test-target"), .unavailable)
    }
}
