import SwiftUI
import UniformTypeIdentifiers
import ImageIO

@MainActor
final class WindowPetStore: ObservableObject {
    private let defaults: UserDefaults
    private let imageURL: URL
    @Published private(set) var artwork: NSImage
    @Published private(set) var hasCustomImage: Bool
    var aspect: Double { artwork.size.height > 0 ? artwork.size.width / artwork.size.height : PetPlacement.aspect }
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "windowPet.enabled") } }
    @Published var tapLines: String { didSet { defaults.set(tapLines, forKey: "windowPet.tapLines") } }
    @Published var holdLines: String { didSet { defaults.set(holdLines, forKey: "windowPet.holdLines") } }
    @Published private(set) var placement: PetPlacement
    static let defaultTapLines = "今天也一起加油吧！\n课表看好，别跑错教室啦。\n我在这里陪你。"
    static let defaultHoldLines = "正在蓄力……\n再按一会儿，我要弹起来啦！"
    static let defaultArtwork: NSImage = {
        if let url = Bundle.main.url(forResource: "WindowPet", withExtension: "png"), let image = NSImage(contentsOf: url) { return image }
        return NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "窗口桌宠") ?? NSImage()
    }()
    init(defaults: UserDefaults = .standard, imageURL: URL? = nil) {
        self.defaults = defaults
        let savedURL = imageURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CampusSchedule/WindowPet/custom.png")
        self.imageURL = savedURL
        let saved = NSImage(contentsOf: savedURL)
        artwork = saved ?? Self.defaultArtwork
        hasCustomImage = saved != nil
        enabled = defaults.object(forKey: "windowPet.enabled") == nil ? true : defaults.bool(forKey: "windowPet.enabled")
        tapLines = defaults.string(forKey: "windowPet.tapLines") ?? Self.defaultTapLines
        holdLines = defaults.string(forKey: "windowPet.holdLines") ?? Self.defaultHoldLines
        if let data = defaults.data(forKey: "windowPet.placement"), let saved = try? JSONDecoder().decode(PetPlacement.self, from: data) {
            placement = saved.normalized
        } else { placement = PetPlacement() }
    }
    /// Decode away from the UI thread and retain a bounded, oriented PNG copy.
    nonisolated static func prepareImage(at url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 30 * 1024 * 1024 else { throw PetImageError.tooLarge }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 30 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024
              ] as CFDictionary) else { throw PetImageError.unreadable }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw PetImageError.unreadable }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw PetImageError.unreadable }
        return output as Data
    }
    func applyImage(_ data: Data) throws {
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else { throw PetImageError.unreadable }
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: imageURL, options: .atomic)
        artwork = image; hasCustomImage = true
    }
    func restoreDefaultImage() throws {
        if FileManager.default.fileExists(atPath: imageURL.path) { try FileManager.default.removeItem(at: imageURL) }
        artwork = Self.defaultArtwork; hasCustomImage = false
    }
    private func setPlacement(_ value: PetPlacement) {
        placement = value.normalized
        if let data = try? JSONEncoder().encode(placement) { defaults.set(data, forKey: "windowPet.placement") }
    }
    func resize(_ size: Double) { var value = placement; value.size = size; setPlacement(value) }
    func move(toX x: Double, y: Double, area: CGSize) {
        setPlacement(placement.moved(toX: x, y: y, inWidth: area.width, height: area.height, aspect: aspect))
    }
    func preset(x: Double, y: Double) { var value = placement; value.x = x; value.y = y; setPlacement(value) }
    func resetPosition() { preset(x: 1, y: 1) }
    func line(holding: Bool) -> String? {
        (holding ? holdLines : tapLines).components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.randomElement()
    }
}

