import Combine
import AVFoundation
import Foundation

@MainActor
final class MediaInfoViewModel: ObservableObject {
    @Published private(set) var importedFileURL: URL?
    @Published private(set) var mediaInfo: MediaInfo?
    @Published private(set) var metadataJSONOutput: String?
    @Published private(set) var isAnalyzing = false
    @Published private(set) var statusMessage = ""
    @Published var errorMessage: String?

    private let probeService: FFprobeService
    private let fileService: FileService
    private var selectionGeneration: Int = 0

    init(
        probeService: FFprobeService = FFprobeService(),
        fileService: FileService = FileService()
    ) {
        self.probeService = probeService
        self.fileService = fileService
    }

    func importAndAnalyze(url: URL) async {
        let generation = nextSelectionGeneration()
        log("Selection #\(generation) STEP 1: User selected file -> \(url.lastPathComponent)")
        resetForNewSelection()
        isAnalyzing = true
        statusMessage = "Importing file..."

        defer {
            if generation == selectionGeneration {
                isAnalyzing = false
            }
        }

        guard generation == selectionGeneration else { return }

        do {
            let fileService = self.fileService
            let importedURL = try await Task.detached(priority: .userInitiated) {
                try fileService.importFile(from: url)
            }.value
            importedFileURL = importedURL
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusMessage = "Unable to import the selected source."
            return
        }

        statusMessage = "Analyzing media..."
        log("Selection #\(generation) STEP 4: Starting metadata pipeline")
        guard let importedFileURL else {
            statusMessage = "Unable to import the selected source."
            return
        }

        let result = await analyzeMediaBestEffort(at: importedFileURL, presentingAs: url)
        guard generation == selectionGeneration else { return }

        let info = result.mediaInfo
        mediaInfo = info
        metadataJSONOutput = result.jsonOutput
        log("Selection #\(generation) STEP 8: UI update -> hasVideo=\(info.hasVideo), hasAudio=\(info.hasAudio), format=\(info.formatName), duration=\(info.duration), streams=\(info.streams.count)")
        if info.hasVideo || info.hasAudio {
            statusMessage = "Ready to inspect."
            errorMessage = nil
        } else {
            statusMessage = "Metadata unavailable for this file."
            if errorMessage == nil {
                errorMessage = "Metadata not found: no audio/video streams detected after all fallback stages."
            }
        }
    }

    private func resetForNewSelection() {
        importedFileURL = nil
        mediaInfo = nil
        metadataJSONOutput = nil
        errorMessage = nil
    }

    private func nextSelectionGeneration() -> Int {
        selectionGeneration += 1
        return selectionGeneration
    }

    private func analyzeMediaBestEffort(at sourceURL: URL, presentingAs originalURL: URL) async -> ProbeAnalysisResult {
        var failureReasons: [String] = []

        do {
            let directProbe = try await probeService.analyzeMedia(at: sourceURL)
            if isUsableMetadata(directProbe.mediaInfo) {
                log("Metadata stage success: direct metadata scan for \(originalURL.lastPathComponent)")
                return normalizeAnalysisResult(directProbe, presentingAs: originalURL)
            }
            let reason = "Direct metadata scan returned no audio/video streams."
            failureReasons.append(reason)
            log("Metadata stage partial: \(reason) File=\(originalURL.lastPathComponent)")
        } catch {
            let reason = failureReason(from: error)
            failureReasons.append("Direct metadata scan failed: \(reason)")
            log("Metadata stage failed: direct metadata scan error for \(originalURL.lastPathComponent): \(reason)")
        }

        let avInfo = await analyzeMediaWithAVFoundation(at: sourceURL)
        log("Metadata stage fallback: AVFoundation for \(originalURL.lastPathComponent), hasVideo=\(avInfo.hasVideo), hasAudio=\(avInfo.hasAudio), streams=\(avInfo.streams.count)")
        if !isUsableMetadata(avInfo) {
            let reason = "AVFoundation fallback returned no audio/video tracks."
            failureReasons.append(reason)
            let finalReason = "MediaInfo failure reason: \(failureReasons.joined(separator: " | "))"
            errorMessage = finalReason
            log(finalReason)
        }
        return ProbeAnalysisResult(
            mediaInfo: normalizeMetadata(avInfo, presentingAs: originalURL),
            jsonOutput: nil
        )
    }

    private func normalizeAnalysisResult(_ result: ProbeAnalysisResult, presentingAs originalURL: URL) -> ProbeAnalysisResult {
        ProbeAnalysisResult(
            mediaInfo: normalizeMetadata(result.mediaInfo, presentingAs: originalURL),
            jsonOutput: result.jsonOutput
        )
    }

