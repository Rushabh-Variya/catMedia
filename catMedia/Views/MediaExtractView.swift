import SwiftUI
import UniformTypeIdentifiers

struct MediaExtractView: View {
    @StateObject private var viewModel = MediaExtractViewModel()
    @State private var isImporterPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    Divider().overlay(.primary.opacity(0.10))
                    importer
                    if viewModel.importedFileURL != nil {
                        Divider().overlay(.primary.opacity(0.10))
                        options
                    }
                    if viewModel.isExtracting || viewModel.outputURL != nil {
                        Divider().overlay(.primary.opacity(0.10))
                        progress
                    }
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
                .animation(UIAnimation.easeOut, value: viewModel.importedFileURL != nil)
                .animation(UIAnimation.easeOut, value: viewModel.outputURL != nil)
            }
            .background(Color.black)
            .navigationTitle("Extract")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ClearCacheToolbarButton()
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.item, .folder],
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
            Text("Extract streams")
                .font(.system(.largeTitle, design: .default).weight(.bold))
                .foregroundStyle(.white)
        }
    }

    private var importer: some View {
        Button {
            isImporterPresented = true
        } label: {
            VStack(spacing: 14) {
                Image(systemName: "scissors").font(.system(size: 30, weight: .semibold)).frame(width: 64, height: 64).background(.white.opacity(0.08), in: Circle())
                Text(viewModel.importedFileURL?.lastPathComponent ?? "Choose file or folder").font(.headline).foregroundStyle(.white)
                Text(viewModel.statusMessage.isEmpty ? "Tap to import source" : viewModel.statusMessage).font(.footnote).foregroundStyle(.white.opacity(0.60))
            }.frame(maxWidth: .infinity).frame(minHeight: 210).padding(24).background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 24, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.pressableCard)
        .disabled(viewModel.isAnalyzing || viewModel.isExtracting)
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mode").font(.headline.weight(.semibold)).foregroundStyle(.white)
            Picker("Extract", selection: $viewModel.selectedOption) {
                ForEach(MediaExtractOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)

            Text(viewModel.selectedOption.subtitle)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.60))

            Button("Extract") {
                Task { await viewModel.extract() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(white: 0.16))
            .foregroundStyle(.white)
            .disabled(viewModel.importedFileURL == nil || viewModel.isAnalyzing || viewModel.isExtracting)
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Progress").font(.headline.weight(.semibold)).foregroundStyle(.white)
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

            if !viewModel.executionLogLines.isEmpty {
                Text(viewModel.executionLogLines.joined(separator: "\n"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.55))
                    .textSelection(.enabled)
            }
        }
    }
}

#Preview {
    MediaExtractView()
}
