import Foundation

struct MediaInfo: Equatable {
    let fileName: String
    let fileExtension: String
    let formatName: String
    let duration: TimeInterval
    let bitrate: Int?
    let streams: [MediaStream]

    var videoStream: MediaStream? {
        streams.first(where: { $0.kind == .video })
    }

    var audioStream: MediaStream? {
        streams.first(where: { $0.kind == .audio })
    }

    var hasVideo: Bool {
        videoStream != nil
    }

    var hasAudio: Bool {
        audioStream != nil
    }

    var resolutionText: String {
        guard let videoStream, let width = videoStream.width, let height = videoStream.height else {
            return "N/A"
        }

        return "\(width)x\(height)"
    }

    var videoCodecText: String {
        videoStream?.codecName?.uppercased() ?? "N/A"
    }

    var audioCodecText: String {
        audioStream?.codecName?.uppercased() ?? "N/A"
    }

    var samplingRateText: String {
        guard let sampleRate = audioStream?.sampleRate, sampleRate > 0 else { return "N/A" }
        return "\(sampleRate) Hz"
    }

    var channelsText: String {
        guard let channels = audioStream?.channels, channels > 0 else { return "N/A" }
        return "\(channels)"
    }

    var bitDepthText: String {
        guard let bitDepth = videoStream?.bitDepth, bitDepth > 0 else { return "N/A" }
        return "\(bitDepth)-bit"
    }

    var transparencyText: String {
        guard let hasTransparency = videoStream?.hasTransparency else { return "N/A" }
        return hasTransparency ? "Yes" : "No"
    }

    var durationText: String {
        guard duration > 0 else { return "N/A" }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: duration) ?? "N/A"
    }

    var bitrateText: String {
        guard let bitrate, bitrate > 0 else { return "N/A" }
        let kbps = Int((Double(bitrate) / 1_000).rounded())
        return "\(kbps) kb/s"
    }

    static func fromProbeJSON(fileURL: URL, json: Data) throws -> MediaInfo {
        let payload = try JSONDecoder().decode(ProbePayload.self, from: json)
        let streams = payload.streams.map { stream in
            let bitDepthFromRaw = Int(stream.bitsPerRawSample ?? "")
            let bitDepthFromSample = stream.bitsPerSample
            let bitDepth = (bitDepthFromRaw ?? 0) > 0 ? bitDepthFromRaw : bitDepthFromSample
            let sampleRate = Int(stream.sampleRate ?? "")
            let hasTransparency = pixelFormatHasTransparency(stream.pixFmt)

            return MediaStream(
                kind: MediaStream.Kind(rawValue: stream.codecType) ?? .other,
                codecName: stream.codecName,
                codecLongName: stream.codecLongName,
                profile: stream.profile,
                width: stream.width,
                height: stream.height,
                bitrate: Int(stream.bitRate ?? ""),
                codecTagString: stream.codecTagString,
                sampleRate: sampleRate,
                channels: stream.channels,
                bitDepth: bitDepth,
                pixelFormat: stream.pixFmt,
                hasTransparency: hasTransparency
            )
        }

        return MediaInfo(
            fileName: fileURL.lastPathComponent,
            fileExtension: fileURL.pathExtension.lowercased(),
            formatName: payload.format.formatName ?? fileURL.pathExtension.lowercased(),
            duration: TimeInterval(payload.format.duration ?? "") ?? 0,
            bitrate: Int(payload.format.bitRate ?? ""),
            streams: streams
        )
    }

    private static func pixelFormatHasTransparency(_ pixelFormat: String?) -> Bool? {
        guard let pixelFormat else { return nil }
        let value = pixelFormat.lowercased()

        let alphaIndicators = ["rgba", "bgra", "argb", "abgr", "yuva", "gbrap", "ya", "pal8", "ayuv", "vaapi"]
        if alphaIndicators.contains(where: { value.contains($0) }) {
            return true
        }

        return false
    }
}

struct MediaStream: Equatable, Hashable {
    enum Kind: String {
        case audio
        case video
        case subtitle
        case other
    }

    let kind: Kind
    let codecName: String?
    let codecLongName: String?
    let profile: String?
    let width: Int?
    let height: Int?
    let bitrate: Int?
    let codecTagString: String?
    let sampleRate: Int?
    let channels: Int?
    let bitDepth: Int?
    let pixelFormat: String?
    let hasTransparency: Bool?
}

private struct ProbePayload: Decodable {
    let streams: [ProbeStream]
    let format: ProbeFormat
}

private struct ProbeStream: Decodable {
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
    let bitsPerRawSample: String?
    let bitsPerSample: Int?
    let pixFmt: String?

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
        case bitsPerRawSample = "bits_per_raw_sample"
        case bitsPerSample = "bits_per_sample"
        case pixFmt = "pix_fmt"
    }
}

private struct ProbeFormat: Decodable {
    let formatName: String?
    let duration: String?
    let bitRate: String?

    enum CodingKeys: String, CodingKey {
        case formatName = "format_name"
        case duration
        case bitRate = "bit_rate"
    }
}
