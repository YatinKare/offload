import SwiftUI

struct AppRoot: View {
    @AppStorage("completedTutorialV1") private var completed = false
    @State private var forced = false
    @State private var checkedArguments = false
    var body: some View {
        Group {
            if !completed || forced {
                TutorialView { completed = true; forced = false }
            } else { ReviewView() }
        }
        .onAppear {
            guard !checkedArguments else { return }; checkedArguments = true
            #if targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--show-tutorial") { forced = true }
            #endif
        }
    }
}

struct TutorialView: View {
    let onFinish: () -> Void
    @State private var page = 0
    private let ink = Color(red: 0.12, green: 0.22, blue: 0.21)
    private let steps: [(icon: String, title: String, body: String, tip: String)] = [
        ("externaldrive.badge.plus", "Connect your drive.", "Plug your USB drive into your iPhone. In the app, tap the drive icon and choose a folder on it.", "No drive? You can still review and keep photos. Archiving stays locked."),
        ("arrow.left", "Left to archive.", "Adds a copy to your queue. Keep swiping while the originals are copied and verified.", "A swipe never deletes a photo. It stays on your phone until you confirm removal later."),
        ("arrow.right", "Right to keep.", "Keeps the photo on your phone. After five seconds without a swipe, it stays.", "Tap the ring to pause. The curved arrow undoes your last choice."),
        ("checkmark.shield", "Remove when ready.", "Tap the archive button to see each photo, check its copy, or archive it again before removing originals.", "With iCloud Photos, deletion syncs across devices. Recently Deleted may still hold the space for 30 days.")
    ]
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                Button("Skip", action: onFinish).font(.subheadline).accessibilityIdentifier("tutorialSkip")
            }.padding(.top, 20)
            TabView(selection: $page) {
                ForEach(0..<steps.count, id: \.self) { index in
                    VStack(spacing: 25) {
                        Spacer(minLength: 8)
                        Image(systemName: steps[index].icon).font(.system(size: 60, weight: .ultraLight))
                            .frame(width: 140, height: 140).background(ink.opacity(0.07), in: Circle()).accessibilityHidden(true)
                        Text(steps[index].title).font(.system(size: 35, weight: .regular, design: .serif)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        Text(steps[index].body).font(.system(size: 18)).multilineTextAlignment(.center).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                        Text(steps[index].tip).font(.subheadline).lineSpacing(4).multilineTextAlignment(.center)
                            .padding(18).frame(maxWidth: .infinity).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 18)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                    }.padding(.horizontal, 4).tag(index)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never)).accessibilityIdentifier("tutorialPages")
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Capsule().fill(ink.opacity(index == page ? 1 : 0.15)).frame(width: index == page ? 24 : 7, height: 7)
                }
            }.accessibilityHidden(true)
            Text("\(page + 1) of \(steps.count) · Swipe to explore").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("tutorialStep")
            Button {
                if page < steps.count - 1 { withAnimation { page += 1 } } else { onFinish() }
            } label: {
                Text(page == steps.count - 1 ? "Let’s begin" : "Next").bold().frame(maxWidth: .infinity).padding(19)
            }.background(ink, in: RoundedRectangle(cornerRadius: 18)).foregroundStyle(.white)
                .accessibilityIdentifier(page == steps.count - 1 ? "tutorialBegin" : "tutorialNext")
        }
        .padding(.horizontal, 26).padding(.bottom, 22)
        .background(Color(red: 0.97, green: 0.96, blue: 0.92)).foregroundStyle(ink)
    }
}
