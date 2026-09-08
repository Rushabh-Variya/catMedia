import Foundation

enum MediaExtractOption: String, CaseIterable, Identifiable {
    case video

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video:
            return "Video"
        }
    }

    var subtitle: String {
        switch self {
        case .video:
            return "Extract video-only MP4 with stream copy and metadata/chapter mapping."
        }
    }

    var outputExtension: String {
        switch self {
        case .video:
            return "mp4"
        }
    }
}
