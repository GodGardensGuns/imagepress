import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import Darwin

@main
struct ImagePressApp: App {
    init() {
        if CommandLine.arguments.contains("--self-test") {
            do {
                try SelfTest.run()
                Darwin.exit(0)
            } catch {
                fputs("Self-test failed: \(error.localizedDescription)\n", stderr)
                Darwin.exit(1)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 980, minHeight: 650)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

struct ContentView: View {
    @StateObject private var model = CompressorModel()
    @State private var isDropTargeted = false
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField {
        case maxPixelEdge
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()
            mainContent
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(FocusBehaviorInstaller {
            focusedField = nil
        })
        .onAppear {
            focusedField = nil
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .alert("ImagePress", isPresented: Binding(
            get: { model.alertText != nil },
            set: { newValue in
                if !newValue { model.alertText = nil }
            }
        )) {
            Button("OK") { model.alertText = nil }
        } message: {
            Text(model.alertText ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ImagePress")
                    .font(.system(size: 24, weight: .semibold))
                Text("Local batch image compression")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.chooseImages()
            } label: {
                Label("Add Images", systemImage: "plus")
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button {
                model.clear()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(model.items.isEmpty || model.isWorking)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                LabeledContent("Output") {
                    Picker("", selection: $model.outputFormat) {
                        ForEach(OutputFormat.allCases) { format in
                            Text(format.label).tag(format)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }

                LabeledContent("Quality") {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { model.quality },
                                set: { model.quality = $0.rounded() }
                            ),
                            in: 1...100
                        )
                            .frame(width: 220)
                        Text("\(Int(model.quality))%")
                            .monospacedDigit()
                            .frame(width: 46, alignment: .trailing)
                    }
                }

                Toggle("Strip metadata", isOn: $model.stripMetadata)

                Spacer()
            }

            HStack(alignment: .center, spacing: 16) {
                LabeledContent("Method") {
                    Picker("", selection: $model.method) {
                        ForEach(CompressionMethod.allCases) { method in
                            Text(method.label).tag(method)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 470)
                }

                HStack(spacing: 8) {
                    Text("Max width/height")
                        .fontWeight(.medium)
                        .fixedSize(horizontal: true, vertical: false)

                    TextField("No resize", text: $model.maxEdgeText)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .maxPixelEdge)
                        .frame(width: 118)
                        .help("Optional pixel limit for the image's longest side. Leave blank to keep original dimensions.")
                }

                Button {
                    model.compress(makeZip: false)
                } label: {
                    Label("Export Folder", systemImage: "folder")
                }
                .disabled(model.items.isEmpty || model.isWorking)

                Button {
                    model.compress(makeZip: true)
                } label: {
                    Label("Export Zip", systemImage: "archivebox")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.items.isEmpty || model.isWorking)

                if model.isWorking {
                    Button {
                        model.cancelCompression()
                    } label: {
                        Label(model.isCancelling ? "Cancelling" : "Cancel", systemImage: "xmark.circle")
                    }
                    .keyboardShortcut(".", modifiers: [.command])
                    .disabled(model.isCancelling)
                }

                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var mainContent: some View {
        if model.items.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "photo.on.rectangle.angled")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                Text("Drop images or folders here")
                    .font(.title3.weight(.medium))
                Text("JPEG, PNG, WebP, AVIF, HEIC, TIFF, BMP, GIF, and common camera RAW files are accepted.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
                Button {
                    model.chooseImages()
                } label: {
                    Label("Choose Images", systemImage: "plus")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
        } else {
            Table(model.items) {
                TableColumn("File") { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.status.symbolName)
                            .foregroundStyle(item.status.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.url.lastPathComponent)
                                .lineLimit(1)
                            Text(item.url.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .width(min: 260, ideal: 360)

                TableColumn("Original") { item in
                    Text(ByteCountFormatter.fileSize.string(fromByteCount: item.originalSize))
                        .monospacedDigit()
                }
                .width(90)

                TableColumn("Compressed") { item in
                    Text(item.outputSize.map { ByteCountFormatter.fileSize.string(fromByteCount: $0) } ?? "-")
                        .monospacedDigit()
                }
                .width(105)

                TableColumn("Savings") { item in
                    Text(item.savingsText)
                        .monospacedDigit()
                }
                .width(78)

                TableColumn("Status") { item in
                    Text(item.status.label)
                        .lineLimit(1)
                }
                .width(min: 160, ideal: 240)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if model.isWorking {
                ProgressView(value: model.progressValue)
                    .frame(width: 170)
            }

            Text(model.summaryText)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if model.canRevealOutput {
                Button {
                    model.revealOutput()
                } label: {
                    Label("Reveal Output", systemImage: "finder")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        Task { @MainActor in
                            model.addURLs([url])
                        }
                    }
                }
            }
        }
        return accepted
    }
}

struct FocusBehaviorInstaller: NSViewRepresentable {
    let clearSwiftUIFocus: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(clearSwiftUIFocus: clearSwiftUIFocus)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.clearFocus(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.clearFocus(from: nsView)
        }
    }

    final class Coordinator {
        private var didClear = false
        private var monitoredWindow: NSWindow?
        private var eventMonitor: Any?
        private let clearSwiftUIFocus: () -> Void

        init(clearSwiftUIFocus: @escaping () -> Void) {
            self.clearSwiftUIFocus = clearSwiftUIFocus
        }

        deinit {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
        }

        func clearFocus(from view: NSView) {
            guard !didClear, let window = view.window else { return }
            didClear = true
            window.makeFirstResponder(nil)
            clearSwiftUIFocus()
            installMonitor(for: window)
        }

        private func installMonitor(for window: NSWindow) {
            guard monitoredWindow !== window else { return }

            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }

            monitoredWindow = window
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self, weak window] event in
                guard let self, let window, event.window === window else { return event }

                if event.type == .keyDown,
                   event.keyCode == 53 || event.charactersIgnoringModifiers == "\u{1b}" {
                    if self.windowHasTextFocus(window) {
                        self.clearFocus(in: window)
                        return nil
                    }
                    return event
                }

                if event.type == .leftMouseDown,
                   self.windowHasTextFocus(window),
                   !self.clickIsInsideTextField(event, window: window) {
                    self.clearFocus(in: window)
                }

                return event
            }
        }

        private func clearFocus(in window: NSWindow) {
            window.makeFirstResponder(nil)
            clearSwiftUIFocus()
        }

        private func windowHasTextFocus(_ window: NSWindow) -> Bool {
            if window.firstResponder is NSTextView {
                return true
            }

            if let responder = window.firstResponder as? NSView {
                return viewIsInsideTextField(responder)
            }

            return false
        }

        private func clickIsInsideTextField(_ event: NSEvent, window: NSWindow) -> Bool {
            guard let hitView = window.contentView?.hitTest(event.locationInWindow) else {
                return false
            }
            return viewIsInsideTextField(hitView)
        }

        private func viewIsInsideTextField(_ view: NSView) -> Bool {
            var current: NSView? = view
            while let candidate = current {
                if candidate is NSTextField {
                    return true
                }
                current = candidate.superview
            }
            return false
        }
    }
}

@MainActor
final class CompressorModel: ObservableObject {
    @Published var items: [ImageJob] = []
    @Published var outputFormat: OutputFormat = .same
    @Published var quality: Double = 80
    @Published var method: CompressionMethod = .balanced
    @Published var stripMetadata = true
    @Published var maxEdgeText = ""
    @Published var isWorking = false
    @Published var isCancelling = false
    @Published var completedCount = 0
    @Published var alertText: String?
    @Published private var lastOutputFolder: URL?
    @Published private var lastZipFile: URL?
    private var compressionTask: Task<Void, Never>?
    private var currentRunControl: CompressionRunControl?

    var progressValue: Double {
        guard !items.isEmpty else { return 0 }
        return Double(completedCount) / Double(items.count)
    }

    var canRevealOutput: Bool {
        lastZipFile != nil || lastOutputFolder != nil
    }

    var summaryText: String {
        if isCancelling {
            return "Cancelling compression"
        }

        if isWorking {
            return "Compressing \(completedCount) of \(items.count)"
        }

        guard !items.isEmpty else {
            return "No images added"
        }

        let done = items.filter { $0.status.isDone }.count
        let failed = items.filter { $0.status.isFailed }.count
        let cancelled = items.filter { $0.status.isCancelled }.count
        if done > 0 || failed > 0 || cancelled > 0 {
            return "\(done) finished, \(failed) failed, \(cancelled) cancelled, \(items.count) total"
        }
        return "\(items.count) images ready"
    }

    func chooseImages() {
        let panel = NSOpenPanel()
        panel.title = "Choose images or folders"
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.resolvesAliases = true
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                self?.addURLs(panel.urls)
            }
        }
    }

    func addURLs(_ urls: [URL]) {
        let existingPaths = Set(items.map { $0.url.standardizedFileURL.path })

        Task.detached(priority: .userInitiated) {
            let discovered = ImageFileFinder.expand(urls)
            let unique = discovered.filter { !existingPaths.contains($0.standardizedFileURL.path) }
            let newItems = unique.map { url in
                ImageJob(url: url, originalSize: FileUtilities.fileSize(url))
            }

            await MainActor.run {
                if newItems.isEmpty {
                    self.alertText = "No new supported images were found."
                } else {
                    self.items.append(contentsOf: newItems)
                }
            }
        }
    }

    func clear() {
        guard !isWorking else { return }
        items.removeAll()
        completedCount = 0
        isCancelling = false
        lastOutputFolder = nil
        lastZipFile = nil
    }

    func cancelCompression() {
        guard isWorking else { return }
        isCancelling = true
        compressionTask?.cancel()
        currentRunControl?.cancel()
    }

    func compress(makeZip: Bool) {
        guard !items.isEmpty else {
            alertText = "Add images first."
            return
        }

        guard let maxEdge = parsedMaxEdge else {
            alertText = "Max width/height must be empty or a whole number of pixels."
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Choose output folder"
        panel.prompt = makeZip ? "Export Zip" : "Export"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard let self, response == .OK, let destination = panel.url else { return }
            Task { @MainActor in
                self.startCompression(in: destination, makeZip: makeZip, maxEdge: maxEdge)
            }
        }
    }

    func revealOutput() {
        if let lastZipFile {
            NSWorkspace.shared.activateFileViewerSelecting([lastZipFile])
        } else if let lastOutputFolder {
            NSWorkspace.shared.activateFileViewerSelecting([lastOutputFolder])
        }
    }

    private var parsedMaxEdge: Int? {
        let trimmed = maxEdgeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        guard let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    private func startCompression(in destination: URL, makeZip: Bool, maxEdge: Int) {
        isWorking = true
        isCancelling = false
        completedCount = 0
        lastOutputFolder = nil
        lastZipFile = nil
        compressionTask?.cancel()

        for index in items.indices {
            items[index].resetForRun()
        }

        let settings = CompressionSettings(
            outputFormat: outputFormat,
            quality: quality,
            method: method,
            stripMetadata: stripMetadata,
            maxPixelEdge: maxEdge
        )
        let jobs = items
        let exportFolder: URL
        let exportBaseName = "ImagePress Export \(FileUtilities.timestamp())"

        do {
            if makeZip {
                exportFolder = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ImagePress-\(UUID().uuidString)", isDirectory: true)
                    .appendingPathComponent(exportBaseName, isDirectory: true)
            } else {
                exportFolder = try FileUtilities.uniqueDirectory(
                    parent: destination,
                    baseName: exportBaseName
                )
            }
            try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
        } catch {
            isWorking = false
            alertText = "Could not prepare the export: \(error.localizedDescription)"
            return
        }

        let runControl = CompressionRunControl()
        currentRunControl = runControl

        compressionTask = Task.detached(priority: .userInitiated) {
            var usedNames = Set<String>()
            var wasCancelled = false

            for job in jobs {
                do {
                    try runControl.checkCancellation()
                } catch is CancellationError {
                    wasCancelled = true
                    break
                } catch {
                    break
                }

                await MainActor.run {
                    self.updateJob(id: job.id) { item in
                        item.status = .processing
                    }
                }

                do {
                    let outputURL = try ImageCompressor.compress(
                        input: job.url,
                        outputDirectory: exportFolder,
                        settings: settings,
                        usedFileNames: &usedNames,
                        control: runControl
                    )
                    try runControl.checkCancellation()
                    let outputSize = FileUtilities.fileSize(outputURL)
                    await MainActor.run {
                        self.updateJob(id: job.id) { item in
                            item.outputURL = outputURL
                            item.outputSize = outputSize
                            item.status = .done
                        }
                        self.completedCount += 1
                    }
                } catch is CancellationError {
                    wasCancelled = true
                    await MainActor.run {
                        self.updateJob(id: job.id) { item in
                            item.status = .cancelled
                        }
                        self.completedCount += 1
                    }
                    break
                } catch {
                    await MainActor.run {
                        self.updateJob(id: job.id) { item in
                            item.status = .failed(error.localizedDescription)
                        }
                        self.completedCount += 1
                    }
                }
            }

            var zipURL: URL?
            if makeZip && !wasCancelled {
                do {
                    try runControl.checkCancellation()
                    zipURL = try FileUtilities.uniqueFile(parent: destination, baseName: exportBaseName, extensionName: "zip")
                    try ZipWriter.zip(folder: exportFolder, to: zipURL!, control: runControl)
                } catch is CancellationError {
                    wasCancelled = true
                    if let zipURL {
                        try? FileManager.default.removeItem(at: zipURL)
                    }
                } catch {
                    await MainActor.run {
                        self.alertText = "Zip export failed: \(error.localizedDescription)"
                    }
                }

                try? FileManager.default.removeItem(at: exportFolder.deletingLastPathComponent())
            }

            let finalZipURL = wasCancelled ? nil : zipURL
            let finalOutputFolder = makeZip ? nil : exportFolder
            let finalWasCancelled = wasCancelled
            await MainActor.run {
                if finalWasCancelled {
                    self.markWaitingJobsCancelled()
                }
                self.lastOutputFolder = finalOutputFolder
                self.lastZipFile = finalZipURL
                self.isWorking = false
                self.isCancelling = false
                self.currentRunControl = nil
                self.compressionTask = nil
            }
        }
    }

    private func updateJob(id: UUID, _ update: (inout ImageJob) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        update(&items[index])
    }

    private func markWaitingJobsCancelled() {
        for index in items.indices where items[index].status == .waiting {
            items[index].status = .cancelled
        }
    }
}

struct ImageJob: Identifiable {
    let id = UUID()
    let url: URL
    let originalSize: Int64
    var outputSize: Int64?
    var outputURL: URL?
    var status: JobStatus = .waiting

    mutating func resetForRun() {
        outputSize = nil
        outputURL = nil
        status = .waiting
    }

    var savingsText: String {
        guard let outputSize, originalSize > 0 else { return "-" }
        let delta = Double(originalSize - outputSize) / Double(originalSize)
        let percent = Int((delta * 100).rounded())
        return "\(percent)%"
    }
}

enum JobStatus: Equatable {
    case waiting
    case processing
    case done
    case cancelled
    case failed(String)

    var label: String {
        switch self {
        case .waiting:
            return "Waiting"
        case .processing:
            return "Compressing"
        case .done:
            return "Done"
        case .cancelled:
            return "Cancelled"
        case .failed(let message):
            return message
        }
    }

    var symbolName: String {
        switch self {
        case .waiting:
            return "clock"
        case .processing:
            return "arrow.triangle.2.circlepath"
        case .done:
            return "checkmark.circle.fill"
        case .cancelled:
            return "xmark.circle"
        case .failed:
            return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .waiting:
            return .secondary
        case .processing:
            return .accentColor
        case .done:
            return .green
        case .cancelled:
            return .orange
        case .failed:
            return .red
        }
    }

    var isDone: Bool {
        if case .done = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case same
    case jpeg
    case png
    case webp
    case avif
    case heic
    case tiff
    case gif
    case bmp
    case jpeg2000

    var id: String { rawValue }

    var label: String {
        switch self {
        case .same: return "Same as input"
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .webp: return "WebP"
        case .avif: return "AVIF"
        case .heic: return "HEIC"
        case .tiff: return "TIFF"
        case .gif: return "GIF"
        case .bmp: return "BMP"
        case .jpeg2000: return "JPEG 2000"
        }
    }

    var fileExtension: String {
        switch self {
        case .same: return "jpg"
        case .jpeg: return "jpg"
        case .png: return "png"
        case .webp: return "webp"
        case .avif: return "avif"
        case .heic: return "heic"
        case .tiff: return "tiff"
        case .gif: return "gif"
        case .bmp: return "bmp"
        case .jpeg2000: return "jp2"
        }
    }

    var typeIdentifier: String? {
        switch self {
        case .same, .webp:
            return nil
        case .jpeg:
            return "public.jpeg"
        case .png:
            return "public.png"
        case .avif:
            return "public.avif"
        case .heic:
            return "public.heic"
        case .tiff:
            return "public.tiff"
        case .gif:
            return "com.compuserve.gif"
        case .bmp:
            return "com.microsoft.bmp"
        case .jpeg2000:
            return "public.jpeg-2000"
        }
    }

    var requiresOpaqueBackground: Bool {
        switch self {
        case .jpeg, .avif, .heic, .bmp, .jpeg2000:
            return true
        default:
            return false
        }
    }

    static func resolved(for inputURL: URL, requested: OutputFormat) -> OutputFormat {
        guard requested == .same else { return requested }

        switch inputURL.pathExtension.lowercased() {
        case "jpg", "jpeg", "jpe":
            return .jpeg
        case "png":
            return .png
        case "webp":
            return .webp
        case "avif":
            return .avif
        case "heic", "heif":
            return .heic
        case "tif", "tiff":
            return .tiff
        case "gif":
            return .gif
        case "bmp":
            return .bmp
        case "jp2", "j2k", "jpf", "jpx":
            return .jpeg2000
        default:
            return .jpeg
        }
    }

    static let writableTypeIdentifiers: Set<String> = {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return Set(identifiers)
    }()
}

enum CompressionMethod: String, CaseIterable, Identifiable {
    case balanced
    case smaller
    case detail
    case lossless

    var id: String { rawValue }

    var label: String {
        switch self {
        case .balanced:
            return "Balanced"
        case .smaller:
            return "Smaller Files"
        case .detail:
            return "Preserve Detail"
        case .lossless:
            return "Lossless When Possible"
        }
    }

    func quality(from sliderValue: Double) -> Double {
        let normalized = min(max(sliderValue / 100, 0.01), 1.0)
        switch self {
        case .balanced:
            return normalized
        case .smaller:
            return min(max(normalized * 0.72, 0.01), 0.82)
        case .detail:
            return max(normalized, 0.78)
        case .lossless:
            return 1.0
        }
    }

    func webPArguments(quality: Double, input: URL, output: URL, stripMetadata: Bool) -> [String] {
        let webPQuality = Int((self.quality(from: quality) * 100).rounded())
        var arguments: [String]

        switch self {
        case .balanced:
            arguments = ["-quiet", "-q", "\(webPQuality)", "-m", "4"]
        case .smaller:
            arguments = ["-quiet", "-q", "\(webPQuality)", "-m", "6", "-af"]
        case .detail:
            arguments = ["-quiet", "-q", "\(max(webPQuality, 82))", "-m", "4", "-sharp_yuv"]
        case .lossless:
            arguments = ["-quiet", "-lossless", "-z", "9"]
        }

        if stripMetadata {
            arguments += ["-metadata", "none"]
        } else {
            arguments += ["-metadata", "all"]
        }

        arguments += [input.path, "-o", output.path]
        return arguments
    }

    func avifArguments(quality: Double, input: URL, output: URL, stripMetadata: Bool) -> [String] {
        let avifQuality = Int((self.quality(from: quality) * 100).rounded())
        var arguments: [String]

        switch self {
        case .balanced:
            arguments = ["--qcolor", "\(avifQuality)", "--qalpha", "\(avifQuality)", "--speed", "6", "--jobs", "all", "--yuv", "420"]
        case .smaller:
            arguments = ["--qcolor", "\(avifQuality)", "--qalpha", "\(avifQuality)", "--speed", "3", "--jobs", "all", "--yuv", "420"]
        case .detail:
            let detailQuality = max(avifQuality, 84)
            arguments = ["--qcolor", "\(detailQuality)", "--qalpha", "\(detailQuality)", "--speed", "5", "--jobs", "all", "--yuv", "444"]
        case .lossless:
            arguments = ["--lossless", "--speed", "3", "--jobs", "all"]
        }

        if stripMetadata {
            arguments += ["--ignore-exif", "--ignore-xmp"]
        }

        arguments += [input.path, output.path]
        return arguments
    }

    func pngQuantArguments(quality: Double, input: URL, output: URL, stripMetadata: Bool) -> [String] {
        let maxQuality = max(35, min(95, Int(quality.rounded())))
        let minQuality = max(5, maxQuality - 30)
        var arguments = [
            "--force",
            "--quality", "\(minQuality)-\(maxQuality)",
            "--speed", "1",
            "--output", output.path
        ]

        if stripMetadata {
            arguments.append("--strip")
        }

        arguments += ["--", input.path]
        return arguments
    }

    func oxiPNGArguments(input: URL, output: URL, stripMetadata: Bool) -> [String] {
        let level: String
        switch self {
        case .balanced:
            level = "3"
        case .smaller:
            level = "5"
        case .detail:
            level = "2"
        case .lossless:
            level = "4"
        }

        var arguments = ["--quiet", "--opt", level, "--out", output.path]
        if stripMetadata {
            arguments += ["--strip", "safe"]
        }
        arguments.append(input.path)
        return arguments
    }
}

struct CompressionSettings {
    let outputFormat: OutputFormat
    let quality: Double
    let method: CompressionMethod
    let stripMetadata: Bool
    let maxPixelEdge: Int
}

enum ImagePressError: LocalizedError {
    case cannotReadImage(URL)
    case cannotCreateImage(URL)
    case cannotCreateDestination(URL)
    case unsupportedOutput(String)
    case writeFailed(URL)
    case webPEncoderMissing
    case avifEncoderMissing
    case processFailed(String)
    case cannotCreateContext

    var errorDescription: String? {
        switch self {
        case .cannotReadImage(let url):
            return "Could not read \(url.lastPathComponent)"
        case .cannotCreateImage(let url):
            return "Could not decode \(url.lastPathComponent)"
        case .cannotCreateDestination(let url):
            return "Could not create \(url.lastPathComponent)"
        case .unsupportedOutput(let format):
            return "\(format) export is not supported by this Mac"
        case .writeFailed(let url):
            return "Could not write \(url.lastPathComponent)"
        case .webPEncoderMissing:
            return "WebP export needs cwebp at /opt/homebrew/bin/cwebp or /usr/local/bin/cwebp"
        case .avifEncoderMissing:
            return "AVIF export needs avifenc at /opt/homebrew/bin/avifenc or /usr/local/bin/avifenc"
        case .processFailed(let message):
            return message.isEmpty ? "The encoder failed" : message
        case .cannotCreateContext:
            return "Could not prepare the image"
        }
    }
}

final class CompressionRunControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var activeProcess: Process?

    var isCancelled: Bool {
        lock.lock()
        let value = cancelled
        lock.unlock()
        return value
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = activeProcess
        lock.unlock()

        if let process, process.isRunning {
            process.terminate()
        }
    }

    func checkCancellation() throws {
        if isCancelled || Task.isCancelled {
            throw CancellationError()
        }
    }

    func setActiveProcess(_ process: Process?) {
        lock.lock()
        activeProcess = process
        let shouldCancel = cancelled
        lock.unlock()

        if shouldCancel, let process, process.isRunning {
            process.terminate()
        }
    }
}

enum ImageCompressor {
    static func compress(
        input: URL,
        outputDirectory: URL,
        settings: CompressionSettings,
        usedFileNames: inout Set<String>,
        control: CompressionRunControl? = nil
    ) throws -> URL {
        try control?.checkCancellation()

        guard let source = CGImageSourceCreateWithURL(input as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            throw ImagePressError.cannotReadImage(input)
        }

        let format = OutputFormat.resolved(for: input, requested: settings.outputFormat)
        let outputURL = try FileUtilities.uniqueFile(
            parent: outputDirectory,
            baseName: input.deletingPathExtension().lastPathComponent,
            extensionName: format.fileExtension,
            usedFileNames: &usedFileNames
        )

        do {
            if format == .webp {
                try encodeWebP(source: source, input: input, output: outputURL, settings: settings, control: control)
            } else if format == .avif {
                try encodeAVIF(source: source, input: input, output: outputURL, settings: settings, control: control)
            } else if format == .png {
                try encodePNG(source: source, input: input, output: outputURL, settings: settings, control: control)
            } else {
                try encodeImageIO(source: source, input: input, output: outputURL, format: format, settings: settings, control: control)
            }
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        }

        try control?.checkCancellation()
        return outputURL
    }

    private static func encodePNG(
        source: CGImageSource,
        input: URL,
        output: URL,
        settings: CompressionSettings,
        control: CompressionRunControl?
    ) throws {
        try control?.checkCancellation()

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImagePress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let rawPNG = tempDirectory.appendingPathComponent("raw.png")
        let quantizedPNG = tempDirectory.appendingPathComponent("quantized.png")
        let optimizedPNG = tempDirectory.appendingPathComponent("optimized.png")
        let image = try imageForPNGCompatibleEncoding(
            transformedImage(from: source, input: input, maxPixelEdge: settings.maxPixelEdge)
        )

        guard let destination = CGImageDestinationCreateWithURL(rawPNG as CFURL, "public.png" as CFString, 1, nil) else {
            throw ImagePressError.cannotCreateDestination(rawPNG)
        }
        CGImageDestinationAddImage(destination, image, destinationProperties(from: source, format: .png, settings: settings))
        guard CGImageDestinationFinalize(destination) else {
            throw ImagePressError.writeFailed(rawPNG)
        }

        try control?.checkCancellation()

        var candidate = rawPNG
        if settings.method == .smaller, let pngquantURL = PNGQuantLocator.executableURL() {
            do {
                try ProcessRunner.run(
                    executable: pngquantURL,
                    arguments: settings.method.pngQuantArguments(
                        quality: settings.quality,
                        input: rawPNG,
                        output: quantizedPNG,
                        stripMetadata: settings.stripMetadata
                    ),
                    control: control
                )
                if FileManager.default.fileExists(atPath: quantizedPNG.path) {
                    candidate = quantizedPNG
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                candidate = rawPNG
            }
        }

        try control?.checkCancellation()

        if let oxipngURL = OxiPNGLocator.executableURL() {
            do {
                try ProcessRunner.run(
                    executable: oxipngURL,
                    arguments: settings.method.oxiPNGArguments(
                        input: candidate,
                        output: optimizedPNG,
                        stripMetadata: settings.stripMetadata
                    ),
                    control: control
                )
                if FileManager.default.fileExists(atPath: optimizedPNG.path) {
                    candidate = optimizedPNG
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Keep the best candidate we already have.
            }
        }

        try FileManager.default.copyItem(at: candidate, to: output)

        if shouldPreferOriginalPNG(input: input, output: output, settings: settings) {
            try? FileManager.default.removeItem(at: output)
            try FileManager.default.copyItem(at: input, to: output)
        }

        try control?.checkCancellation()
    }

    private static func encodeImageIO(
        source: CGImageSource,
        input: URL,
        output: URL,
        format: OutputFormat,
        settings: CompressionSettings,
        control: CompressionRunControl?
    ) throws {
        try control?.checkCancellation()

        guard let typeIdentifier = format.typeIdentifier else {
            throw ImagePressError.unsupportedOutput(format.label)
        }
        guard OutputFormat.writableTypeIdentifiers.contains(typeIdentifier) else {
            throw ImagePressError.unsupportedOutput(format.label)
        }

        var image = try transformedImage(from: source, input: input, maxPixelEdge: settings.maxPixelEdge)
        if format.requiresOpaqueBackground {
            image = try flattenedOverWhite(image)
        }

        try control?.checkCancellation()

        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, typeIdentifier as CFString, 1, nil) else {
            throw ImagePressError.cannotCreateDestination(output)
        }

        let properties = destinationProperties(from: source, format: format, settings: settings)
        CGImageDestinationAddImage(destination, image, properties)

        guard CGImageDestinationFinalize(destination) else {
            throw ImagePressError.writeFailed(output)
        }

        try control?.checkCancellation()

        if shouldPreferOriginal(input: input, output: output, format: format, settings: settings) {
            try? FileManager.default.removeItem(at: output)
            try FileManager.default.copyItem(at: input, to: output)
        }
    }

    private static func encodeWebP(
        source: CGImageSource,
        input: URL,
        output: URL,
        settings: CompressionSettings,
        control: CompressionRunControl?
    ) throws {
        try control?.checkCancellation()

        guard let cwebpURL = WebPEncoderLocator.executableURL() else {
            throw ImagePressError.webPEncoderMissing
        }

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImagePress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let tempPNG = tempDirectory.appendingPathComponent("source.png")
        var image = try transformedImage(from: source, input: input, maxPixelEdge: settings.maxPixelEdge)
        image = try imageForPNGCompatibleEncoding(image)

        guard let destination = CGImageDestinationCreateWithURL(tempPNG as CFURL, "public.png" as CFString, 1, nil) else {
            throw ImagePressError.cannotCreateDestination(tempPNG)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ImagePressError.writeFailed(tempPNG)
        }

        try control?.checkCancellation()

        try ProcessRunner.run(
            executable: cwebpURL,
            arguments: settings.method.webPArguments(
                quality: settings.quality,
                input: tempPNG,
                output: output,
                stripMetadata: settings.stripMetadata
            ),
            control: control
        )
    }

    private static func encodeAVIF(
        source: CGImageSource,
        input: URL,
        output: URL,
        settings: CompressionSettings,
        control: CompressionRunControl?
    ) throws {
        try control?.checkCancellation()

        guard let avifencURL = AVIFEncoderLocator.executableURL() else {
            throw ImagePressError.avifEncoderMissing
        }

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImagePress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let tempPNG = tempDirectory.appendingPathComponent("source.png")
        let image = try imageForPNGCompatibleEncoding(
            transformedImage(from: source, input: input, maxPixelEdge: settings.maxPixelEdge)
        )

        guard let destination = CGImageDestinationCreateWithURL(tempPNG as CFURL, "public.png" as CFString, 1, nil) else {
            throw ImagePressError.cannotCreateDestination(tempPNG)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ImagePressError.writeFailed(tempPNG)
        }

        try control?.checkCancellation()

        try ProcessRunner.run(
            executable: avifencURL,
            arguments: settings.method.avifArguments(
                quality: settings.quality,
                input: tempPNG,
                output: output,
                stripMetadata: settings.stripMetadata
            ),
            control: control
        )
    }

    private static func transformedImage(from source: CGImageSource, input: URL, maxPixelEdge: Int) throws -> CGImage {
        var pixelLimit = maxPixelEdge

        if pixelLimit == 0,
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int {
            pixelLimit = max(width, height)
        }

        var options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        if pixelLimit > 0 {
            options[kCGImageSourceThumbnailMaxPixelSize] = pixelLimit
        }

        if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return image
        }

        if let image = CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) {
            return image
        }

        throw ImagePressError.cannotCreateImage(input)
    }

    private static func destinationProperties(
        from source: CGImageSource,
        format: OutputFormat,
        settings: CompressionSettings
    ) -> CFDictionary {
        let properties = NSMutableDictionary()

        if !settings.stripMetadata,
           let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary? {
            for (key, value) in sourceProperties {
                if let key = key as? NSCopying {
                    properties.setObject(value, forKey: key)
                }
            }
            properties.removeObject(forKey: kCGImagePropertyOrientation)
        }

        switch format {
        case .jpeg, .avif, .heic, .jpeg2000:
            let quality = settings.method.quality(from: settings.quality)
            properties.setObject(quality as NSNumber, forKey: kCGImageDestinationLossyCompressionQuality as NSString)
        case .png, .tiff, .gif, .bmp, .same, .webp:
            break
        }

        return properties
    }

    private static func shouldPreferOriginal(
        input: URL,
        output: URL,
        format: OutputFormat,
        settings: CompressionSettings
    ) -> Bool {
        guard settings.maxPixelEdge == 0 else { return false }
        guard OutputFormat.resolved(for: input, requested: .same) == format else { return false }

        let originalSize = FileUtilities.fileSize(input)
        let outputSize = FileUtilities.fileSize(output)
        return originalSize > 0 && outputSize > originalSize
    }

    private static func shouldPreferOriginalPNG(input: URL, output: URL, settings: CompressionSettings) -> Bool {
        guard settings.maxPixelEdge == 0 else { return false }
        guard input.pathExtension.lowercased() == "png" else { return false }

        let originalSize = FileUtilities.fileSize(input)
        let outputSize = FileUtilities.fileSize(output)
        return originalSize > 0 && outputSize > originalSize
    }

    private static func flattenedOverWhite(_ image: CGImage) throws -> CGImage {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImagePressError.cannotCreateContext
        }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(rect)
        context.draw(image, in: rect)

        guard let flattened = context.makeImage() else {
            throw ImagePressError.cannotCreateContext
        }
        return flattened
    }

    private static func imageForPNGCompatibleEncoding(_ image: CGImage) throws -> CGImage {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImagePressError.cannotCreateContext
        }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.clear(rect)
        context.draw(image, in: rect)

        guard let converted = context.makeImage() else {
            throw ImagePressError.cannotCreateContext
        }
        return converted
    }
}

