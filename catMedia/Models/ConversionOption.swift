import Foundation

enum ConversionCategory: String {
    case audio = "Audio"
    case video = "Video"
    case extraction = "Extraction"
}

enum ConversionOption: String, CaseIterable, Identifiable {
    case convertToMP4

    var id: String { rawValue }

    var title: String {
        switch self {
        case .convertToMP4:
            "Smart Lossless MP4"
        }
    }

    var category: ConversionCategory {
        switch self {
        case .convertToMP4:
            .video
        }
    }

    var subtitle: String {
        switch self {
        case .convertToMP4:
            "Auto-detect codec/profile and remux to MP4 without re-encoding."
        }   
    }

    var outputExtension: String {
        switch self {
        case .convertToMP4:
            "mp4"
        }
    }

    static func availableOptions(for mediaInfo: MediaInfo) -> [ConversionOption] {
        guard mediaInfo.hasVideo, isSupportedForSmartLosslessMP4(mediaInfo) else {
            return []
        }

        return [.convertToMP4]
    }

    private static func isSupportedForSmartLosslessMP4(_ mediaInfo: MediaInfo) -> Bool {
        guard let videoStream = mediaInfo.videoStream else { return false }

        let codec = (videoStream.codecName ?? "").lowercased()
        let profile = (videoStream.profile ?? "").lowercased()
        let codecTag = (videoStream.codecTagString ?? "").lowercased()

        if ["h264", "avc", "hevc", "h265", "av1"].contains(codec) {
            return true
        }

        let hasDolbyVisionSignal = profile.contains("dolby vision") || codecTag.contains("dvhe") || codecTag.contains("dvh1")

        return hasDolbyVisionSignal
    }
}
