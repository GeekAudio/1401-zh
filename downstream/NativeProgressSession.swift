import Foundation

// A private per-operation channel, with no log contents or writable progress files.
final class NativeProgressSession {
    let channel = "io.github.geekaudio.1401-zh.progress." + UUID().uuidString
    private var token: Int32 = -1

    init(update: @escaping (Double) -> Void) {
        var registration: Int32 = 0
        let status = notify_register_dispatch(channel, &registration, .main) { notification in
            var value: UInt64 = 0
            guard notify_get_state(notification, &value) == NOTIFY_STATUS_OK, value < 100 else { return }
            update(Double(value) / 100)
        }
        if status == NOTIFY_STATUS_OK { token = registration }
    }

    // The generated channel contains only a fixed prefix and UUID characters.
    var environment: String { "GEEK_PROGRESS_CHANNEL=" + channel + " " }

    func close() {
        if token != -1 { notify_cancel(token); token = -1 }
    }

    deinit { close() }
}
