import Combine
import Foundation

@MainActor
final class MediaExtractViewModel: ObservableObject {
    @Published private(set) var importedFileURL: URL?
    @Published private(set) var mediaInfo: MediaInfo?
    @Published var selectedOption: MediaExtractOption = .video
    @Published private(set) var isAnalyzing = false
    @Published private(set) var isExtracting = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusMessage = ""
    @Published private(set) var outputURL: URL?
    @Published private(set) var outputSaveMessage: String?
    @Published private(set) var latestCommand: String?
    @Published private(set) var executionLogLines: [String] = []
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
        resetForNewSelection()
        isAnalyzing = true
        statusMessage = "Importing media..."
        defer { isAnalyzing = false }

        do {
            let fileService = self.fileService
            let importedURL = try await Task.detached(priority: .userInitiated) {
                try fileService.importFile(from: url)
            }.value
            importedFileURL = importedURL
            statusMessage = "Ready to extract."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusMessage = "Unable to import the selected source."
        }
    }

    func importAndAnalyze(data: Data, suggestedFileExtension: String) async {
        resetForNewSelection()
        isAnalyzing = true
        statusMessage = "Importing media..."
        defer { isAnalyzing = false }

        do {
            let fileService = self.fileService
            let importedURL = try await Task.detached(priority: .userInitiated) {
                try fileService.importMediaData(data, suggestedFileExtension: suggestedFileExtension)
            }.value
            importedFileURL = importedURL
            statusMessage = "Ready to extract."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusMessage = "Unable to import the selected source."
        }
    }

    func extract() async {
        guard !isExtracting, let importedFileURL = importedFileURL else {
            return
        }

        let mediaInfo = mediaInfo ?? fallbackMediaInfo(for: importedFileURL)

        isExtracting = true
        progress = 0
        outputURL = nil
        errorMessage = nil
        statusMessage = "Preparing extraction..."
        setExecutionPipeline(preparingPercent: 0, status: "Processing")

        do {
            let extractSubfolder = "Extracted/Video"
            let directOutput = try fileService.makeDirectOutputURL(
                for: importedFileURL,
                preferredExtension: selectedOption.outputExtension,
                preferredDirectoryURL: nil,
                fallbackOutputDirectoryName: extractSubfolder
            )
            let outputURL = directOutput.url

            let arguments = CommandBuilder.mediaExtractArguments(
                inputURL: importedFileURL,
                outputURL: outputURL,
                option: selectedOption,
                mediaInfo: mediaInfo
            )

            latestCommand = CommandBuilder.displayString(for: arguments)
            statusMessage = "Extracting..."

            let result = try await ffmpegService.executeConversion(
                arguments: arguments,
                estimatedDuration: mediaInfo.duration,
                outputURL: outputURL
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
                throw FFmpegServiceError.failed(message: "Extraction finished, but output file was not found at \(result.outputURL.path)")
            }

            self.outputURL = result.outputURL
            outputSaveMessage = "Saved in catMedia: \(directOutput.storageDirectoryURL.path)"
            latestCommand = result.commandDescription
            statusMessage = "Extraction complete."
            setExecutionPipeline(preparingPercent: 100, status: "Success")
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusMessage = "Extraction failed."
            setExecutionPipeline(preparingPercent: Int((progress * 100).rounded()), status: "Failed")
        }

        isExtracting = false
    }

    private func resetForNewSelection() {
        importedFileURL = nil
        mediaInfo = nil
        selectedOption = .video
        progress = 0
        outputURL = nil
        outputSaveMessage = nil
        latestCommand = nil
        executionLogLines = []
        lastProgressUpdate = .distantPast
        errorMessage = nil
    }

    private func shouldPublishProgress(_ value: Double) -> Bool {
        let now = Date()
        guard value >= 1 || now.timeIntervalSince(lastProgressUpdate) >= 0.08 else {
            return false
        }
        lastProgressUpdate = now
        return true
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
}
