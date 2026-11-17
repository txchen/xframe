import SwiftUI

struct XboxAccountView: View {
    let account: XboxAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "person.crop.circle.fill").font(.system(size: 42)).foregroundStyle(LibraryStyle.accent)
            Text(account.hasXboxSignIn ? "Your Xbox account" : "Your next game starts here.").font(.title.bold())
            Text(account.hasXboxSignIn ? "Console and cloud streaming access are checked separately." : "Sign in with Microsoft to stream from your Xbox or cloud library.")
                .foregroundStyle(.secondary)
            if let gamertag = account.gamertag { Text(gamertag).font(.title2) }
            HStack {
                if account.isBusy { ProgressView().controlSize(.small) }
                Text(account.status).font(.headline)
            }
            if let code = account.userCode, let url = account.verificationURL {
                VStack(alignment: .leading, spacing: 14) {
                    Text("1. Copy this sign-in code").font(.headline)
                    Text(code).font(.system(size: 30, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                    Text("2. Open Microsoft's website and enter the code").font(.headline)
                    Link(destination: url) {
                        Label("Open Microsoft Sign-In", systemImage: "arrow.up.right.square")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(LibraryStyle.accent, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens your browser to complete Microsoft sign-in")
                    Text("After signing in, return here. XFrame will continue automatically.")
                        .font(.callout).foregroundStyle(.secondary)
                    if let expires = account.codeExpires {
                        Text("Code expires at \(expires.formatted(date: .omitted, time: .standard)).").font(.caption)
                    }
                    Text("Use your personal Microsoft account with an Xbox profile. XFrame never sees your password.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }
            if let expires = account.accessExpires, let offering = account.offering {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(context.date < expires ? offering.label : "Credentials expired — check access again",
                              systemImage: context.date < expires ? "checkmark.circle.fill" : "clock")
                        Text("Valid until \(expires.formatted(date: .omitted, time: .standard))")
                    }.font(.callout)
                }
            }
            if let expires = account.homeExpires {
                Label(Date() < expires ? "Xbox console access verified" : "Console access expired — check again",
                      systemImage: Date() < expires ? "checkmark.circle.fill" : "clock")
            }
            if let error = account.homeError { Text("Console: " + error).foregroundStyle(.orange).textSelection(.enabled) }
            if let error = account.cloudError { Text("Cloud: " + error).foregroundStyle(.orange).textSelection(.enabled) }
            if let error = account.errorMessage { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if account.isBusy { Button("Cancel") { account.cancel() } }
                else {
                    if !account.hasSavedSignIn {
                        Button("Sign In with Microsoft") { account.signIn() }
                            .buttonStyle(.borderedProminent).tint(LibraryStyle.accent)
                    }
                    if account.hasSavedSignIn { Button("Check Access Again") { account.restore() } }
                    if account.hasSavedSignIn && !account.hasXboxSignIn { Button("Sign In Again") { account.signIn() } }
                }
                Spacer()
                if account.hasSavedSignIn { Button("Sign Out") { account.signOut() } }
            }.disabled(account.library.ownsSession || account.library.loading)
            DisclosureGroup("Development details") {
                Text(account.credentialStorageDescription)
                if !account.regionNames.isEmpty { Text("Available regions: \(account.regionNames.joined(separator: ", "))") }
            }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 520)
    }
}