enum ImageFileFinder {
    private static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "png", "webp", "avif", "heic", "heif", "tif", "tiff",
        "gif", "bmp", "ico", "jp2", "j2k", "jpf", "jpx", "psd",
        "dng", "raw", "cr2", "cr3", "crw", "nef", "nrw", "arw", "srf", "sr2",
        "orf", "rw2", "raf", "pef", "rwl", "iiq", "3fr", "fff"
    ]

    static func expand(_ urls: [URL]) -> [URL] {
        let fileManager = FileManager.default
        var results: [URL] = []

        for url in urls {
            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                if let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    for case let child as URL in enumerator {
                        guard isSupported(child) else { continue }
                        results.append(child)
                    }
                }
            } else if isSupported(url) {
                results.append(url)
            }
        }

        return results.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}

enum FileUtilities {
    static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }

    static func uniqueDirectory(parent: URL, baseName: String) throws -> URL {
        var candidate = parent.appendingPathComponent(baseName, isDirectory: true)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(baseName) \(index)", isDirectory: true)
            index += 1
        }
        return candidate
    }

    static func uniqueFile(parent: URL, baseName: String, extensionName: String) throws -> URL {
        var usedNames = Set<String>()
        return try uniqueFile(parent: parent, baseName: baseName, extensionName: extensionName, usedFileNames: &usedNames)
    }

    static func uniqueFile(
        parent: URL,
        baseName: String,
        extensionName: String,
        usedFileNames: inout Set<String>
    ) throws -> URL {
        let safeBase = sanitizedFileName(baseName).isEmpty ? "image" : sanitizedFileName(baseName)
        let normalizedExtension = extensionName.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        var candidateName = "\(safeBase).\(normalizedExtension)"
        var candidate = parent.appendingPathComponent(candidateName)
        var index = 2

        while usedFileNames.contains(candidateName.lowercased()) || FileManager.default.fileExists(atPath: candidate.path) {
            candidateName = "\(safeBase)-\(index).\(normalizedExtension)"
            candidate = parent.appendingPathComponent(candidateName)
            index += 1
        }

        usedFileNames.insert(candidateName.lowercased())
        return candidate
    }

    private static func sanitizedFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return name.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum WebPEncoderLocator {
    static func executableURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "cwebp", withExtension: nil, subdirectory: "bin"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        for path in ["/opt/homebrew/bin/cwebp", "/usr/local/bin/cwebp"] where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return nil
    }
}

