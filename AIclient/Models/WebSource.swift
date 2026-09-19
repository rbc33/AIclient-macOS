import Foundation

/// One search result used as context for a response — kept on the
/// assistant `ChatMessage` that used it, so the UI can show a "Fuentes" row
/// linking back to where the information came from.
struct WebSource: Identifiable, Codable, Hashable {
    var id: String { url.absoluteString }
    var title: String
    var url: URL
}
