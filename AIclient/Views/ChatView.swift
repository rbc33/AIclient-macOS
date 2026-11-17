import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
#if os(iOS)
import PhotosUI
#endif

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    var providerStore: ProviderStore
    var webSearchStore: WebSearchStore

    @State private var pendingAttachments: [Attachment] = []
    @State private var showingImageImporter = false
    @State private var showingFileImporter = false
    @State private var attachmentError: String?

    /// On for the *next* message only — resets after sending, like
    /// `pendingAttachments`. Tapping the globe button opens Ajustes instead
    /// of turning this on when no `WebSearchConfig` is saved yet.
    @State private var webSearchEnabled = false
    @State private var showingWebSearchSettings = false

    /// Models fetched from each provider's `/v1/models`, keyed by provider
    /// id — powers the combined provider+model picker below, which needs
    /// every provider's models (not just the active one) to build its
    /// submenus.
    @State private var modelsByProvider: [UUID: [String]] = [:]
    @State private var loadingProviderIDs: Set<UUID> = []

    #if os(iOS)
    /// iOS "Fotos" opens the system photo library (PhotosPicker) rather than
    /// the Files browser `.fileImporter` would show.
    @State private var photoSelection: [PhotosPickerItem] = []
    #endif

    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var isRecording = false

    private static let maxAttachmentMB = 8
    private static let maxAttachmentBytes = maxAttachmentMB * 1024 * 1024

    init(conversation: Conversation, provider: ProviderConfig?, conversationStore: ConversationStore, providerStore: ProviderStore, webSearchStore: WebSearchStore) {
        _viewModel = State(wrappedValue: ChatViewModel(conversation: conversation, provider: provider, store: conversationStore, webSearchStore: webSearchStore))
        self.providerStore = providerStore
        self.webSearchStore = webSearchStore
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.provider == nil {
                ContentUnavailableView(
                    "Este proveedor ya no existe",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Edítalo o crea uno nuevo en Proveedores.")
                )
            } else {
                messageList
            }

            if let error = viewModel.errorMessage ?? attachmentError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            if viewModel.isSearchingWeb {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Buscando en la web…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 4)
            }

            if !pendingAttachments.isEmpty {
                pendingAttachmentsRow
            }

            providerModelPickerRow

            inputBar
        }
        .navigationTitle(viewModel.conversation.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(
            isPresented: $showingImageImporter,
            selection: $photoSelection,
            maxSelectionCount: 5,
            matching: .images
        )
        .onChange(of: photoSelection) {
            loadSelectedPhotos()
        }
        #else
        .fileImporter(
            isPresented: $showingImageImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            handleImportResult(result, forcedKind: .image)
        }
        #endif
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.pdf, .plainText, .rtf, .audio, .data],
            allowsMultipleSelection: true
        ) { result in
            handleImportResult(result, forcedKind: nil)
        }
        .task(id: providerStore.providers.map(\.id)) {
            await loadAllModels()
        }
        .sheet(isPresented: $showingWebSearchSettings) {
            WebSearchSettingsView(store: webSearchStore)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.conversation.messages) { message in
                        MessageBubbleView(
                            message: message,
                            onRegenerate: regenerateAction(for: message)
                        )
                        .id(message.id)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.conversation.messages.last?.content) {
                guard let lastID = viewModel.conversation.messages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    private var pendingAttachmentsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(pendingAttachments) { attachment in
                    HStack(spacing: 4) {
                        Image(systemName: icon(for: attachment.kind))
                        Text(attachment.fileName)
                            .lineLimit(1)
                        Button {
                            pendingAttachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.top, 6)
        }
    }

    /// Inline provider+model switcher, à la Claude's composer — one control
    /// showing "Proveedor · modelo". Opening it lists every configured
    /// provider as a labeled section (each with its own models fetched from
    /// that provider's `/v1/models`); picking a model there switches both
    /// the provider and the model in a single gesture, and persists the
    /// choice on the provider (its default model) and on this conversation
    /// (which provider it uses).
    ///
    /// Deliberately flat (`Section`s in one top-level menu), not nested
    /// `Menu`s-within-`Menu`s — macOS/AppKit can cache a submenu's items
    /// from the moment it's first built, so if a provider's models arrive
    /// (async, from `/v1/models`) after that, the submenu can get stuck
    /// showing stale/empty content on reopen. A single top-level menu is
    /// rebuilt fresh every time it's opened, so it always reflects the
    /// latest `modelsByProvider`.
    private var providerModelPickerRow: some View {
        HStack {
            Menu {
                if providerStore.providers.isEmpty {
                    Text("Sin proveedores — añade uno en Proveedores")
                } else {
                    ForEach(providerStore.providers) { provider in
                        Section(provider.name) {
                            providerModelMenuItems(for: provider)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(pickerLabel)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
            }
            .compactMenuStyle()
            .fixedSize()
            .disabled(providerStore.providers.isEmpty)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 6)
    }

    private var pickerLabel: String {
        guard let provider = viewModel.provider else { return "Elegir proveedor" }
        let model = provider.model.isEmpty ? "sin modelo" : provider.model
        return "\(provider.name) · \(model)"
    }

    @ViewBuilder
    private func providerModelMenuItems(for provider: ProviderConfig) -> some View {
        let models = modelsByProvider[provider.id] ?? []
        if loadingProviderIDs.contains(provider.id) {
            Text("Cargando modelos…")
        } else if models.isEmpty {
            Button {
                selectProviderAndModel(provider, modelID: provider.model)
            } label: {
                Text(provider.model.isEmpty ? "Usar este proveedor" : "Usar (modelo actual: \(provider.model))")
            }
        } else {
            ForEach(models, id: \.self) { modelID in
                Button {
                    selectProviderAndModel(provider, modelID: modelID)
                } label: {
                    if provider.id == viewModel.provider?.id && modelID == provider.model {
                        Label(modelID, systemImage: "checkmark")
                    } else {
                        Text(modelID)
                    }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                Button {
                    showingImageImporter = true
                } label: {
                    Label("Fotos", systemImage: "photo")
                }
                Button {
                    showingFileImporter = true
                } label: {
                    Label("Archivos", systemImage: "doc")
                }
                #if os(iOS)
                // On iPhone the composer row is too narrow for a separate
                // paste button; text can also be pasted natively into the
                // field (long-press > Pegar), so here it lives in this menu.
                Button {
                    pasteFromClipboard()
                } label: {
                    Label("Pegar", systemImage: "doc.on.clipboard")
                }
                #endif
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .compactMenuStyle()
            .fixedSize()
            .disabled(viewModel.provider == nil)
            .help("Adjuntar")

            #if os(macOS)
            Button {
                pasteFromClipboard()
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.provider == nil)
            .help("Pegar (texto o imagen del portapapeles)")
            #endif

            Button {
                if webSearchStore.config == nil {
                    showingWebSearchSettings = true
                } else {
                    webSearchEnabled.toggle()
                }
            } label: {
                Image(systemName: "globe")
                    .font(.title2)
                    .foregroundStyle(webSearchEnabled ? Color.accentColor : .primary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.provider == nil)
            .help(webSearchStore.config == nil
                ? "Configura un buscador web (SearXNG)"
                : (webSearchEnabled ? "Búsqueda web activada para el próximo mensaje" : "Buscar en la web antes de responder"))

            TextField("Escribe un mensaje…", text: $viewModel.draftText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                .onSubmit { send() }
                .disabled(viewModel.provider == nil)

            Button {
                toggleRecording()
            } label: {
                Image(systemName: isRecording ? "stop.circle.fill" : "mic")
                    .font(.title2)
                    .foregroundStyle(isRecording ? .red : .primary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.provider == nil)
            .help(isRecording ? "Detener grabación" : "Grabar audio")

            if viewModel.isSending {
                Button {
                    viewModel.cancelStreaming()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .help("Detener")
            } else {
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(canSend == false)
                .help("Enviar")
            }
        }
        .padding()
    }

    private var canSend: Bool {
        guard viewModel.provider != nil else { return false }
        return !viewModel.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !pendingAttachments.isEmpty
    }

    private func send() {
        let attachments = pendingAttachments
        viewModel.send(attachments: attachments, webSearch: webSearchEnabled)
        pendingAttachments = []
        webSearchEnabled = false
    }

    /// Only the last assistant message gets a "repetir" button, and only
    /// once it's finished streaming.
    private func regenerateAction(for message: ChatMessage) -> (() -> Void)? {
        guard message.role == .assistant,
              !message.isStreaming,
              message.id == viewModel.conversation.messages.last(where: { $0.role == .assistant })?.id
        else { return nil }
        return { viewModel.regenerateLastResponse() }
    }

    /// Switches the active conversation to `provider` (persisting that on
    /// the conversation) and records `modelID` as that provider's model
    /// (persisting that on the provider itself) — one tap in the picker
    /// covers both.
    private func selectProviderAndModel(_ provider: ProviderConfig, modelID: String) {
        var updated = provider
        updated.model = modelID
        providerStore.upsert(updated)
        viewModel.setProvider(updated)
    }

    /// Fetches `/v1/models` for every configured provider concurrently, so
    /// the combined picker can show each provider's full model list in its
    /// submenu without waiting for you to open it. Providers already loaded
    /// or currently loading are skipped on repeat calls (e.g. after the
    /// provider list changes elsewhere).
    private func loadAllModels() async {
        let providers = providerStore.providers
        let toFetch = providers.filter { !loadingProviderIDs.contains($0.id) }
        guard !toFetch.isEmpty else { return }

        for provider in toFetch { loadingProviderIDs.insert(provider.id) }

        await withTaskGroup(of: (UUID, [String]?).self) { group in
            for provider in toFetch {
                group.addTask {
                    let apiKey = provider.hasAPIKey ? KeychainStore.apiKey(for: provider.id) : nil
                    let result = await ProviderConnectionTester.testConnection(baseURL: provider.baseURL, apiKey: apiKey)
                    if case .success(let models) = result {
                        return (provider.id, models)
                    }
                    return (provider.id, nil)
                }
            }
            for await (providerID, models) in group {
                loadingProviderIDs.remove(providerID)
                if let models {
                    modelsByProvider[providerID] = models
                }
            }
        }
    }

    /// Prefers an image on the clipboard (e.g. a screenshot) — a plain
    /// `TextField` can't receive pasted images, so this is the only way to
    /// attach one without going through a picker. Falls back to pasting text
    /// into the draft.
    private func pasteFromClipboard() {
        if let data = PlatformClipboard.imagePNGData() {
            guard data.count <= Self.maxAttachmentBytes else {
                attachmentError = "La imagen pegada pesa más de \(Self.maxAttachmentMB) MB."
                return
            }
            let fileName = "Pegado \(pendingAttachments.count + 1).png"
            pendingAttachments.append(Attachment(kind: .image, fileName: fileName, mimeType: "image/png", data: data))
            attachmentError = nil
            return
        }

        if let text = PlatformClipboard.string(), !text.isEmpty {
            viewModel.draftText = viewModel.draftText.isEmpty ? text : viewModel.draftText + "\n" + text
            attachmentError = nil
            return
        }

        attachmentError = "El portapapeles no tiene texto ni imagen para pegar."
    }

    #if os(iOS)
    /// Loads what the user picked in the iOS photo library and attaches it
    /// as a downscaled JPEG (library photos are often huge HEICs that some
    /// vision backends can't decode).
    private func loadSelectedPhotos() {
        let items = photoSelection
        guard !items.isEmpty else { return }
        photoSelection = []

        Task { @MainActor in
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let jpeg = image.jpegDataForUpload() else {
                    attachmentError = "No se pudo cargar una de las fotos."
                    continue
                }
                guard jpeg.count <= Self.maxAttachmentBytes else {
                    attachmentError = "Una de las fotos pesa más de \(Self.maxAttachmentMB) MB — no se adjuntó."
                    continue
                }
                let fileName = "Foto \(pendingAttachments.count + 1).jpg"
                pendingAttachments.append(Attachment(kind: .image, fileName: fileName, mimeType: "image/jpeg", data: jpeg))
                attachmentError = nil
            }
        }
    }
    #endif

    // MARK: - Audio recording

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            requestMicrophoneThenRecord()
        }
    }

    /// iOS needs the microphone permission explicitly granted before
    /// recording (and shows the system prompt the first time). On macOS the
    /// prompt is triggered by the recorder itself.
    private func requestMicrophoneThenRecord() {
        #if os(iOS)
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            startRecording()
        case .denied:
            attachmentError = "Sin permiso de micrófono — actívalo en Ajustes > AIclient."
        case .undetermined:
            Task { @MainActor in
                if await AVAudioApplication.requestRecordPermission() {
                    startRecording()
                } else {
                    attachmentError = "Sin permiso de micrófono — actívalo en Ajustes > AIclient."
                }
            }
        @unknown default:
            startRecording()
        }
        #else
        startRecording()
        #endif
    }

    private func startRecording() {
        #if os(iOS)
        // iOS's default audio session category can't record at all.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            attachmentError = "No se pudo activar el micrófono: \(error.localizedDescription)"
            return
        }
        #endif

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.record() else {
                attachmentError = "No se pudo iniciar la grabación (permiso de micrófono denegado)."
                return
            }
            audioRecorder = recorder
            recordingURL = url
            isRecording = true
            attachmentError = nil
        } catch {
            attachmentError = "No se pudo iniciar la grabación: \(error.localizedDescription)"
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif

        guard let url = recordingURL else { return }
        recordingURL = nil
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let data = try Data(contentsOf: url)
            guard data.count <= Self.maxAttachmentBytes else {
                attachmentError = "El audio grabado pesa más de \(Self.maxAttachmentMB) MB."
                return
            }
            let fileName = "Audio \(pendingAttachments.count + 1).m4a"
            pendingAttachments.append(Attachment(kind: .audio, fileName: fileName, mimeType: "audio/m4a", data: data))
            attachmentError = nil
        } catch {
            attachmentError = "No se pudo leer la grabación: \(error.localizedDescription)"
        }
    }

    // MARK: - Attachment picking (file importer)

    private func icon(for kind: AttachmentKind) -> String {
        switch kind {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .document: return "doc.text"
        case .audio: return "waveform"
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>, forcedKind: AttachmentKind?) {
        switch result {
        case .failure(let error):
            attachmentError = error.localizedDescription
        case .success(let urls):
            attachmentError = nil
            for url in urls {
                addAttachment(from: url, forcedKind: forcedKind)
            }
        }
    }

    /// `.fileImporter` hands us security-scoped URLs — reading their bytes
    /// requires bracketing with `start`/`stopAccessingSecurityScopedResource`.
    private func addAttachment(from url: URL, forcedKind: AttachmentKind?) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            guard data.count <= Self.maxAttachmentBytes else {
                attachmentError = "\(url.lastPathComponent) pesa más de \(Self.maxAttachmentMB) MB — no se adjuntó."
                return
            }
            let utType = UTType(filenameExtension: url.pathExtension)
            let kind = forcedKind ?? Self.attachmentKind(for: utType)
            let mimeType = utType?.preferredMIMEType ?? "application/octet-stream"
            pendingAttachments.append(
                Attachment(kind: kind, fileName: url.lastPathComponent, mimeType: mimeType, data: data)
            )
        } catch {
            attachmentError = "No se pudo leer \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private static func attachmentKind(for utType: UTType?) -> AttachmentKind {
        guard let utType else { return .document }
        if utType.conforms(to: .image) { return .image }
        if utType.conforms(to: .pdf) { return .pdf }
        if utType.conforms(to: .audio) { return .audio }
        return .document
    }
}