enum AVIFEncoderLocator {
    static func executableURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "avifenc", withExtension: nil, subdirectory: "bin"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        for path in ["/opt/homebrew/bin/avifenc", "/usr/local/bin/avifenc"] where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return nil
    }
}

enum PNGQuantLocator {
    static func executableURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "pngquant", withExtension: nil, subdirectory: "bin"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        for path in ["/opt/homebrew/bin/pngquant", "/usr/local/bin/pngquant"] where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return nil
    }
}

enum OxiPNGLocator {
    static func executableURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "oxipng", withExtension: nil, subdirectory: "bin"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        for path in ["/opt/homebrew/bin/oxipng", "/usr/local/bin/oxipng"] where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return nil
    }
}

enum ProcessRunner {
    static func run(
        executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        control: CompressionRunControl? = nil
    ) throws {
        try control?.checkCancellation()

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        control?.setActiveProcess(process)
        defer {
            control?.setActiveProcess(nil)
        }

        if Task.isCancelled || control?.isCancelled == true {
            process.terminate()
        }

        process.waitUntilExit()

        if Task.isCancelled || control?.isCancelled == true {
            throw CancellationError()
        }

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData + outputData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ImagePressError.processFailed(message)
        }
    }
}

enum ZipWriter {
    static func zip(folder: URL, to output: URL, control: CompressionRunControl? = nil) throws {
        try ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-qry", output.path, "."],
            currentDirectory: folder,
            control: control
        )
    }
}

