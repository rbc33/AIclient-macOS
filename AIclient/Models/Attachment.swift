import Foundation

/// Broad category of an attached file, used to pick an icon/preview and to
/// decide how to encode it for the backend (e.g. images go in as base64
/// `image_url` content parts; PDFs/documents get text-extracted upstream).
enum AttachmentKind: String, Codable, Hashable {
    case image
    case pdf
    case document
    case audio
}

/// A file attached to a chat message.
///
/// Small attachments carry their raw bytes inline (`data`). This keeps
/// `Conversation` fully `Codable` and self-contained for persistence,
/// without needing a separate on-disk blob store for a first version of
/// the app. If attachments turn out to be large/frequent, this is the type
/// to revisit first (e.g. spill `data` to a file and store a reference).
struct Attachment: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: AttachmentKind
    var fileName: String
    /// e.g. "image/png", "application/pdf".
    var mimeType: String
    var data: Data

    init(
        id: UUID = UUID(),
        kind: AttachmentKind,
        fileName: String,
        mimeType: String,
        data: Data
    ) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.mimeType = mimeType
        self.data = data
    }

    /// Human-readable size for the attachment chip in the chat bubble.
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }
}
