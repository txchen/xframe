import SwiftUI

struct XboxAccountView: View {
    let account: XboxAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "person.crop.circle.fill").font(.system(size: 42)).foregroundStyle(LibraryStyle.accent)
            Text(account.hasCloudAccess ? "Your Xbox account" : "Your next game starts here.").font(.title.bold())
            Text(account.hasCloudAccess ? "Manage your Microsoft sign-in and cloud access." : "Sign in with Microsoft to explore your cloud library.")
                .foregroundStyle(.secondary)
            if let gamertag = account.gamertag { Text(gamertag).font(.title2) }
            HStack {
                if account.isBusy { ProgressView().controlSize(.small) }
                Text(account.status).font(.headline)
            }
            if let code = account.userCode, let url = account.verificationURL {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Enter this code on Microsoft's sign-in page:")
                    Text(code).font(.system(size: 30, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                    Link("Open Microsoft Sign-In", destination: url)
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
            if let error = account.errorMessage { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if account.isBusy { Button("Cancel") { account.cancel() } }
                else {
                    if !account.hasSavedSignIn { Button("Sign In with Microsoft") { account.signIn() } }
                    if account.hasSavedSignIn { Button("Check Access Again") { account.restore() } }
                    if account.hasSavedSignIn && !account.hasCloudAccess { Button("Sign In Again") { account.signIn() } }
                }
                Spacer()
                if account.hasSavedSignIn { Button("Sign Out") { account.signOut() } }
            }.disabled(account.library.ownsSession || account.library.loading)
            DisclosureGroup("Development details") {
                Text("Sign-in is saved in an owner-only, unencrypted local file, not Keychain. Sign Out removes that file; legacy Keychain entries and browser sign-in are unchanged.")
                if !account.regionNames.isEmpty { Text("Available regions: \(account.regionNames.joined(separator: ", "))") }
            }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 520)
    }
}
