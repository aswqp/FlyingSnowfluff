import Darwin
import Foundation
#if canImport(FlyingSnowfluffCore)
import FlyingSnowfluffCore
#endif

private func socketPath() -> String {
    "/private/tmp/flying-snowfluff-\(getuid()).sock"
}

private func monotonicMilliseconds() -> Int64 {
    var value = timespec()
    guard clock_gettime(CLOCK_MONOTONIC, &value) == 0 else { return 0 }
    return Int64(value.tv_sec) * 1_000 + Int64(value.tv_nsec) / 1_000_000
}

private func readBoundedInput(
    maximumBytes: Int,
    maximumWaitMilliseconds: Int32 = 80
) -> Data? {
    let descriptor = STDIN_FILENO
    let originalFlags = fcntl(descriptor, F_GETFL)
    guard originalFlags >= 0,
          fcntl(descriptor, F_SETFL, originalFlags | O_NONBLOCK) == 0
    else { return nil }
    defer { _ = fcntl(descriptor, F_SETFL, originalFlags) }

    let byteLimit = maximumBytes + 1
    let deadline = monotonicMilliseconds() + Int64(maximumWaitMilliseconds)
    var input = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)

    while input.count < byteLimit {
        let remaining = deadline - monotonicMilliseconds()
        guard remaining > 0 else { break }
        var pollDescriptor = pollfd(
            fd: descriptor,
            events: Int16(POLLIN | POLLHUP),
            revents: 0
        )
        let ready = poll(&pollDescriptor, 1, Int32(min(remaining, 10)))
        if ready == 0 { continue }
        if ready < 0 {
            if errno == EINTR { continue }
            return nil
        }

        let capacity = min(buffer.count, byteLimit - input.count)
        let count = buffer.withUnsafeMutableBytes { bytes in
            Darwin.read(descriptor, bytes.baseAddress, capacity)
        }
        if count > 0 {
            input.append(buffer, count: count)
            continue
        }
        if count == 0 { break }
        if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR { return nil }
    }

    guard input.count <= maximumBytes else { return nil }
    return input
}

private func send(_ data: Data, to path: String) {
    let descriptor = socket(AF_UNIX, SOCK_DGRAM, 0)
    guard descriptor >= 0 else { return }
    defer { Darwin.close(descriptor) }

    var address = sockaddr_un()
    let pathBytes = Array(path.utf8)
    let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
    guard pathBytes.count < pathCapacity else { return }
    let addressLength = MemoryLayout<sockaddr_un>.offset(of: \sockaddr_un.sun_path)! + pathBytes.count + 1
    address.sun_len = UInt8(addressLength)
    address.sun_family = sa_family_t(AF_UNIX)
    path.withCString { source in
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { destination in
                _ = strlcpy(destination, source, pathCapacity)
            }
        }
    }

    data.withUnsafeBytes { payload in
        withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                _ = Darwin.sendto(
                    descriptor,
                    payload.baseAddress,
                    payload.count,
                    MSG_DONTWAIT,
                    socketAddress,
                    socklen_t(addressLength)
                )
            }
        }
    }
}

private func run() {
    let arguments = CommandLine.arguments
    guard let eventIndex = arguments.firstIndex(of: "--event"),
          arguments.indices.contains(eventIndex + 1),
          let event = HookCommandEvent(rawValue: arguments[eventIndex + 1])
    else { return }

    guard let input = readBoundedInput(maximumBytes: HookEnvelopeParser.maximumInputBytes) else { return }
    guard let envelope = HookEnvelopeParser.parse(input, forcedEvent: event),
          let packet = try? JSONEncoder().encode(envelope),
          packet.count <= 4_096
    else { return }
    send(packet, to: socketPath())
}

run()
