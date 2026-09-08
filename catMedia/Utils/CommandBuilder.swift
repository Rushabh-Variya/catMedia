import Foundation

enum CommandBuilder {
    static func probeArguments(for inputURL: URL) -> [String] {
        [
            "ffprobe",
            "-v", "error",
            "-print_format", "json",
            "-find_stream_info",
            "-analyzeduration", "100M",
            "-probesize", "100M",
            "-show_format",
            "-show_streams",
            inputURL.path
        ]
    }

    static func conversionArguments(
        inputURL: URL,
        outputURL: URL,
        option: ConversionOption,
        mediaInfo: MediaInfo
    ) -> [String] {
        switch option {
        case .convertToMP4:
            return smartLosslessMP4Arguments(inputURL: inputURL, outputURL: outputURL, mediaInfo: mediaInfo)
        }
    }

    static func displayString(for arguments: [String]) -> String {
        arguments
            .map { argument in
                if argument.contains(" ") {
                    "\"\(argument.replacingOccurrences(of: "\"", with: "\\\""))\""
                } else {
                    argument
                }
            }
            .joined(separator: " ")
    }

    static func mediaExtractArguments(
        inputURL: URL,
        outputURL: URL,
        option: MediaExtractOption,
        mediaInfo: MediaInfo
    ) -> [String] {
        switch option {
        case .video:
            return extractVideoContainerArguments(inputURL: inputURL, outputURL: outputURL, mediaInfo: mediaInfo)
        }
    }

    private static func smartLosslessMP4Arguments(inputURL: URL, outputURL: URL, mediaInfo: MediaInfo) -> [String] {
        var components = [
            "ffmpeg", "-y", "-i", inputURL.path,
            "-map", "0:v:0",
            "-map", "0:a?",
            "-map_chapters", "0",
            "-map_metadata", "0",
            "-c:v", "copy",
            "-c:a", "copy",
            "-sn",
            "-movflags", "+faststart"
        ]

        if let videoStream = mediaInfo.videoStream {
            let profile = (videoStream.profile ?? "").lowercased()
            let codecTag = (videoStream.codecTagString ?? "").lowercased()
            let isDolbyVision = profile.contains("dolby vision") || codecTag.contains("dvhe") || codecTag.contains("dvh1")
            let isProfile5 = profile.contains("profile 5") || profile.contains("dvhe.05")
            let isProfile8 = profile.contains("profile 8") || profile.contains("8.1") || profile.contains("8.4")

            if isDolbyVision && isProfile5 {
                components.append(contentsOf: ["-tag:v", "dvh1"])
            } else if isDolbyVision && isProfile8 {
                components.append(contentsOf: ["-tag:v", "hvc1"])
            }
        }

        components.append(outputURL.path)
        return components
    }

    private static func extractVideoContainerArguments(inputURL: URL, outputURL: URL, mediaInfo: MediaInfo) -> [String] {
        var components = [
            "ffmpeg", "-y", "-i", inputURL.path,
            "-map", "0:v:0",
            "-map_chapters", "0",
            "-map_metadata", "0",
            "-c:v", "copy",
            "-an",
            "-dn",
            "-sn",
            "-movflags", "+faststart"
        ]

        if let videoStream = mediaInfo.videoStream {
            let profile = (videoStream.profile ?? "").lowercased()
            let codecTag = (videoStream.codecTagString ?? "").lowercased()
            let isDolbyVision = profile.contains("dolby vision") || codecTag.contains("dvhe") || codecTag.contains("dvh1")
            let isProfile5 = profile.contains("profile 5") || profile.contains("dvhe.05")
            let isProfile8 = profile.contains("profile 8") || profile.contains("8.1") || profile.contains("8.4")

            if isDolbyVision && isProfile5 {
                components.append(contentsOf: ["-tag:v", "dvh1"])
            } else if isDolbyVision && isProfile8 {
                components.append(contentsOf: ["-tag:v", "hvc1"])
            }
        }

        components.append(outputURL.path)
        return components
    }

}
