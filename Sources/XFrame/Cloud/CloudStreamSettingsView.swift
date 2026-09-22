import SwiftUI

struct CloudStreamSettingsView: View {
    @Bindable var library: CloudLibrary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Streaming Settings").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 10) {
                Picker("Stream quality", selection: $library.streamPreferences.quality) {
                    ForEach(CloudStreamQuality.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text("HQ requests higher streaming quality. Resolution and bitrate depend on the game, subscription and service. Bitrate is negotiated automatically.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                Picker("Game language", selection: $library.streamPreferences.language) {
                    ForEach(CloudGameLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text("Used when starting a new game session. Language availability depends on the game. XFrame and the library stay in English.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                Picker("Frame pacing", selection: $library.streamPreferences.framePacing) {
                    ForEach(FramePacingMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text("Balanced smooths brief frame-arrival jitter. Low latency keeps only the newest waiting frame; motion may be less even and more frames may be skipped. A latency reduction is not guaranteed.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            if let active = library.activeStreamPreferences {
                Text("Current session: \(active.summary)").font(.callout)
            }
            Text(library.ownsSession
                 ? "Saved for your next session. End this session, then start the game again to apply changes."
                 : "Saved automatically. These settings apply the next time you start a game.")
                .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
        }.padding(28).frame(width: 510)
            .background(LibraryStyle.canvas).foregroundStyle(.white)
            .preferredColorScheme(.dark)
    }
}
