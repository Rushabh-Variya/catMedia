import Foundation

enum FFprobeServiceError: LocalizedError {
    case invalidOutput
    case failed(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidOutput:
            "FFprobe returned an unreadable response."
        case let .failed(message):
            message
        }
    }
}

struct ProbeAnalysisResult {
    let mediaInfo: MediaInfo
    let jsonOutput: String?
}

struct FFprobeService {
    func analyzeMedia(at url: URL) async throws -> ProbeAnalysisResult {
        log("STEP 2: Copy selected file to temporary location")

        do {
            let workingCopy = try copyToLocalTemp(url: url)
            defer {
                try? FileManager.default.removeItem(at: workingCopy)
                log("Temporary copy removed: \(workingCopy.lastPathComponent)")
            }

            log("STEP 2 result: Temporary copy created -> \(workingCopy.lastPathComponent)")
            do {
                log("STEP 4: Running FFprobe metadata command")
                let command = CommandBuilder.probeArguments(for: workingCopy)
                log("Command: \(CommandBuilder.displayString(for: command))")

                let output = try await FFmpegCommandRunner.shared.runFFprobe(arguments: command)
                let jsonString = extractJSONPayload(from: output)
                log("STEP 5: Captured FFprobe output -> raw=\(output.count) chars, jsonSlice=\(jsonString.count) chars")
                log("STEP 6: Validating output JSON")

                guard !jsonString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw FFprobeServiceError.invalidOutput
                }

                guard let data = jsonString.data(using: .utf8), !data.isEmpty else {
                    throw FFprobeServiceError.invalidOutput
                }

                log("STEP 7: Parsing metadata JSON")
                let parsed = try MediaInfo.fromProbeJSON(fileURL: url, json: data)
                if !(parsed.hasVideo || parsed.hasAudio) {
                    let kinds = parsed.streams.map(\.kind.rawValue)
                    let detail = kinds.isEmpty ? "none" : kinds.joined(separator: ",")
                    throw FFprobeServiceError.failed(message: "FFprobe JSON parsed, but no audio/video streams were found (stream kinds: \(detail)).")
                }

                log("Metadata scan success (ffprobe-json): streams=\(parsed.streams.count), hasVideo=\(parsed.hasVideo), hasAudio=\(parsed.hasAudio)")
                let prettyJSON = normalizedPrettyJSON(from: jsonString, originalURL: url)
                return ProbeAnalysisResult(mediaInfo: parsed, jsonOutput: prettyJSON)
            } catch {
                let reason = failureReason(from: error)
                log("Metadata scan failed (ffprobe-json): \(reason)")

                log("STEP 4B: Running FFmpeg metadata fallback command")
                if let fallbackInfo = await analyzeFromFFmpegInfo(localURL: workingCopy, presentingAs: url) {
                    log("Metadata scan success (ffmpeg-fallback): streams=\(fallbackInfo.mediaInfo.streams.count), hasVideo=\(fallbackInfo.mediaInfo.hasVideo), hasAudio=\(fallbackInfo.mediaInfo.hasAudio)")
                    return fallbackInfo
                }

                throw FFprobeServiceError.failed(message: reason)
            }
        } catch {
            let reason = failureReason(from: error)
            log("Metadata scan failed (final): \(reason)")
            throw FFprobeServiceError.failed(message: reason)
        }
    }

    private func normalizedPrettyJSON(from jsonString: String, originalURL: URL) -> String? {
        guard let data = jsonString.data(using: .utf8) else {
            return nil
        }

        guard var object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return jsonString
        }

        if var formatObject = object["format"] as? [String: Any] {
            formatObject["filename"] = originalURL.lastPathComponent
            object["format"] = formatObject
        }

        guard JSONSerialization.isValidJSONObject(object),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8)
        else {
            return jsonString
        }

        return prettyString
    }

    private func log(_ message: String) {
        print("[catMedia][FFprobeService] \(message)")
    }

    private func extractJSONPayload(from rawOutput: String) -> String {
        guard
            let start = rawOutput.firstIndex(of: "{"),
            let end = rawOutput.lastIndex(of: "}")
        else {
            return rawOutput
        }

        return String(rawOutput[start...end])
    }

    private func copyToLocalTemp(url: URL) throws -> URL {
        let fileManager = FileManager.default
        let appSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

        if url.path.hasPrefix(fileManager.temporaryDirectory.path) || url.path.hasPrefix(appSupportDirectory.path) {
            return url
        }

        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent("ProbeCache", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
        let destination = tempDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.copyItem(at: url, to: destination)
        return destination
    }

    private func analyzeFromFFmpegInfo(localURL: URL, presentingAs originalURL: URL) async -> ProbeAnalysisResult? {
        let args = [
            "ffmpeg",
            "-hide_banner",
            "-nostdin",
            "-v", "info",
            "-i", localURL.path
        ]
        log("Fallback command: \(CommandBuilder.displayString(for: args))")

        let infoText = await FFmpegCommandRunner.shared.runFFmpegInfoAllowingFailure(arguments: args)
        guard !infoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            log("FFmpeg fallback produced empty output")
            return nil
        }

        var streams: [MediaStream] = []
        let streamLines = infoText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.localizedCaseInsensitiveContains("Stream #") }

        for line in streamLines {
            if let videoCodec = firstMatch(in: line, pattern: "Video:\\s*([^,\\s\\(]+)") {
                let resolution = parseResolution(from: line)
                let pixelFormat = parsePixelFormat(from: line)
                streams.append(
                    MediaStream(
                        kind: .video,
                        codecName: videoCodec.lowercased(),
                        codecLongName: nil,
                        profile: nil,
                        width: resolution?.0,
                        height: resolution?.1,
                        bitrate: nil,
                        codecTagString: nil,
                        sampleRate: nil,
                        channels: nil,
                        bitDepth: parseBitDepth(from: line, pixelFormat: pixelFormat),
                        pixelFormat: pixelFormat,
                        hasTransparency: pixelFormatHasTransparency(pixelFormat)
                    )
                )
                continue
            }

            if let audioCodec = firstMatch(in: line, pattern: "Audio:\\s*([^,\\s\\(]+)") {
                streams.append(
                    MediaStream(
                        kind: .audio,
                        codecName: audioCodec.lowercased(),
                        codecLongName: nil,
                        profile: nil,
                        width: nil,
                        height: nil,
                        bitrate: nil,
                        codecTagString: nil,
                        sampleRate: parseSampleRate(from: line),
                        channels: parseChannels(from: line),
                        bitDepth: nil,
                        pixelFormat: nil,
                        hasTransparency: nil
                    )
                )
            }
        }

        if streams.isEmpty {
            if let videoCodec = firstMatch(in: infoText, pattern: "Video:\\s*([^,\\s\\(]+)") {
                let resolution = parseResolution(from: infoText)
                let pixelFormat = parsePixelFormat(from: infoText)
                streams.append(
                    MediaStream(
                        kind: .video,
                        codecName: videoCodec.lowercased(),
                        codecLongName: nil,
                        profile: nil,
                        width: resolution?.0,
                        height: resolution?.1,
                        bitrate: nil,
                        codecTagString: nil,
                        sampleRate: nil,
                        channels: nil,
                        bitDepth: parseBitDepth(from: infoText, pixelFormat: pixelFormat),
                        pixelFormat: pixelFormat,
                        hasTransparency: pixelFormatHasTransparency(pixelFormat)
                    )
                )
            }

            if let audioCodec = firstMatch(in: infoText, pattern: "Audio:\\s*([^,\\s\\(]+)") {
                streams.append(
                    MediaStream(
                        kind: .audio,
                        codecName: audioCodec.lowercased(),
                        codecLongName: nil,
                        profile: nil,
                        width: nil,
                        height: nil,
                        bitrate: nil,
                        codecTagString: nil,
                        sampleRate: parseSampleRate(from: infoText),
                        channels: parseChannels(from: infoText),
                        bitDepth: nil,
                        pixelFormat: nil,
                        hasTransparency: nil
                    )
                )
            }
        }

        guard streams.contains(where: { $0.kind == .video || $0.kind == .audio }) else {
            log("FFmpeg fallback could not parse audio/video streams")
            return nil
        }

        let duration = parseDurationSeconds(from: infoText) ?? 0
        let bitrate = parseBitrate(from: infoText)
        let formatName = parseFormatName(from: infoText) ?? originalURL.pathExtension.lowercased()

        let mediaInfo = MediaInfo(
            fileName: originalURL.lastPathComponent,
            fileExtension: originalURL.pathExtension.lowercased(),
            formatName: formatName,
            duration: duration,
            bitrate: bitrate,
            streams: streams
        )

        return ProbeAnalysisResult(mediaInfo: mediaInfo, jsonOutput: fallbackJSONOutput(from: mediaInfo))
    }

    private func fallbackJSONOutput(from info: MediaInfo) -> String? {
        let payload = FallbackProbePayload(
            format: FallbackProbeFormat(
                filename: info.fileName,
                formatName: info.formatName,
                duration: info.duration > 0 ? String(format: "%.3f", info.duration) : nil,
                bitRate: info.bitrate.map(String.init)
            ),
            streams: info.streams.map {
                FallbackProbeStream(
                    codecType: $0.kind.rawValue,
                    codecName: $0.codecName,
                    codecLongName: $0.codecLongName,
                    profile: $0.profile,
                    width: $0.width,
                    height: $0.height,
                    bitRate: $0.bitrate.map(String.init),
                    codecTagString: $0.codecTagString,
                    sampleRate: $0.sampleRate.map(String.init),
                    channels: $0.channels,
                    bitDepth: $0.bitDepth,
                    pixelFormat: $0.pixelFormat
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(payload) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private func parseDurationSeconds(from text: String) -> TimeInterval? {
        guard let durationText = firstMatch(in: text, pattern: "Duration:\\s*([0-9]{2}:[0-9]{2}:[0-9]{2}(?:\\.[0-9]+|,[0-9]+)?)") else {
            return nil
        }

        let normalized = durationText.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else {
            return nil
        }

        return (hours * 3600) + (minutes * 60) + seconds
    }

    private func parseBitrate(from text: String) -> Int? {
        guard let kbpsText = firstMatch(in: text, pattern: "bitrate:\\s*([0-9]+)\\s*(?:kb/s|kbits/s)"),
              let kbps = Int(kbpsText) else {
            return nil
        }

        return kbps * 1_000
    }

    private func parseResolution(from text: String) -> (Int, Int)? {
        guard let widthText = firstMatch(in: text, pattern: "([0-9]{2,5})x([0-9]{2,5})", captureGroup: 1),
              let heightText = firstMatch(in: text, pattern: "([0-9]{2,5})x([0-9]{2,5})", captureGroup: 2),
              let width = Int(widthText),
              let height = Int(heightText) else {
            return nil
        }

        return (width, height)
    }

    private func parseFormatName(from text: String) -> String? {
        guard let format = firstMatch(in: text, pattern: "Input\\s*#0,\\s*([^,\\n]+(?:,[^,\\n]+)*),\\s*from") else {
            return nil
        }

        return format.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseSampleRate(from text: String) -> Int? {
        guard let sampleRateText = firstMatch(in: text, pattern: "([0-9]{4,6})\\s*Hz"),
              let sampleRate = Int(sampleRateText),
              sampleRate > 0
        else {
            return nil
        }

        return sampleRate
    }

    private func parseChannels(from text: String) -> Int? {
        if let channelsText = firstMatch(in: text, pattern: "([0-9]+)\\s*channels?"), let channels = Int(channelsText), channels > 0 {
            return channels
        }

        let lowercased = text.lowercased()
        if lowercased.contains("mono") {
            return 1
        }

        if lowercased.contains("stereo") {
            return 2
        }

        if lowercased.contains("5.1") {
            return 6
        }

        if lowercased.contains("7.1") {
            return 8
        }

        return nil
    }

    private func parsePixelFormat(from text: String) -> String? {
        guard let pixelFormat = firstMatch(in: text, pattern: "Video:\\s*[^,]+,\\s*([^,\\s]+)") else {
            return nil
        }

        return pixelFormat.lowercased()
    }

    private func parseBitDepth(from text: String, pixelFormat: String?) -> Int? {
        if let rawBitDepth = firstMatch(in: text, pattern: "([0-9]{1,2})-bit"), let bitDepth = Int(rawBitDepth), bitDepth > 0 {
            return bitDepth
        }

        if let pixelFormat,
           let bitDepthText = firstMatch(in: pixelFormat, pattern: "p([0-9]{2})"),
           let bitDepth = Int(bitDepthText),
           bitDepth > 0 {
            return bitDepth
        }

        return nil
    }

    private func pixelFormatHasTransparency(_ pixelFormat: String?) -> Bool? {
        guard let pixelFormat else { return nil }

        let value = pixelFormat.lowercased()
        let alphaIndicators = ["rgba", "bgra", "argb", "abgr", "yuva", "gbrap", "ya", "pal8", "ayuv"]

        if alphaIndicators.contains(where: { value.contains($0) }) {
            return true
        }

        return false
    }

    private func firstMatch(in text: String, pattern: String, captureGroup: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > captureGroup,
              let valueRange = Range(match.range(at: captureGroup), in: text) else {
            return nil
        }

        return String(text[valueRange])
    }

    private func failureReason(from error: Error) -> String {
        if let probeError = error as? FFprobeServiceError {
            switch probeError {
            case .invalidOutput:
                return "FFprobe output was empty or did not include valid JSON payload."
            case let .failed(message):
                return message
            }
        }

        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return "Unknown FFprobe failure"
        }

        if message.localizedCaseInsensitiveContains("already specified") {
            return "Embedded FFprobe state conflict: previous input argument persisted into this run."
        }

        if message.localizedCaseInsensitiveContains("permission denied") {
            return "Permission denied while reading temporary media copy."
        }

        if message.localizedCaseInsensitiveContains("no such file") {
            return "Temporary media file was missing when FFprobe started."
        }

        return message
    }
}

private struct FallbackProbePayload: Encodable {
    let format: FallbackProbeFormat
    let streams: [FallbackProbeStream]
}

private struct FallbackProbeFormat: Encodable {
    let filename: String
    let formatName: String
    let duration: String?
    let bitRate: String?

    enum CodingKeys: String, CodingKey {
        case filename
        case formatName = "format_name"
        case duration
        case bitRate = "bit_rate"
    }
}

private struct FallbackProbeStream: Encodable {
    let codecType: String
    let codecName: String?
    let codecLongName: String?
    let profile: String?
    let width: Int?
    let height: Int?
    let bitRate: String?
    let codecTagString: String?
    let sampleRate: String?
    let channels: Int?
    let bitDepth: Int?
    let pixelFormat: String?

    enum CodingKeys: String, CodingKey {
        case codecType = "codec_type"
        case codecName = "codec_name"
        case codecLongName = "codec_long_name"
        case profile
        case width
        case height
        case bitRate = "bit_rate"
        case codecTagString = "codec_tag_string"
        case sampleRate = "sample_rate"
        case channels
        case bitDepth = "bits_per_raw_sample"
        case pixelFormat = "pix_fmt"
    }
}
