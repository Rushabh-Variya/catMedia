import Combine
import Foundation

@MainActor
final class MediaConverterViewModel: ObservableObject {
    private let maxCommandHistoryCount = 20

    @Published private(set) var importedFileURL: URL?
    @Published private(set) var mediaInfo: MediaInfo?
    @Published private(set) var availableOptions: [ConversionOption] = []
    @Published var selectedOption: ConversionOption?
    @Published private(set) var isAnalyzing = false
    @Published private(set) var isConverting = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusMessage = ""
    @Published private(set) var outputURL: URL?
    @Published private(set) var outputSaveMessage: String?
    @Published private(set) var latestCommand: String?
    @Published private(set) var commandHistory: [String] = []
    @Published private(set) var executionLogLines: [String] = []
    @Published var successPopupMessage: String?
    @Published var errorMessage: String?

    private var lastProgressUpdate = Date.distantPast

    private let fileService: FileService
    private let ffmpegService: FFmpegService

    init(
        fileService: FileService = FileService(),
        ffmpegService: FFmpegService = FFmpegService()
    ) {
        self.fileService = fileService
        self.ffmpegService = ffmpegService
    }

    func importAndAnalyze(url: URL) async {
        await performImport {
            let fileService = self.fileService
            return try await Task.detached(priority: .userInitiated) {
                try fileService.importFile(from: url)
            }.value
        }
    }

    func importAndAnalyze(data: Data, suggestedFileExtension: String) async {
        await performImport {
            let fileService = self.fileService
            return try await Task.detached(priority: .userInitiated) {
                try fileService.importMediaData(data, suggestedFileExtension: suggestedFileExtension)
            }.value
        }
    }

    func convert() async {
        guard !isConverting, let importedFileURL, let selectedOption else {
            return
        }

        let mediaInfo = mediaInfo ?? fallbackMediaInfo(for: importedFileURL)

        isConverting = true
        progress = 0
        outputURL = nil
        outputSaveMessage = nil
        errorMessage = nil
        successPopupMessage = nil
        statusMessage = "Preparing conversion..."
        setExecutionPipeline(preparingPercent: 0, status: "Processing")

        defer { isConverting = false }

        do {
            let directOutput = try fileService.makeDirectOutputURL(
                for: importedFileURL,
                preferredExtension: selectedOption.outputExtension,
                preferredDirectoryURL: nil,
                fallbackOutputDirectoryName: "Converted"
            )

            let destinationURL = directOutput.url
            let arguments = CommandBuilder.conversionArguments(
                inputURL: importedFileURL,
                outputURL: destinationURL,
                option: selectedOption,
                mediaInfo: mediaInfo
            )

            latestCommand = CommandBuilder.displayString(for: arguments)
            if let latestCommand, !latestCommand.isEmpty {
                commandHistory.append(latestCommand)
                if commandHistory.count > maxCommandHistoryCount {
                    commandHistory.removeFirst(commandHistory.count - maxCommandHistoryCount)
                }
            }

            statusMessage = "Converting..."

            let result = try await ffmpegService.executeConversion(
                arguments: arguments,
                estimatedDuration: mediaInfo.duration,
                outputURL: destinationURL
            ) { [weak self] value in
                Task { @MainActor in
                    guard let self, self.shouldPublishProgress(value) else { return }
                    self.progress = value
                    self.setExecutionPipeline(
                        preparingPercent: Int((value * 100).rounded()),
                        status: "Processing"
                    )
                }
            }

            progress = 1

            guard FileManager.default.fileExists(atPath: result.outputURL.path) else {
                throw FFmpegServiceError.failed(message: "Conversion finished, but output file was not found at \(result.outputURL.path)")
            }

            outputURL = result.outputURL
            outputSaveMessage = "Saved in catMedia: \(directOutput.storageDirectoryURL.path)"
            latestCommand = result.commandDescription
            successPopupMessage = "Successfully Converted (Output Save in your file)"
            statusMessage = "Conversion complete."
            setExecutionPipeline(preparingPercent: 100, status: "Success")
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusMessage = "Conversion failed."
            setExecutionPipeline(preparingPercent: Int((progress * 100).rounded()), status: "Failed")
        }
    }

    private func performImport(_ importAction: () async throws -> URL) async {
        resetForNewSelection()
        isAnalyzing = true
        statusMessage = "Importing file..."
        defer { isAnalyzing = false }

        do {
            let importedURL = try await importAction()
            importedFileURL = importedURL
            availableOptions = [.convertToMP4]
            selectedOption = .convertToMP4
            statusMessage = "Ready to convert."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusMessage = "Unable to import the selected source."
        }
    }

    private func fallbackMediaInfo(for url: URL) -> MediaInfo {
        MediaInfo(
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension.lowercased(),
            formatName: url.pathExtension.lowercased(),
            duration: 0,
            bitrate: nil,
            streams: []
        )
    }

    private func resetForNewSelection() {
        importedFileURL = nil
        mediaInfo = nil
        availableOptions = []
        selectedOption = nil
        progress = 0
        outputURL = nil
        outputSaveMessage = nil
        latestCommand = nil
        executionLogLines = []
        lastProgressUpdate = .distantPast
        successPopupMessage = nil
        errorMessage = nil
    }

    private func setExecutionPipeline(preparingPercent: Int, status: String) {
        let clampedPercent = max(0, min(preparingPercent, 100))
        let resolvedStatus = (clampedPercent == 100 && status == "Processing") ? "Success" : status
        let phaseLine = clampedPercent == 100 ? "ffmpeg | End" : "ffmpeg | Start"
        executionLogLines = [
            phaseLine,
            "ffmpeg | Preparing \(clampedPercent)%",
            "ffmpeg | Status : \(resolvedStatus)"
        ]
    }

    private func shouldPublishProgress(_ value: Double) -> Bool {
        let now = Date()
        guard value >= 1 || now.timeIntervalSince(lastProgressUpdate) >= 0.08 else {
            return false
        }
        lastProgressUpdate = now
        return true
    }
}