extension ByteCountFormatter {
    static let fileSize: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()
}

enum SelfTest {
    static func run() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImagePressSelfTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source.png")
        try makeTestPNG(at: source)

        let output = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        var usedNames = Set<String>()
        let settings = CompressionSettings(
            outputFormat: .jpeg,
            quality: 72,
            method: .balanced,
            stripMetadata: true,
            maxPixelEdge: 0
        )
        let jpeg = try ImageCompressor.compress(input: source, outputDirectory: output, settings: settings, usedFileNames: &usedNames)
        print("JPEG ok: \(jpeg.lastPathComponent)")

        let pngSettings = CompressionSettings(
            outputFormat: .png,
            quality: 70,
            method: .smaller,
            stripMetadata: true,
            maxPixelEdge: 0
        )
        let png = try ImageCompressor.compress(input: source, outputDirectory: output, settings: pngSettings, usedFileNames: &usedNames)
        guard FileUtilities.fileSize(png) <= FileUtilities.fileSize(source) else {
            throw ImagePressError.processFailed("PNG output grew from \(FileUtilities.fileSize(source)) to \(FileUtilities.fileSize(png)) bytes")
        }
        print("PNG no-growth ok: \(png.lastPathComponent)")

        var webPSettings = settings
        webPSettings = CompressionSettings(
            outputFormat: .webp,
            quality: 72,
            method: .balanced,
            stripMetadata: true,
            maxPixelEdge: 0
        )
        if WebPEncoderLocator.executableURL() != nil {
            let webp = try ImageCompressor.compress(input: source, outputDirectory: output, settings: webPSettings, usedFileNames: &usedNames)
            print("WebP ok: \(webp.lastPathComponent)")
        } else {
            print("WebP skipped: cwebp missing")
        }

