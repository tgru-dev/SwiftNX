import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.13, blue: 0.30),
                        Color(red: 0.18, green: 0.24, blue: 0.55),
                        Color(red: 0.30, green: 0.25, blue: 0.62),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(Brand.accent.opacity(0.32))
                    .blur(radius: 70)
                    .frame(width: 360, height: 360)
                    .offset(x: 180, y: -90)
                Circle()
                    .fill(Brand.purple.opacity(0.26))
                    .blur(radius: 80)
                    .frame(width: 300, height: 300)
                    .offset(x: -200, y: 110)

                HStack(spacing: 22) {
                    BrandMark(size: 88)
                        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SwiftNX")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Native game porting, without the terminal.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                        Text("A SwiftUI frontend for nxnative")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer()
                }
                .padding(.horizontal, 38)
            }
            .frame(height: 230)

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("From your own dump to a Mac app")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                    Text("SwiftNX walks through the parts the nxnative guide asks you to do by hand: pick the files, configure the build, and watch every stage.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 18) {
                    WelcomeFeature(
                        icon: "1.circle.fill",
                        title: "Prepare the toolchain",
                        text: "Xcode, Metal, Homebrew, .NET and an isolated Python environment are checked with clear fixes."
                    )
                    WelcomeFeature(
                        icon: "2.circle.fill",
                        title: "Pick your files",
                        text: "Base game and update, with title ID detection and a profile check before anything starts."
                    )
                    WelcomeFeature(
                        icon: "3.circle.fill",
                        title: "Build & play",
                        text: "Live stage progress, ETA, a native log, then the app lands in your library."
                    )
                }

                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundStyle(Brand.warning)
                    Text("SwiftNX ships no games and no keys. Use dumps and prod.keys from your own Nintendo Switch. nxnative is an independent open-source project.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(11)
                .background(Brand.warning.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .padding(28)

            Spacer(minLength: 0)

            Divider().opacity(0.5)
            HStack(spacing: 10) {
                Button {
                    if let url = URL(string: "https://github.com/seedds/nxnative") {
                        AppActions.open(url)
                    }
                } label: {
                    Label("About nxnative", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10.5))

                Spacer()

                Button("Skip for Now") {
                    app.completeWelcome(setup: false)
                }
                .buttonStyle(.bordered)

                Button {
                    app.completeWelcome(setup: true)
                } label: {
                    Label("Set Up My Mac", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(.bar)
        }
        .frame(width: 720, height: 610)
        .interactiveDismissDisabled()
    }
}

private struct WelcomeFeature: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Brand.accent)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
