import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct MediaInfoView: View {
    @StateObject private var viewModel = MediaInfoViewModel()
    @State private var isImporterPresented = false
    @State private var didCopyJSON = false
    @State private var selectedOutputFormat: MetadataOutputFormat = .json

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    Divider().overlay(.primary.opacity(0.10))
                    importer
                    if showMetadata {
                        Divider().overlay(.primary.opacity(0.10))
                        metadata
                    }
                    if showOutput {
                        Divider().overlay(.primary.opacity(0.10))
                        output
                    }
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
                .animation(UIAnimation.easeOut, value: showMetadata)
                .animation(UIAnimation.easeOut, value: showOutput)
            }
            .background(Color.black)
            .navigationTitle("Media Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ClearCacheToolbarButton()
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case let .success(urls):
                    guard let url = urls.first else { return }
                    Task { await viewModel.importAndAnalyze(url: url) }
                case let .failure(error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
            .alert("Video files only", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "Select a supported video file.")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Inspect media")
                .font(.system(.largeTitle, design: .default).weight(.bold))
                .foregroundStyle(.white)
        }
    }

    private var importer: some View {
        Button {
            presentImporter()
        } label: {
            VStack(spacing: 14) {
                Image(systemName: "info.circle").font(.system(size: 30, weight: .semibold)).frame(width: 64, height: 64).background(.white.opacity(0.08), in: Circle())
                Text(viewModel.importedFileURL?.lastPathComponent ?? "Choose media file").font(.headline).foregroundStyle(.white)
                Text(viewModel.statusMessage.isEmpty ? "Tap to inspect file" : viewModel.statusMessage).font(.footnote).foregroundStyle(.white.opacity(0.60))
            }.frame(maxWidth: .infinity).frame(minHeight: 210).padding(24).background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 24, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.pressableCard)
        .disabled(viewModel.isAnalyzing)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Metadata").font(.headline.weight(.semibold)).foregroundStyle(.white)
            if let info = viewModel.mediaInfo {
                metadataSection("File") {
                    flatRow("Name", info.fileName)
                    flatRow("Extension", info.fileExtension.uppercased())
                    flatRow("Format", info.formatName.uppercased())
                    flatRow("Duration", info.durationText)
                    flatRow("Bitrate", info.bitrateText)
                }

                if let video = info.videoStream {
                    metadataSection("Video") {
                        flatRow("Codec", info.videoCodecText)
                        flatRow("Profile", video.profile ?? "N/A")
                        flatRow("Resolution", info.resolutionText)
                        flatRow("Pixel format", video.pixelFormat?.uppercased() ?? "N/A")
                        flatRow("Bit depth", info.bitDepthText)
                        flatRow("Bitrate", streamBitrateText(video))
                        flatRow("Transparency", info.transparencyText)
                    }
                }

                if let audio = info.audioStream {
                    metadataSection("Audio") {
                        flatRow("Codec", info.audioCodecText)
                        flatRow("Profile", audio.profile ?? "N/A")
                        flatRow("Sample rate", info.samplingRateText)
                        flatRow("Channels", info.channelsText)
                        flatRow("Bitrate", streamBitrateText(audio))
                    }
                }
            } else {
                Text("No metadata yet.").foregroundStyle(.white.opacity(0.60))
            }
        }
    }

    @ViewBuilder
    private func metadataSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .padding(.bottom, 4)

            content()
        }
        .padding(.top, 4)
    }

    private var output: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Output")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Picker("Format", selection: $selectedOutputFormat) {
                    ForEach(MetadataOutputFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.menu)

                if let text = renderedOutputText {
                    Button {
                        UIPasteboard.general.string = text
                        didCopyJSON = true
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let text = renderedOutputText {
                Text(text)
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.60))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)

                if didCopyJSON {
                    Text("Copied.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.60))
                }
            } else {
                Text("Output appears after scan.")
                    .foregroundStyle(.white.opacity(0.60))
            }
        }
    }

    private func flatRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.white.opacity(0.60))
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.white)
        }
        .font(.subheadline)
    }

    private func streamBitrateText(_ stream: MediaStream) -> String {
        guard let bitrate = stream.bitrate, bitrate > 0 else { return "N/A" }
        return "\(Int((Double(bitrate) / 1_000).rounded())) kb/s"
    }

    private var renderedOutputText: String? {
        guard let info = viewModel.mediaInfo else { return nil }

        switch selectedOutputFormat {
        case .json:
            return viewModel.metadataJSONOutput
        case .html:
            return """
            <html><body><pre>\(viewModel.metadataJSONOutput ?? "")</pre></body></html>
            """
        case .plainText:
            return [
                "Audio: \(info.hasAudio ? "Yes" : "No")",
                "Duration: \(info.durationText)",
                "Resolution: \(info.resolutionText)",
                "Video codec: \(info.videoCodecText)",
                "Audio codec: \(info.audioCodecText)",
                "Bitrate: \(info.bitrateText)"
            ].joined(separator: "\n")
        }
    }

    private func presentImporter() {
        viewModel.errorMessage = nil
        didCopyJSON = false
        selectedOutputFormat = .json
        isImporterPresented = true
    }

    private var showMetadata: Bool {
        viewModel.importedFileURL != nil && !viewModel.isAnalyzing && viewModel.mediaInfo != nil
    }

    private var showOutput: Bool {
        showMetadata && viewModel.metadataJSONOutput != nil
    }
}

private enum MetadataOutputFormat: String, CaseIterable, Identifiable {
    case json
    case html
    case plainText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .json: "JSON"
        case .html: "HTML"
        case .plainText: "Text"
        }
    }
}

#Preview {
    MediaInfoView()
}
