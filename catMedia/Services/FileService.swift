import Foundation

enum FileServiceError: LocalizedError {
    case unsupportedType
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedType:
            "The selected file could not be processed as media."
        case .copyFailed:
            "The selected file could not be copied into the app sandbox."
        }
    }
}

struct OutputSaveResult {
    let url: URL
    let savedInPreferredDirectory: Bool
    let storageDirectoryURL: URL
    let isTemporaryStorage: Bool
}

struct CacheCleanupReport {
    let removedFileCount: Int
    let freedBytes: Int64

    var summaryText: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        let sizeText = formatter.string(fromByteCount: freedBytes)
        return "Removed \(removedFileCount) files (\(sizeText))."
    }
}

struct CacheInspectionReport {
    let directories: [URL]
    let fileCount: Int
    let totalBytes: Int64

    var sizeText: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalBytes)
    }
}

struct FileService: Sendable {
    private let supportedExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "avi", "webm", "flv", "wmv", "mpg", "mpeg", "ts", "m2ts", "mts", "3gp", "3g2", "ogv", "vob", "asf", "f4v", "mxf"
    ]

    nonisolated func importFile(from externalURL: URL) throws -> URL {
        _ = try createCatMediaFolder()

        let didAccess = externalURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                externalURL.stopAccessingSecurityScopedResource()
            }
        }

        let sourceURL: URL
        let values = try externalURL.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true {
            guard let firstMediaFile = firstSupportedMediaFile(in: externalURL) else {
                throw FileServiceError.unsupportedType
            }
            sourceURL = firstMediaFile
        } else {
            sourceURL = externalURL
        }

        let fileExtension = sourceURL.pathExtension.lowercased()
        guard supportedExtensions.contains(fileExtension) else {
            throw FileServiceError.unsupportedType
        }
        let normalizedExtension = fileExtension.isEmpty ? "bin" : fileExtension

        let fileManager = FileManager.default
        let sandboxDirectory = try importedFilesDirectory()
        let destinationURL = uniqueURL(
            in: sandboxDirectory,
            preferredName: sourceURL.deletingPathExtension().lastPathComponent,
            extension: normalizedExtension
        )

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw FileServiceError.copyFailed
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            throw FileServiceError.copyFailed
        }
    }

    nonisolated func resolveInputSourceURL(from externalURL: URL) throws -> URL {
        let didAccess = externalURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                externalURL.stopAccessingSecurityScopedResource()
            }
        }

        let sourceURL: URL
        let values = try externalURL.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true {
            guard let firstMediaFile = firstSupportedMediaFile(in: externalURL) else {
                throw FileServiceError.unsupportedType
            }
            sourceURL = firstMediaFile
        } else {
            sourceURL = externalURL
        }

        return sourceURL
    }

    func preferredOutputDirectory(for externalURL: URL) -> URL? {
        let values = try? externalURL.resourceValues(forKeys: [.isDirectoryKey])
        if values?.isDirectory == true {
            return externalURL
        }

        return externalURL.deletingLastPathComponent()
    }

    nonisolated func importMediaData(_ data: Data, suggestedFileExtension: String) throws -> URL {
        _ = try createCatMediaFolder()

        let normalizedExtension = suggestedFileExtension.lowercased().isEmpty
            ? "bin"
            : suggestedFileExtension.lowercased()
        guard supportedExtensions.contains(normalizedExtension) else {
            throw FileServiceError.unsupportedType
        }
        guard !data.isEmpty else {
            throw FileServiceError.unsupportedType
        }

        let sandboxDirectory = try importedFilesDirectory()
        let destinationURL = uniqueURL(
            in: sandboxDirectory,
            preferredName: "photo-media",
            extension: normalizedExtension
        )

        do {
            try data.write(to: destinationURL, options: .atomic)
            return destinationURL
        } catch {
            throw FileServiceError.copyFailed
        }
    }

    func makeOutputURL(for inputURL: URL, option: ConversionOption) throws -> URL {
        try makeOutputURL(
            for: inputURL,
            preferredExtension: option.outputExtension,
            outputDirectoryName: "Converted"
        )
    }

    func makeDirectOutputURL(
        for inputURL: URL,
        preferredExtension: String,
        preferredDirectoryURL: URL?,
        fallbackOutputDirectoryName: String
    ) throws -> OutputSaveResult {
        _ = preferredDirectoryURL

        let appDirectory = try createCatMediaFolder()
        let taskDirectory = appDirectory.appendingPathComponent(fallbackOutputDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: taskDirectory, withIntermediateDirectories: true)
        let fallback = try makeOutputURL(in: taskDirectory, inputURL: inputURL, preferredExtension: preferredExtension)
        return OutputSaveResult(
            url: fallback,
            savedInPreferredDirectory: false,
            storageDirectoryURL: taskDirectory,
            isTemporaryStorage: false
        )
    }

    func copyOutputToPreferredDirectoryIfPossible(
        generatedOutputURL: URL,
        originalInputURL: URL,
        preferredExtension: String,
        preferredDirectoryURL: URL?
    ) -> OutputSaveResult {
        guard let preferredDirectoryURL else {
            return OutputSaveResult(
                url: generatedOutputURL,
                savedInPreferredDirectory: false,
                storageDirectoryURL: generatedOutputURL.deletingLastPathComponent(),
                isTemporaryStorage: isTemporaryURL(generatedOutputURL)
            )
        }

        let didAccess = preferredDirectoryURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                preferredDirectoryURL.stopAccessingSecurityScopedResource()
            }
        }

        guard didAccess else {
            return OutputSaveResult(
                url: generatedOutputURL,
                savedInPreferredDirectory: false,
                storageDirectoryURL: generatedOutputURL.deletingLastPathComponent(),
                isTemporaryStorage: isTemporaryURL(generatedOutputURL)
            )
        }

        let destinationURL = uniqueURL(
            in: preferredDirectoryURL,
            preferredName: originalInputURL.deletingPathExtension().lastPathComponent,
            extension: preferredExtension
        )

        do {
            try FileManager.default.copyItem(at: generatedOutputURL, to: destinationURL)
            try? FileManager.default.removeItem(at: generatedOutputURL)
            return OutputSaveResult(
                url: destinationURL,
                savedInPreferredDirectory: true,
                storageDirectoryURL: preferredDirectoryURL,
                isTemporaryStorage: false
            )
        } catch {
            return OutputSaveResult(
                url: generatedOutputURL,
                savedInPreferredDirectory: false,
                storageDirectoryURL: generatedOutputURL.deletingLastPathComponent(),
                isTemporaryStorage: isTemporaryURL(generatedOutputURL)
            )
        }
    }

    func ensureAppOutputDirectoryExists() throws -> URL {
        try createCatMediaFolder()
    }

    nonisolated func createCatMediaFolder() throws -> URL {
        // The app's Documents directory is already exposed as "On My iPhone/catMedia".
        // Writing directly here avoids nested "catMedia/catMedia" paths.
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs
    }

    nonisolated func saveFile(tempOutput: URL) throws -> URL {
        let folder = try createCatMediaFolder()

        // If FFmpeg already wrote directly into the app folder, keep it in place.
        if tempOutput.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL {
            return tempOutput
        }

        let sourceName = tempOutput.deletingPathExtension().lastPathComponent
        let sourceExtension = tempOutput.pathExtension
        let destination = uniqueURL(in: folder, preferredName: sourceName, extension: sourceExtension)

        try FileManager.default.copyItem(at: tempOutput, to: destination)
        return destination
    }

    func makeOutputURL(for inputURL: URL, preferredExtension: String, outputDirectoryName: String) throws -> URL {
        _ = outputDirectoryName
        let outputDirectory = try createCatMediaFolder()

        return uniqueURL(
            in: outputDirectory,
            preferredName: inputURL.deletingPathExtension().lastPathComponent,
            extension: preferredExtension
        )
    }

    func removeTemporaryOutputIfExists(at url: URL) throws -> Bool {
        let fileManager = FileManager.default
        let temporaryRootPath = fileManager.temporaryDirectory.standardizedFileURL.path + "/"
        let standardizedURL = url.standardizedFileURL

        guard standardizedURL.path.hasPrefix(temporaryRootPath) else {
            return false
        }

        guard fileManager.fileExists(atPath: standardizedURL.path) else {
            return false
        }

        try fileManager.removeItem(at: standardizedURL)
        return true
    }

    private func isTemporaryURL(_ url: URL) -> Bool {
        let temporaryRoot = FileManager.default.temporaryDirectory.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.hasPrefix(temporaryRoot)
    }

    private func makeOutputURL(in directory: URL, inputURL: URL, preferredExtension: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return uniqueURL(
            in: directory,
            preferredName: inputURL.deletingPathExtension().lastPathComponent,
            extension: preferredExtension
        )
    }

    func clearAppGeneratedFiles() throws -> CacheCleanupReport {
        let fileManager = FileManager.default

        var totalRemovedCount = 0
        var totalFreedBytes: Int64 = 0

        let directories = appTemporaryDirectories(fileManager: fileManager)

        for directory in directories where fileManager.fileExists(atPath: directory.path) {
            let result = try removeContents(of: directory, using: fileManager)
            totalRemovedCount += result.removedCount
            totalFreedBytes += result.freedBytes
        }

        return CacheCleanupReport(removedFileCount: totalRemovedCount, freedBytes: totalFreedBytes)
    }

    func inspectAppGeneratedFiles() throws -> CacheInspectionReport {
        let fileManager = FileManager.default
        let directories = appTemporaryDirectories(fileManager: fileManager)

        var totalCount = 0
        var totalBytes: Int64 = 0

        for directory in directories where fileManager.fileExists(atPath: directory.path) {
            let usage = try directoryUsage(of: directory, using: fileManager)
            totalCount += usage.fileCount
            totalBytes += usage.totalBytes
        }

        return CacheInspectionReport(
            directories: directories,
            fileCount: totalCount,
            totalBytes: totalBytes
        )
    }

    private nonisolated func importedFilesDirectory() throws -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedMedia", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func importedFilesDirectoryIfExists() -> URL? {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedMedia", isDirectory: true)
        return FileManager.default.fileExists(atPath: directory.path) ? directory : nil
    }

    private func appTemporaryDirectories(fileManager: FileManager) -> [URL] {
        [
            fileManager.temporaryDirectory.appendingPathComponent("Converted", isDirectory: true),
            fileManager.temporaryDirectory.appendingPathComponent("Extracted", isDirectory: true),
            fileManager.temporaryDirectory.appendingPathComponent("ProbeCache", isDirectory: true)
        ]
    }

    private func directoryUsage(of directory: URL, using fileManager: FileManager) throws -> (fileCount: Int, totalBytes: Int64) {
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        )

        var fileCount = 0
        var totalBytes: Int64 = 0

        for url in urls {
            if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]),
               values.isRegularFile == true {
                fileCount += 1
                if let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize {
                    totalBytes += Int64(size)
                }
            }
        }

        return (fileCount, totalBytes)
    }

    private func removeContents(of directory: URL, using fileManager: FileManager) throws -> (removedCount: Int, freedBytes: Int64) {
        let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey], options: [.skipsHiddenFiles])

        var removedCount = 0
        var freedBytes: Int64 = 0

        for url in urls {
            if let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]),
               let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize {
                freedBytes += Int64(size)
            }

            try fileManager.removeItem(at: url)
            removedCount += 1
        }

        return (removedCount, freedBytes)
    }

    private nonisolated func uniqueURL(in directory: URL, preferredName: String, extension fileExtension: String) -> URL {
        let fileManager = FileManager.default
        let ext = fileExtension.isEmpty ? "" : ".\(fileExtension)"

        let candidate = directory.appendingPathComponent(preferredName + ext)
        guard fileManager.fileExists(atPath: candidate.path) else {
            return candidate
        }

        var counter = 1
        while true {
            let next = directory.appendingPathComponent("\(preferredName)+\(counter)\(ext)")
            if !fileManager.fileExists(atPath: next.path) {
                return next
            }
            counter += 1
        }
    }

    private nonisolated func firstSupportedMediaFile(in folderURL: URL) -> URL? {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let regularFiles = entries.filter { candidate in
            (try? candidate.resourceValues(forKeys: Set(keys)).isRegularFile) == true
        }

        for candidate in regularFiles {
            let ext = candidate.pathExtension.lowercased()
            if supportedExtensions.contains(ext) {
                return candidate
            }
        }

        return nil
    }
}
