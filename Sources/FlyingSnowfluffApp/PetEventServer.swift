import Darwin
import Dispatch
import Foundation
import FlyingSnowfluffCore

final class PetEventServer {
    static var socketPath: String { "/private/tmp/flying-snowfluff-\(getuid()).sock" }

    private var descriptor: Int32 = -1
    private var source: DispatchSourceRead?
    private let onEvent: (HookEnvelope) -> Void

    init(onEvent: @escaping (HookEnvelope) -> Void) {
        self.onEvent = onEvent
    }

    func start() throws {
        stop()
        unlink(Self.socketPath)
        descriptor = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { throw ServerError.socket(errno) }

        var address = sockaddr_un()
        let pathBytes = Array(Self.socketPath.utf8)
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count < pathCapacity else {
            stop()
            throw ServerError.path
        }
        let addressLength = MemoryLayout<sockaddr_un>.offset(of: \sockaddr_un.sun_path)! + pathBytes.count + 1
        address.sun_len = UInt8(addressLength)
        address.sun_family = sa_family_t(AF_UNIX)
        Self.socketPath.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { destination in
                    _ = strlcpy(destination, source, pathCapacity)
                }
            }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(descriptor, socketAddress, socklen_t(addressLength))
            }
        }
        guard result == 0 else {
            let copiedPath = withUnsafeBytes(of: address.sun_path) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
            let failureCode = errno
            stop()
            throw ServerError.bind(failureCode, copiedPath, addressLength)
        }
        _ = Darwin.chmod(Self.socketPath, S_IRUSR | S_IWUSR)

        let readSource = DispatchSource.makeReadSource(
            fileDescriptor: descriptor,
            queue: DispatchQueue(label: "local.flyingsnowfluff.events", qos: .utility)
        )
        readSource.setEventHandler { [weak self] in self?.receivePacket() }
        readSource.resume()
        source = readSource
    }

    func stop() {
        source?.cancel()
        source = nil
        if descriptor >= 0 {
            Darwin.close(descriptor)
            descriptor = -1
        }
        unlink(Self.socketPath)
    }

    private func receivePacket() {
        guard descriptor >= 0 else { return }
        var bytes = [UInt8](repeating: 0, count: 4_096)
        let count = bytes.withUnsafeMutableBytes { buffer in
            Darwin.recv(descriptor, buffer.baseAddress, buffer.count, MSG_DONTWAIT)
        }
        guard count > 0,
              let envelope = try? JSONDecoder().decode(HookEnvelope.self, from: Data(bytes.prefix(count))),
              envelope.version == HookEnvelope.protocolVersion
        else { return }
        DispatchQueue.main.async { [onEvent] in onEvent(envelope) }
    }

    deinit { stop() }

    enum ServerError: Error, CustomStringConvertible {
        case socket(Int32)
        case path
        case bind(Int32, String, Int)

        var description: String {
            switch self {
            case .socket(let code): return "socket errno=\(code): \(String(cString: strerror(code)))"
            case .path: return "socket path is too long"
            case .bind(let code, let path, let length):
                return "bind errno=\(code): \(String(cString: strerror(code))); path=\(path); length=\(length)"
            }
        }
    }
}
