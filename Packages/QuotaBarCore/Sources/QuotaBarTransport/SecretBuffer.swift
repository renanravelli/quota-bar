import Darwin

enum SecretBuffer {
    static func zero(_ region: UnsafeMutableRawBufferPointer) {
        guard let base = region.baseAddress, region.count > 0 else { return }
        _ = memset_s(base, rsize_t(region.count), 0, rsize_t(region.count))
    }

    static func zero(_ bytes: inout [UInt8]) {
        bytes.withUnsafeMutableBytes(zero)
    }
}

final class SecretOutbox: @unchecked Sendable {
    private var storage = UnsafeMutableRawBufferPointer(start: nil, count: 0)

    deinit {
        release()
    }

    var isZeroed: Bool {
        storage.allSatisfy { $0 == 0 }
    }

    func load(_ value: String, terminatedBy terminator: UInt8) -> UnsafeRawBufferPointer {
        let payloadLength = value.utf8.count + 1
        reserve(payloadLength)

        var index = 0
        for byte in value.utf8 {
            storage[index] = byte
            index += 1
        }
        storage[index] = terminator

        return UnsafeRawBufferPointer(rebasing: storage[0..<payloadLength])
    }

    func wipe() {
        SecretBuffer.zero(storage)
    }

    private func reserve(_ byteCount: Int) {
        guard storage.count < byteCount else { return }

        release()
        storage = UnsafeMutableRawBufferPointer.allocate(byteCount: byteCount, alignment: 1)
        SecretBuffer.zero(storage)
    }

    private func release() {
        guard storage.baseAddress != nil else { return }
        wipe()
        storage.deallocate()
        storage = UnsafeMutableRawBufferPointer(start: nil, count: 0)
    }
}
