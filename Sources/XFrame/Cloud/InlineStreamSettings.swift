import SwiftUI

struct InlineStreamSettings: View {
    @Bindable var library: CloudLibrary
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { quality; pacing; language; more }
                VStack(alignment: .leading, spacing: 12) {
                    HStack { quality; pacing }
                    HStack { language; more }
                }
            }
            Text("Changes apply to the next session").font(.system(size: 14)).foregroundStyle(LibraryStyle.secondary)
        }.font(.system(size: 16)).controlSize(.large)
    }
    private var quality: some View {
        Picker("Quality", selection: $library.streamPreferences.quality) {
            ForEach(CloudStreamQuality.allCases, id: \.self) { Text($0.title).tag($0) }
        }.frame(maxWidth: 260)
    }
    private var pacing: some View {
        Picker("Pacing", selection: $library.streamPreferences.framePacing) {
            ForEach(FramePacingMode.allCases, id: \.self) { Text($0.title).tag($0) }
        }.frame(maxWidth: 270)
    }
    private var language: some View {
        Picker("Language", selection: $library.streamPreferences.language) {
            ForEach(CloudGameLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
        }.frame(maxWidth: 240)
    }
    private var more: some View {
        Button("More settings") { library.showingStreamSettings = true }
    }
}
