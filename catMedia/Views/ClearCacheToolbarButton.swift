import SwiftUI

struct ClearCacheToolbarButton: View {
    @State private var isConfirmationPresented = false
    @State private var resultMessage: String?
    @State private var isResultAlertPresented = false
    @State private var confirmationMessage = ""

    private let fileService = FileService()

    var body: some View {
        Button {
            prepareConfirmationMessage()
            isConfirmationPresented = true
        } label: {
            Image(systemName: "trash")
        }
        .accessibilityLabel("Clear Cache")
        .confirmationDialog("Clear Cache?", isPresented: $isConfirmationPresented, titleVisibility: .visible) {
            Button("Clear Cache", role: .destructive) {
                clearCache()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
        .alert("Cache Cleanup", isPresented: $isResultAlertPresented) {
            Button("OK", role: .cancel) {
                resultMessage = nil
            }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private func clearCache() {
        do {
            let report = try fileService.clearAppGeneratedFiles()
            resultMessage = report.removedFileCount == 0
                ? "Nothing to clear."
                : report.summaryText
        } catch {
            resultMessage = "Failed to clear cache: \(error.localizedDescription)"
        }

        isResultAlertPresented = true
    }

    private func prepareConfirmationMessage() {
        do {
            let inspection = try fileService.inspectAppGeneratedFiles()
            confirmationMessage = "Only temporary folders are targeted.\n\nFiles: \(inspection.fileCount)\nSize: \(inspection.sizeText)\n\nTargets: tmp/Converted, tmp/Extracted, tmp/ProbeCache"
        } catch {
            confirmationMessage = "Only temporary folder files are targeted."
        }
    }
}
