import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// The macOS and iOS targets compile the exact same sources. Everything that
// differs between AppKit and UIKit (or only makes sense on one platform)
// is funneled through the small helpers below, so the views themselves stay
// almost free of `#if os(...)`.

#if os(macOS)
typealias PlatformImage = NSImage
#else
typealias PlatformImage = UIImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

/// System clipboard: NSPasteboard on macOS, UIPasteboard on iOS.
enum PlatformClipboard {
    static func copy(_ string: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }

    /// First image on the clipboard (e.g. a screenshot), re-encoded as PNG.
    static func imagePNGData() -> Data? {
        #if os(macOS)
        guard let images = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
              let image = images.first,
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
        #else
        guard UIPasteboard.general.hasImages else { return nil }
        return UIPasteboard.general.image?.pngData()
        #endif
    }

    static func string() -> String? {
        #if os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #else
        return UIPasteboard.general.string
        #endif
    }
}

extension Color {
    /// Shaded background for fenced code blocks in `MarkdownContentView`.
    static var codeBlockBackground: Color {
        #if os(macOS)
        return Color(nsColor: .textBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

extension View {
    /// Minimum window/sheet size — only meaningful on macOS. On iPhone a
    /// 760-pt minimum width would push content off-screen, and iOS sizes
    /// sheets and screens itself, so this is a no-op there.
    @ViewBuilder
    func macOSMinFrame(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
        self.frame(minWidth: width, minHeight: height)
        #else
        self
        #endif
    }

    /// Compact, chrome-less look for the inline menus in the composer
    /// ("+" and the provider/model picker). `.borderlessButton` only exists
    /// on macOS; iOS menus already render as plain tappable labels.
    @ViewBuilder
    func compactMenuStyle() -> some View {
        #if os(macOS)
        self.menuStyle(.borderlessButton)
        #else
        self
        #endif
    }

    /// For URL text fields: on iOS, no auto-capitalization ("Http://…"),
    /// no autocorrect mangling the hostname, and the URL keyboard.
    @ViewBuilder
    func urlInputField() -> some View {
        #if os(iOS)
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
        #else
        self.autocorrectionDisabled()
        #endif
    }
}

#if os(iOS)
extension UIImage {
    /// Photos from the library can be 12–48 MP HEICs: downscale to at most
    /// `maxDimension` px on the long side and re-encode as JPEG, which every
    /// vision backend (llama.cpp/llama-swap, Ollama, vLLM) can decode and
    /// which keeps the base64 payload reasonable. Drawing through the
    /// renderer also bakes in the EXIF orientation.
    func jpegDataForUpload(maxDimension: CGFloat = 2048, quality: CGFloat = 0.85) -> Data? {
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxDimension / longest)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
#endif
