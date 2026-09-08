import SwiftUI
import UniformTypeIdentifiers

struct MediaConverterView: View {
    @StateObject private var viewModel = MediaConverterViewModel()
    @State private var isImporterPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    Divider().overlay(.primary.opacity(0.10))
                    uploader
                    if viewModel.importedFileURL != nil {
                        Divider().overlay(.primary.opacity(0.10))
                        options
                    }
                    if viewModel.isAnalyzing || viewModel.isConverting || viewModel.outputURL != nil {
                        Divider().overlay(.primary.opacity(0.10))
                        progress
                    }
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .background(Color.black)
            .navigationTitle("Conversion")
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
            Text("Convert media")
                .font(.system(.largeTitle, design: .default).weight(.bold))
                .foregroundStyle(.white)
            Text("Offline FFmpeg presets only. Clean flow, no command box.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.60))
        }
    }

    private var uploader: some View {
        Button {
            isImporterPresented = true
        } label: {
            VStack(spacing: 14) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 30, weight: .semibold))
                    .frame(width: 64, height: 64)
                    .background(.white.opacity(0.08), in: Circle())
                Text(viewModel.importedFileURL?.lastPathComponent ?? "Choose media file")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(viewModel.statusMessage.isEmpty ? "Tap to import and analyze" : viewModel.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.60))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 210)
            .padding(24)
            .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isAnalyzing || viewModel.isConverting)
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Presets")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            if viewModel.availableOptions.isEmpty {
                Text("No safe preset for this file.")
                    .foregroundStyle(.white.opacity(0.60))
            } else {
                Picker("Preset", selection: Binding(
                    get: { viewModel.selectedOption },
                    set: { viewModel.selectedOption = $0 }
                )) {
                    ForEach(viewModel.availableOptions) { option in
                        Text(option.title).tag(Optional(option))
                    }
                }
                .pickerStyle(.menu)

                if let option = viewModel.selectedOption {
                    Text(option.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.60))
                }

                Button("Convert") {
                    Task { await viewModel.convert() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(white: 0.16))
                .foregroundStyle(.white)
                .disabled(viewModel.selectedOption == nil || viewModel.isAnalyzing || viewModel.isConverting)
            }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Progress")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            ProgressView(value: viewModel.progress)

            HStack {
                Text("\(Int(viewModel.progress * 100))%")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.60))
                Spacer()
                if let outputURL = viewModel.outputURL {
                    Text(outputURL.lastPathComponent)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.60))
                }
            }

            if let latestCommand = viewModel.latestCommand {
                Text(latestCommand)
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.52))
                    .textSelection(.enabled)
                    .lineLimit(5)
            }
        }
    }
}

#Preview {
    MediaConverterView()
}
