import Foundation
import FlyingSnowfluffCore

@main
struct SocketBindProbe {
    static func main() {
        let server = PetEventServer { envelope in
            print(envelope.event.rawValue)
        }
        do {
            try server.start()
            print("PASS: bound \(PetEventServer.socketPath)")
            server.stop()
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }
}
