import Foundation
import MachMemory

private let maxMachWriteByteCount = Int(UInt32.max)

public struct MemoryReadRequest: Sendable {
    public let address: UInt64
    public let size: Int

    public init(address: UInt64, size: Int) {
        self.address = address
        self.size = size
    }
}

public struct MemoryWriteRequest: Sendable {
    public let address: UInt64
    public let data: Data

    public init(address: UInt64, data: Data) {
        self.address = address
        self.data = data
    }
}

public struct MemoryProtectRequest: Sendable {
    public let address: UInt64
    public let size: UInt64
    public let protection: Int32

    public init(address: UInt64, size: UInt64, protection: Int32) {
        self.address = address
        self.size = size
        self.protection = protection
    }
}

public struct MemoryAllocateRequest: Sendable {
    public let address: UInt64
    public let size: UInt64
    public let flags: Int32

    public init(address: UInt64, size: UInt64, flags: Int32) {
        self.address = address
        self.size = size
        self.flags = flags
    }
}

public struct MemoryDeallocateRequest: Sendable {
    public let address: UInt64
    public let size: UInt64

    public init(address: UInt64, size: UInt64) {
        self.address = address
        self.size = size
    }
}

public struct MemoryCacheFlushRequest: Sendable {
    public let address: UInt64
    public let size: UInt64
    public let kind: MemoryCacheKind

    public init(address: UInt64, size: UInt64, kind: MemoryCacheKind) {
        self.address = address
        self.size = size
        self.kind = kind
    }
}

public final class MachMemoryAccess: MemoryAccess {
    public init() {}

    public func attach(to process: TargetProcess) throws -> MemorySession {
        var task = mach_port_name_t()
        let result = dt_task_for_pid(process.pid, &task)
        guard result == KERN_SUCCESS else {
            throw TrainerError.permissionDenied(MachAttachDiagnostics.failureDetail(
                pid: process.pid,
                machError: machError(result),
                isAdministrator: geteuid() == 0,
                targetPolicy: process.pid > 0
                    ? MachAttachDiagnostics.targetPolicy(executablePath: process.executablePath)
                    : .unavailable
            ))
        }
        return MemorySession(task: task, process: process, ownsPort: true)
    }

    public func currentProcessSession() -> MemorySession {
        let process = TargetProcess(
            pid: getpid(),
            name: ProcessInfo.processInfo.processName,
            executablePath: CommandLine.arguments.first ?? ProcessInfo.processInfo.processName
        )
        return MemorySession(task: dt_mach_task_self(), process: process, ownsPort: false)
    }
}

public final class MemorySession {
    public let process: TargetProcess
    private let task: mach_port_name_t
    private let ownsPort: Bool

    init(task: mach_port_name_t, process: TargetProcess, ownsPort: Bool) {
        self.task = task
        self.process = process
        self.ownsPort = ownsPort
    }

    deinit {
        if ownsPort {
            _ = dt_mach_port_deallocate(task)
        }
    }

    public func read(_ request: MemoryReadRequest) throws -> Data {
        guard request.size > 0 else {
            throw TrainerError.invalidInput("读取长度必须大于 0。")
        }

        var data = Data(count: request.size)
        var bytesRead = 0
        let result = data.withUnsafeMutableBytes { rawBuffer in
            dt_mach_vm_read(task, request.address, rawBuffer.baseAddress, request.size, &bytesRead)
        }

        guard result == KERN_SUCCESS else {
            throw TrainerError.memoryReadFailed("mach_vm_read_overwrite(0x\(String(request.address, radix: 16))) failed: \(machError(result))")
        }

        guard bytesRead == request.size else {
            throw TrainerError.memoryReadFailed("mach_vm_read_overwrite(0x\(String(request.address, radix: 16))) 只读取 \(bytesRead)/\(request.size) 字节。")
        }

        return data
    }

    public func write(_ request: MemoryWriteRequest) throws {
        guard !request.data.isEmpty else {
            throw TrainerError.invalidInput("写入数据不能为空。")
        }

        guard request.data.count <= maxMachWriteByteCount else {
            throw TrainerError.memoryWriteFailed("mach_vm_write 单次写入超过 \(maxMachWriteByteCount) 字节。")
        }

        let result = request.data.withUnsafeBytes { rawBuffer in
            dt_mach_vm_write(task, request.address, rawBuffer.baseAddress, request.data.count)
        }

        guard result == KERN_SUCCESS else {
            throw TrainerError.memoryWriteFailed("mach_vm_write(0x\(String(request.address, radix: 16))) failed: \(machError(result))")
        }
    }

