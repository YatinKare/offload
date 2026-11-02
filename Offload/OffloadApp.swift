import SwiftUI
import Photos
import UniformTypeIdentifiers

@main struct OffloadApp: App {
    var body: some Scene { WindowGroup { AppRoot() } }
}
struct ReviewView: View {
    @StateObject private var model = ReviewModel()
    @State private var showDrive = false
    @State private var showTutorial = false
    @State private var picker = false
    @State private var drag: CGFloat = 0
    @State private var dragging = false
    @State private var pausedBeforeDrag = false
    @Environment(\.scenePhase) private var phase
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if model.ready, !model.finished {
                ZStack {
                    if let image = model.image { Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else { ProgressView().tint(.white) }
                }
                .contentShape(Rectangle()).accessibilityElement(children: .ignore).accessibilityLabel("Photo")
                .accessibilityIdentifier("photoCard").offset(x: drag).rotationEffect(.degrees(Double(drag) / 50))
                .gesture(DragGesture().onChanged { value in
                    guard !model.busy else { return }
                    if !dragging { pausedBeforeDrag = model.paused; dragging = true }
                    model.paused = true; drag = value.translation.width
                }.onEnded { value in
                    drag = 0; dragging = false
                    let wasPaused = pausedBeforeDrag
                    if value.translation.width < -80 {
                        Task { await model.archive(); model.paused = wasPaused }
                    } else {
                        if value.translation.width > 80 { model.keep() }
                        model.paused = wasPaused
                    }
                })
                if drag != 0 {
                    LinearGradient(
                        stops: [
                            .init(color: (drag < 0 ? Color.red : Color.green).opacity(min(Double(abs(drag)) / 120, 1) * 0.65), location: 0),
                            .init(color: .clear, location: 0.28),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: drag < 0 ? .leading : .trailing,
                        endPoint: drag < 0 ? .trailing : .leading
                    )
                    .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
                }
            } else if model.finished {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark").font(.system(size: 45, weight: .light))
                    Text("All reviewed").font(.title2)
                }.foregroundStyle(.white)
            } else {
                VStack(spacing: 18) {
                    Button { showDrive = true } label: { Label(model.root == nil ? "Connect drive" : "Drive connected", systemImage: "externaldrive").frame(maxWidth: 250).padding(18) }
                        .background(.white.opacity(0.12), in: Capsule())
                    Button { Task { await model.load() } } label: { Text("Open Photos").bold().frame(maxWidth: 250).padding(18) }
                        .background(.white, in: Capsule()).foregroundStyle(.black).accessibilityIdentifier("start").disabled(model.busy)
                }.foregroundStyle(.white)
            }
            VStack {
                HStack(spacing: 18) {
                    icon("externaldrive", label: "Manage drive", id: "drive") { showDrive = true }
                    icon("questionmark", label: "How to use Offload", id: "showTutorial") { showTutorial = true }
                    Spacer()
                    if model.ready, !model.finished {
                        Text("\(model.index + 1)/\(model.assets.count)").font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
                        Button { model.paused.toggle() } label: {
                            ZStack {
                                Circle().stroke(.white.opacity(0.3), lineWidth: 2)
                                Circle().trim(from: 0, to: CGFloat(model.seconds) / 5).stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
                                Image(systemName: model.paused ? "play.fill" : "pause.fill").font(.system(size: 11))
                            }.frame(width: 38, height: 38)
                        }.foregroundStyle(.white).accessibilityLabel(model.paused ? "Resume review" : "Pause review").accessibilityIdentifier("pause").disabled(model.busy)
                    }
                }
                Spacer()
                HStack {
                    if !model.history.isEmpty { icon("arrow.uturn.backward", label: "Undo", id: "undo") { model.undo() } }
                    Spacer()
                    if !model.receipts.isEmpty {
                        Button { model.paused = true; model.showRemoval = true } label: {
                            HStack(spacing: 7) { Image(systemName: "checkmark.circle"); Text("\(model.receipts.count)").monospacedDigit() }.padding(13).background(.ultraThinMaterial, in: Capsule())
                        }.foregroundStyle(.white).accessibilityLabel("Review removal, \(model.receipts.count) archived").accessibilityIdentifier("reviewRemoval").disabled(model.busy)
                    }
                }
            }.padding(.horizontal, 22).padding(.vertical, 10)
            if model.busy { ProgressView().tint(.white).padding(20).background(.ultraThinMaterial, in: Circle()) }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("reviewState")
        .accessibilityValue("\(model.receipts.count) archived. \(model.kept) kept.")
        .sheet(isPresented: $showDrive) { driveSheet }
        .fullScreenCover(isPresented: $showTutorial) { TutorialView { showTutorial = false } }
        .alert("Couldn't finish", isPresented: Binding(get: { model.error != nil && !showDrive }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        .alert("Remove archived photos?", isPresented: $model.showRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Verify & remove", role: .destructive) { Task { await model.removeVerified() } }.accessibilityIdentifier("confirmRemoval")
        } message: {
            Text("Re-check \(model.receipts.count) copies on your drive, then remove the originals from Photos. iCloud deletion syncs across devices. Recently Deleted may hold them for 30 days before space is freed.")
        }
        .onReceive(timer) { _ in model.tick(active: phase == .active && !showDrive && !showTutorial && !model.showRemoval && model.error == nil) }
        .onOpenURL { url in
            #if targetEnvironment(simulator)
            guard model.simulation, url.scheme == "offload-test" else { return }
            switch url.host {
            case "connect": model.connectTestDrive()
            case "disconnect": model.disconnectTestDrive()
            case "corrupt": model.corruptTestCopy()
            case "internal": model.chooseDrive(URL.documentsDirectory)
            default: break
            }
            #endif
        }
    }
    private var driveSheet: some View {
        NavigationStack {
            Form {
                Section("Archive drive") {
                    Label(model.root?.lastPathComponent ?? "Not connected", systemImage: "externaldrive")
                    Button("Choose drive") { picker = true }.disabled(model.busy)
                }
                if !model.receipts.isEmpty {
                    Section {
                        Label("\(model.receipts.count) archived", systemImage: "checkmark.shield")
                    } footer: { Text("Originals stay in Photos until you confirm removal.") }
                }
            }
            .navigationTitle("Drive").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showDrive = false } } }
            .fileImporter(isPresented: $picker, allowedContentTypes: [.folder]) { result in
                switch result { case .success(let url): model.chooseDrive(url); case .failure(let error): model.error = error.localizedDescription }
            }
            .alert("Couldn't finish", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        }.presentationDetents([.medium, .large])
    }
    private func icon(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 17)).frame(width: 42, height: 42).background(.ultraThinMaterial, in: Circle()) }
            .foregroundStyle(.white).accessibilityLabel(label).accessibilityIdentifier(id).disabled(model.busy)
    }
}