struct WindowPetOverlay: View {
    @EnvironmentObject private var pet: WindowPetStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressID: UUID?
    @State private var pressedAt: Date?
    @State private var anchor: CGPoint?
    @State private var dragOffset = CGSize.zero
    @State private var dragging = false
    @State private var charging = false
    @State private var scaleX = 1.0
    @State private var scaleY = 1.0
    @State private var lift = 0.0
    @State private var speech: String?
    @State private var speechHeight: CGFloat = 70
    @State private var chargeTask: Task<Void, Never>?
    @State private var bounceTask: Task<Void, Never>?
    @State private var speechTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            let area = geometry.size
            let frame = pet.placement.frame(inWidth: area.width, height: area.height, aspect: pet.aspect)
            let x = (anchor?.x ?? CGFloat(frame.x)) + dragOffset.width
            let y = (anchor?.y ?? CGFloat(frame.y)) + dragOffset.height
            ZStack(alignment: .topLeading) {
                if pet.enabled {
                    Image(nsImage: pet.artwork).resizable().scaledToFit()
                        .frame(width: frame.width, height: frame.height)
                        .scaleEffect(x: scaleX, y: scaleY, anchor: .bottom)
                        .offset(y: lift)
                        .contentShape(Rectangle())
                        .gesture(interaction(area: area, frame: frame))
                        .contextMenu {
                            Button("放大一点") { pet.resize(pet.placement.size + 16) }
                            Button("缩小一点") { pet.resize(pet.placement.size - 16) }
                            Button("回到右下角") { pet.resetPosition() }
                            Divider()
                            Button("隐藏桌宠") { pet.enabled = false }
                        }
                        .accessibilityLabel("窗口桌宠，拖动可改变位置，点击弹跳，长按蓄力")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { showLine(holding: false); bounce(held: false) }
                        .position(x: x + frame.width / 2, y: y + frame.height / 2)
                    if let speech, !dragging {
                        let width = min(230, max(100, area.width - 24))
                        let above = y - speechHeight - 12 >= 64
                        let centerX = min(area.width - width / 2 - 8, max(width / 2 + 8, x + frame.width / 2))
                        let desiredY = above ? y - 12 - speechHeight / 2 : y + frame.height + 12 + speechHeight / 2
                        speechBubble(speech, width: width)
                            .position(x: centerX, y: min(area.height - speechHeight / 2 - 8, max(64 + speechHeight / 2, desiredY)))
                            .transition(.opacity)
                    }
                }
            }
        }.onDisappear { cancelInteraction() }
            .onChange(of: pet.enabled) { _, value in if !value { cancelInteraction() } }
    }

    private func interaction(area: CGSize, frame: PetFrame) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if pressID == nil {
                    let token = UUID()
                    pressID = token; pressedAt = Date(); anchor = CGPoint(x: frame.x, y: frame.y)
                    dragOffset = .zero; dragging = false; charging = false
                    bounceTask?.cancel()
                    scaleX = 1; scaleY = 1; lift = 0
                    chargeTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard !Task.isCancelled, pressID == token, !dragging else { return }
                        charging = true
                        showLine(holding: true)
                        withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.9)) {
                            scaleX = reduceMotion ? 1 : 1.18
                            scaleY = reduceMotion ? 0.96 : 0.65
                            lift = reduceMotion ? 0 : 3
                        }
                    }
                }
                if hypot(value.translation.width, value.translation.height) > 7 || dragging {
                    if !dragging {
                        dragging = true; charging = false; chargeTask?.cancel()
                        speechTask?.cancel(); speech = nil
                        scaleX = 1; scaleY = 1; lift = 0
                    }
                    if let anchor {
                        let placement = pet.placement.moved(toX: anchor.x + value.translation.width,
                            y: anchor.y + value.translation.height, inWidth: area.width, height: area.height, aspect: pet.aspect)
                        let moved = placement.frame(inWidth: area.width, height: area.height, aspect: pet.aspect)
                        dragOffset = CGSize(width: moved.x - anchor.x, height: moved.y - anchor.y)
                    }
                }
            }
            .onEnded { _ in
                chargeTask?.cancel()
                if dragging, let anchor {
                    pet.move(toX: anchor.x + dragOffset.width, y: anchor.y + dragOffset.height, area: area)
                } else {
                    let held = charging || pressedAt.map { Date().timeIntervalSince($0) >= 0.35 } == true
                    showLine(holding: held, reuseCurrent: held && charging)
                    bounce(held: held)
                }
                pressID = nil; pressedAt = nil; anchor = nil; dragOffset = .zero
                dragging = false; charging = false
            }
    }
    private func showLine(holding: Bool, reuseCurrent: Bool = false) {
        speechTask?.cancel()
        if !reuseCurrent || speech == nil {
            withAnimation(.easeOut(duration: 0.15)) { speech = pet.line(holding: holding) }
        }
        speechTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, !(charging && pressID != nil) else { return }
            withAnimation(.easeOut(duration: 0.2)) { speech = nil }
        }
    }
    private func bounce(held: Bool) {
        bounceTask?.cancel()
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) { scaleX = 1; scaleY = 1; lift = 0 }
            return
        }
        if !held {
            withAnimation(.easeOut(duration: 0.08)) { scaleX = 1.12; scaleY = 0.83; lift = 0 }
        }
        bounceTask = Task { @MainActor in
            if !held { try? await Task.sleep(nanoseconds: 80_000_000) }
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.45)) {
                scaleX = held ? 0.9 : 0.96; scaleY = held ? 1.12 : 1.04; lift = held ? -44 : -14
            }
            try? await Task.sleep(nanoseconds: held ? 230_000_000 : 150_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.48, dampingFraction: 0.42)) { scaleX = 1; scaleY = 1; lift = 0 }
        }
    }
    private func speechBubble(_ text: String, width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(text).font(.system(size: 12)).foregroundStyle(CampusTheme.boardText)
                .lineLimit(6).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            Button { speechTask?.cancel(); speech = nil } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }.buttonStyle(.plain).help("收起台词")
        }.padding(12).frame(width: width)
            .background(CampusTheme.board, in: RoundedRectangle(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(CampusTheme.boardLine) }
            .shadow(color: .black.opacity(0.12), radius: 9, y: 3)
            .background(GeometryReader { proxy in Color.clear.preference(key: SpeechHeightKey.self, value: proxy.size.height) })
            .onPreferenceChange(SpeechHeightKey.self) { speechHeight = $0 }
    }
    private func cancelInteraction() {
        chargeTask?.cancel(); bounceTask?.cancel(); speechTask?.cancel()
        pressID = nil; pressedAt = nil; anchor = nil; dragOffset = .zero
        dragging = false; charging = false; speech = nil
        scaleX = 1; scaleY = 1; lift = 0
    }
}

