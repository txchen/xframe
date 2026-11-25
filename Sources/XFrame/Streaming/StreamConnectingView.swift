import SwiftUI

struct StreamConnectingView: View {
    let library: CloudLibrary
    var dismiss: () -> Void = {}

    nonisolated static func animatedDots(at date: Date) -> String {
        let phase = Int(floor(date.timeIntervalSinceReferenceDate / 0.45)) % 3
        return String(repeating: ".", count: ((phase % 3) + 3) % 3 + 1)
    }

    nonisolated static func animatedText(_ raw: String, at date: Date) -> String {
        var base = raw
        while base.hasSuffix("…") || base.hasSuffix(".") { base.removeLast() }
        return base + animatedDots(at: date)
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 420
            TimelineView(.periodic(from: .now, by: 0.45)) { context in
                let dots = Self.animatedDots(at: context.date)
                VStack(spacing: compact ? 10 : 24) {
                    if !compact {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(LibraryStyle.accent)
                    }
                    Text(library.activeGame ?? "Xbox streaming")
                        .font(.system(size: compact ? 18 : 28, weight: .bold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if !compact && library.errorMessage == nil {
                        ProgressView().controlSize(.large)
                    }
                    Text(library.errorMessage != nil
                         ? "Could not start the game"
                         : (library.ending ? "Ending session" : "Connecting to your game") + dots)
                        .font(.system(size: compact ? 18 : 24, weight: .semibold))
                    Text(library.errorMessage ?? Self.animatedText(library.status, at: context.date))
                        .font(.system(size: compact ? 14 : 17))
                        .foregroundStyle(.secondary)
                        .lineLimit(compact ? 2 : 4)
                        .multilineTextAlignment(.center)
                    if !compact && geometry.size.width > 580 && library.errorMessage == nil {
                        HStack(spacing: 20) {
                            Label("Session", systemImage: library.ready ? "checkmark.circle.fill" : "circle.dotted")
                            Label("Video connection", systemImage: library.ready ? "circle.dotted" : "circle")
                            Label("First frame", systemImage: "circle")
                        }.font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                    HStack {
                        if library.ownsSession {
                            Button("Cancel") { library.end() }.disabled(library.ending)
                        } else {
                            if library.retryGame != nil { Button("Retry") { library.retry() } }
                            Button("Back to library", action: dismiss)
                        }
                    }.controlSize(.large)
                }.padding(compact ? 12 : 32).frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .background(LibraryStyle.canvas).foregroundStyle(.white).preferredColorScheme(.dark)
    }
}