    private func normalizeMetadata(_ info: MediaInfo, presentingAs originalURL: URL) -> MediaInfo {
        MediaInfo(
            fileName: originalURL.lastPathComponent,
            fileExtension: originalURL.pathExtension.lowercased(),
            formatName: info.formatName.isEmpty ? originalURL.pathExtension.lowercased() : info.formatName,
            duration: info.duration,
            bitrate: info.bitrate,
            streams: info.streams
        )
    }

    private func isUsableMetadata(_ info: MediaInfo) -> Bool {
        info.hasVideo || info.hasAudio
    }


    private func analyzeMediaWithAVFoundation(at url: URL) async -> MediaInfo {
        let asset = AVURLAsset(url: url)
        let tracks = (try? await asset.load(.tracks)) ?? []

        var streams: [MediaStream] = []
        var totalBitrate: Double = 0

        if let videoTrack = tracks.first(where: { $0.mediaType == .video }) {
            let naturalSize = (try? await videoTrack.load(.naturalSize)) ?? .zero
            let preferredTransform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
            let transformedSize = naturalSize.applying(preferredTransform)
            let width = Int(abs(transformedSize.width).rounded())
            let height = Int(abs(transformedSize.height).rounded())
            let codec = await codecName(from: videoTrack)
            let estimatedDataRate = (try? await videoTrack.load(.estimatedDataRate)) ?? 0
            let bitrate = Int(estimatedDataRate.rounded())
            totalBitrate += Double(estimatedDataRate)

            streams.append(
                MediaStream(
                    kind: .video,
                    codecName: codec,
                    codecLongName: nil,
                    profile: nil,
                    width: width > 0 ? width : nil,
                    height: height > 0 ? height : nil,
                    bitrate: bitrate > 0 ? bitrate : nil,
                    codecTagString: nil,
                    sampleRate: nil,
                    channels: nil,
                    bitDepth: nil,
                    pixelFormat: nil,
                    hasTransparency: nil
                )
            )
        }

        if let audioTrack = tracks.first(where: { $0.mediaType == .audio }) {
            let codec = await codecName(from: audioTrack)
            let estimatedDataRate = (try? await audioTrack.load(.estimatedDataRate)) ?? 0
            let bitrate = Int(estimatedDataRate.rounded())
            totalBitrate += Double(estimatedDataRate)

            streams.append(
                MediaStream(
                    kind: .audio,
                    codecName: codec,
                    codecLongName: nil,
                    profile: nil,
                    width: nil,
                    height: nil,
                    bitrate: bitrate > 0 ? bitrate : nil,
                    codecTagString: nil,
                    sampleRate: nil,
                    channels: nil,
                    bitDepth: nil,
                    pixelFormat: nil,
                    hasTransparency: nil
                )
            )
        }

        let duration = (try? await asset.load(.duration)) ?? .zero
        let durationSeconds = CMTimeGetSeconds(duration)
        let safeDuration = durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : 0
        let bitrateValue = totalBitrate > 0 ? Int(totalBitrate.rounded()) : nil

        return MediaInfo(
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension.lowercased(),
            formatName: url.pathExtension.lowercased(),
            duration: safeDuration,
            bitrate: bitrateValue,
            streams: streams
        )
    }

    private func codecName(from track: AVAssetTrack) async -> String? {
        let formatDescriptions = (try? await track.load(.formatDescriptions)) ?? []
        guard let description = formatDescriptions.first else { return nil }
        let mediaSubType = CMFormatDescriptionGetMediaSubType(description)

        let bigEndian = mediaSubType.bigEndian
        let data = Data(bytes: [
            UInt8((bigEndian >> 24) & 0xFF),
            UInt8((bigEndian >> 16) & 0xFF),
            UInt8((bigEndian >> 8) & 0xFF),
            UInt8(bigEndian & 0xFF)
        ], count: 4)

        if let value = String(data: data, encoding: .ascii) {
            return value.trimmingCharacters(in: .controlCharacters).lowercased()
        }

        return nil
    }

    private func log(_ message: String) {
        _ = message
    }

    private func failureReason(from error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return "Unknown error"
        }

        if message.localizedCaseInsensitiveContains("already specified") {
            return "Embedded FFprobe state leaked from a previous run (duplicate input argument conflict)."
        }

        if message.localizedCaseInsensitiveContains("permission denied") {
            return "Permission denied while reading the selected file."
        }

        if message.localizedCaseInsensitiveContains("no such file") {
            return "Selected file or temporary working copy was not found during analysis."
        }

        return message
    }

}
