import SwiftUI

/// System Liquid Glass on iOS 26; the same layout uses material on iOS 17–18.
struct HarborGlass: ViewModifier {
    var radius: CGFloat = 28
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if reduceTransparency {
            content.background(Color(white: 0.13), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5).allowsHitTesting(false))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(.black.opacity(0.22)).interactive(interactive), in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
                .background(.black.opacity(0.25), in: shape)
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.05), .white.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75).allowsHitTesting(false))
                .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
        }
    }
}

extension View {
    func harborGlass(radius: CGFloat = 28, interactive: Bool = false) -> some View {
        modifier(HarborGlass(radius: radius, interactive: interactive))
    }
}

struct HarborGlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) { content() }
        } else {
            content()
        }
    }
}

struct PlayerGlassPanel<Content: View>: View {
    let title: String
    let symbol: String
    var back: (() -> Void)?
    let close: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let back {
                    Button(action: back) { Image(systemName: "chevron.left").frame(width: 36, height: 44) }.accessibilityLabel("Zurück zu Einstellungen")
                } else {
                    Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 24)
                }
                Text(title).font(.headline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).frame(width: 44, height: 44) }.accessibilityLabel("Fertig")
            }.padding(.horizontal, 16).padding(.vertical, 6)
            Divider().overlay(.white.opacity(0.08)).padding(.horizontal, 18)
            ScrollView {
                VStack(spacing: 0) { content() }.padding(.horizontal, 14).padding(.vertical, 8)
            }.scrollBounceBehavior(.basedOnSize).accessibilityIdentifier("playerPanelScroll")
        }
        .buttonStyle(.plain).tint(.white).foregroundStyle(.white)
        .harborGlass(radius: 30).accessibilityIdentifier("playerSettingsPanel")
    }
}

struct PlayerMenuRow: View {
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    var selected = false
    var disclosure = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let symbol { Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(.secondary).frame(width: 25) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body).foregroundStyle(.white)
                    if let subtitle, !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(2) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if selected { Image(systemName: "checkmark").font(.system(size: 17, weight: .semibold)) }
                if disclosure { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary) }
            }.padding(.horizontal, 10).padding(.vertical, 12).frame(minHeight: 48).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct PlaybackTimeline: View {
    let position: Double
    let duration: Double
    let step: Double
    @Binding var scrubbing: Bool
    @Binding var preview: Double
    let seek: (Double) -> Void
    let touch: () -> Void

    private var fraction: Double { min(1, max(0, (scrubbing ? preview : position) / max(1, duration))) }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.24)).frame(height: 4)
                Capsule().fill(.white).frame(width: max(0, geometry.size.width * fraction), height: 4)
                if scrubbing {
                    Circle().fill(.white).frame(width: 12, height: 12).offset(x: max(0, min(geometry.size.width - 12, geometry.size.width * fraction - 6)))
                }
            }.frame(height: 32).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    guard duration > 0 else { return }
                    scrubbing = true
                    preview = min(1, max(0, value.location.x / max(1, geometry.size.width))) * duration
                    touch()
                }.onEnded { _ in
                    guard scrubbing else { return }
                    seek(preview); scrubbing = false; touch()
                })
        }.frame(height: 32)
            .accessibilityElement().accessibilityLabel("Wiedergabeposition")
            .accessibilityValue("\(Int(position)) von \(Int(duration)) Sekunden")
            .accessibilityAdjustableAction { direction in
                guard duration > 0 else { return }
                seek(min(duration, max(0, position + (direction == .increment ? step : -step)))); touch()
            }
    }
}
