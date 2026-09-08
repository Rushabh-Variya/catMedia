import Foundation

struct ConversionResult {
    let outputURL: URL
    let commandDescription: String
}

enum FFmpegServiceError: LocalizedError {
    case failed(message: String)

    var errorDescription: String? {
        switch self {
        case let .failed(message):
            message
        }
    }
}

final class FFmpegService {
    private let runner = FFmpegCommandRunner.shared

    func executeConversion(
        arguments: [String],
        estimatedDuration: TimeInterval,
        outputURL: URL,
        onProgress: @escaping @Sendable (Double) -> Void,
        onLog: (@Sendable (String) -> Void)? = nil
    ) async throws -> ConversionResult {
        let display = CommandBuilder.displayString(for: arguments)
        _ = estimatedDuration
        #if DEBUG
        print("[catMedia][FFmpegService] START: \(display)")
        #endif

        do {
            onProgress(0.05)
            _ = try await runner.runFFmpegWithoutProgress(arguments: arguments, onLog: onLog)
            onProgress(1)

            #if DEBUG
            print("[catMedia][FFmpegService] SUCCESS: \(outputURL.lastPathComponent)")
            #endif

            return ConversionResult(outputURL: outputURL, commandDescription: display)
        } catch {
            #if DEBUG
            print("[catMedia][FFmpegService] ERROR: \(error.localizedDescription)")
            #endif
            throw FFmpegServiceError.failed(message: error.localizedDescription)
        }
    }
}
