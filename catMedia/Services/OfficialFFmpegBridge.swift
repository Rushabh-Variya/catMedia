import Darwin
import Foundation

enum OfficialFFmpegBridge {
    nonisolated static let bridgeNotLinkedExitCode = -127

    nonisolated static func runFFmpeg(arguments: [String]) -> Int {
        run(arguments: arguments, executor: catmedia_ffmpeg_execute)
    }

    nonisolated static func runFFprobe(arguments: [String]) -> Int {
        run(arguments: arguments, executor: catmedia_ffprobe_execute)
    }

    nonisolated static func backendDescription() -> String {
        guard let backend = catmedia_ffmpeg_bridge_backend() else {
            return "unknown"
        }

        return String(cString: backend)
    }

    nonisolated private static func run(
        arguments: [String],
        executor: (Int32, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32
    ) -> Int {
        guard !arguments.isEmpty else {
            return bridgeNotLinkedExitCode
        }

        let mutableArguments = arguments.map { strdup($0) }
        defer {
            mutableArguments.forEach { pointer in
                if let pointer {
                    free(pointer)
                }
            }
        }

        var argv = mutableArguments + [nil]
        let exitCode = argv.withUnsafeMutableBufferPointer { buffer in
            executor(Int32(arguments.count), buffer.baseAddress)
        }

        return Int(exitCode)
    }
}