        if OutputFormat.writableTypeIdentifiers.contains("public.avif") {
            let avifSettings = CompressionSettings(
                outputFormat: .avif,
                quality: 72,
                method: .balanced,
                stripMetadata: true,
                maxPixelEdge: 0
            )
            let avif = try ImageCompressor.compress(input: source, outputDirectory: output, settings: avifSettings, usedFileNames: &usedNames)
            print("AVIF ok: \(avif.lastPathComponent)")
        }

        let zipWorkParent = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImagePress-\(UUID().uuidString)", isDirectory: true)
        let zipWorkFolder = zipWorkParent.appendingPathComponent("ImagePress Export Test", isDirectory: true)
        try FileManager.default.createDirectory(at: zipWorkFolder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: jpeg, to: zipWorkFolder.appendingPathComponent(jpeg.lastPathComponent))

        let zip = try FileUtilities.uniqueFile(parent: root, baseName: "ImagePress Export Test", extensionName: "zip")
        try ZipWriter.zip(folder: zipWorkFolder, to: zip)
        try FileManager.default.removeItem(at: zipWorkParent)

        guard FileManager.default.fileExists(atPath: zip.path),
              !FileManager.default.fileExists(atPath: zipWorkParent.path) else {
            throw ImagePressError.writeFailed(zip)
        }
        print("Zip cleanup ok: \(zip.lastPathComponent)")

        let cancelControl = CompressionRunControl()
        cancelControl.cancel()
        do {
            try ProcessRunner.run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["1"],
                control: cancelControl
            )
            throw ImagePressError.processFailed("Cancel test did not stop the process")
        } catch is CancellationError {
            print("Cancel ok")
        }
    }

    private static func makeTestPNG(at url: URL) throws {
        let width = 256
        let height = 160
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImagePressError.cannotCreateContext
        }

        for y in 0..<height {
            let hue = CGFloat(y) / CGFloat(height)
            context.setFillColor(NSColor(calibratedHue: hue, saturation: 0.72, brightness: 0.92, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: y, width: width, height: 1))
        }

        context.setFillColor(NSColor.white.withAlphaComponent(0.82).cgColor)
        context.fillEllipse(in: CGRect(x: 42, y: 34, width: 76, height: 76))
        context.setFillColor(NSColor.black.withAlphaComponent(0.32).cgColor)
        context.fill(CGRect(x: 132, y: 46, width: 76, height: 52))

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw ImagePressError.cannotCreateDestination(url)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ImagePressError.writeFailed(url)
        }
    }
}