    public func allocate(_ request: MemoryAllocateRequest) throws -> UInt64 {
        guard request.size > 0 else {
            throw TrainerError.invalidInput("分配长度必须大于 0。")
        }

        var address = request.address
        let result = dt_mach_vm_allocate(task, &address, request.size, request.flags)
        guard result == KERN_SUCCESS else {
            throw TrainerError.memoryWriteFailed("mach_vm_allocate(0x\(String(request.address, radix: 16))) failed: \(machError(result))")
        }

        return address
    }

    public func deallocate(_ request: MemoryDeallocateRequest) throws {
        guard request.size > 0 else {
            throw TrainerError.invalidInput("释放长度必须大于 0。")
        }

        let result = dt_mach_vm_deallocate(task, request.address, request.size)
        guard result == KERN_SUCCESS else {
            throw TrainerError.memoryWriteFailed("mach_vm_deallocate(0x\(String(request.address, radix: 16))) failed: \(machError(result))")
        }
    }

    public func protect(_ request: MemoryProtectRequest) throws {
        guard request.size > 0 else {
            throw TrainerError.invalidInput("保护范围长度必须大于 0。")
        }

        let result = dt_mach_vm_protect(task, request.address, request.size, 0, request.protection)
        guard result == KERN_SUCCESS else {
            throw TrainerError.memoryWriteFailed("mach_vm_protect(0x\(String(request.address, radix: 16))) failed: \(machError(result))")
        }
    }

    public func flushCache(_ request: MemoryCacheFlushRequest) throws {
        guard request.size > 0 else {
            throw TrainerError.invalidInput("缓存刷新范围长度必须大于 0。")
        }

        switch request.kind {
        case .instruction:
            let result = dt_mach_vm_flush_instruction_cache(task, request.address, request.size)
            guard result == KERN_SUCCESS else {
                throw TrainerError.memoryWriteFailed("mach_vm_machine_attribute(ICACHE_FLUSH, 0x\(String(request.address, radix: 16))) failed: \(machError(result))")
            }
        }
    }

    public func regions() throws -> [MemoryRegion] {
        var address = UInt64.zero
        var depth = UInt32.zero
        var regions: [MemoryRegion] = []

        while true {
            var rawRegion = DTMemoryRegion()
            var queryAddress = address
            var queryDepth = depth
            let result = dt_mach_vm_region_recurse(task, &queryAddress, &queryDepth, &rawRegion)

            if result == KERN_INVALID_ADDRESS {
                return regions
            }

            guard result == KERN_SUCCESS else {
                throw TrainerError.memoryReadFailed("mach_vm_region_recurse failed: \(machError(result))")
            }

            let region = MemoryRegion(raw: rawRegion)
            if region.isSubmap {
                depth = queryDepth + 1
                continue
            }

            regions.append(region)
            address = try nextAddress(after: region)
            depth = queryDepth
        }
    }

    private func nextAddress(after region: MemoryRegion) throws -> UInt64 {
        let next = region.address.addingReportingOverflow(region.size)
        guard !next.overflow, next.partialValue > region.address else {
            throw TrainerError.memoryReadFailed("内存区域地址溢出：0x\(String(region.address, radix: 16))")
        }
        return next.partialValue
    }
}

extension MemorySession: @unchecked Sendable {}

extension MemoryRegion {
    init(raw: DTMemoryRegion) {
        let descriptor = MemoryRegionDescriptor(
            range: MemoryRange(address: raw.address, size: raw.size),
            protection: MemoryProtectionInfo(current: raw.protection, maximum: raw.max_protection),
            flags: MemoryRegionFlags(isSubmap: raw.is_submap != 0, userTag: raw.user_tag)
        )
        self.init(descriptor: descriptor)
    }
}

public func machError(_ code: kern_return_t) -> String {
    guard let pointer = mach_error_string(code) else {
        return "kern_return_t=\(code)"
    }
    return "\(String(cString: pointer)) (\(code))"
}