private struct SpeechHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 70
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private enum PetImageError: LocalizedError {
    case tooLarge, unreadable
    var errorDescription: String? {
        switch self {
        case .tooLarge: return "请选择 30 MB 以内的图片。"
        case .unreadable: return "无法读取这张图片，请换一张 PNG、JPEG 或其他系统支持的图片。"
        }
    }
}

struct WindowPetSettingsView: View {
    @EnvironmentObject private var pet: WindowPetStore
    @State private var choosingImage = false
    @State private var importingImage = false
    @State private var imageError: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 20) {
                    Image(nsImage: pet.artwork).resizable().scaledToFit().frame(width: 100, height: 100)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("窗口桌宠").font(.title2).fontWeight(.semibold)
                        Text("点击果冻弹跳，长按蓄力，松手弹起；直接拖动可放到喜欢的位置。")
                            .font(.callout).foregroundStyle(.secondary)
                        Toggle("显示桌宠", isOn: $pet.enabled)
                    }
                }
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Button(importingImage ? "正在导入…" : "选择图片…") { choosingImage = true }
                            .disabled(importingImage)
                        Button("恢复默认图片") {
                            do { try pet.restoreDefaultImage() } catch { imageError = error.localizedDescription }
                        }.disabled(!pet.hasCustomImage || importingImage)
                        if importingImage { ProgressView().controlSize(.small) }
                    }
                    Text("支持 PNG、JPEG 等系统图片格式，推荐透明背景；动图使用第一帧。图片会保存副本，移动或删除原文件不影响桌宠。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("大小").font(.headline); Spacer(); Text("\(Int(pet.placement.size)) pt").foregroundStyle(.secondary) }
                    Slider(value: Binding(get: { pet.placement.size }, set: { pet.resize($0) }), in: 72...240, step: 1)
                    HStack {
                        Button("左上") { pet.preset(x: 0, y: 0) }
                        Button("右上") { pet.preset(x: 1, y: 0) }
                        Button("左下") { pet.preset(x: 0, y: 1) }
                        Button("右下") { pet.resetPosition() }
                        Button("居中") { pet.preset(x: 0.5, y: 0.5) }
                    }.controlSize(.small)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("点击台词").font(.headline)
                    MultilineTextInput(text: $pet.tapLines, placeholder: "每行一句，点击时随机选择；留空则不显示。", height: 110)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("长按台词").font(.headline)
                    MultilineTextInput(text: $pet.holdLines, placeholder: "每行一句，长按时随机选择；留空则不显示。", height: 110)
                }
                Text("回车即可换行，每行作为一句台词。位置、大小和台词自动保存在本机。右键桌宠也可调整大小、回到右下角或隐藏；在这里可重新开启。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
        .fileImporter(isPresented: $choosingImage, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                importingImage = true
                Task { @MainActor in
                    defer { importingImage = false }
                    do {
                        let data = try await Task.detached(priority: .userInitiated) { try WindowPetStore.prepareImage(at: url) }.value
                        try pet.applyImage(data)
                    } catch { imageError = error.localizedDescription }
                }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { imageError = error.localizedDescription }
            }
        }
        .alert("桌宠图片", isPresented: Binding(get: { imageError != nil }, set: { if !$0 { imageError = nil } })) {
            Button("好", role: .cancel) { imageError = nil }
        } message: { Text(imageError ?? "") }
    }
}
