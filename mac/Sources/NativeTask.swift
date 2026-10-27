import Foundation

// UI-only activity. A nil fraction means the backend cannot estimate completion.
struct NativeTask: Identifiable {
    let id: String
    let page: String
    let anchor: String
    var title: String
    var fraction: Double? = nil
    var amount = ""
}
