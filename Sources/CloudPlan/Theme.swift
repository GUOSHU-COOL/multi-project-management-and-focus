import AppKit
import SwiftUI

enum SkyTheme {
    static let sea = Color(red: 0.02, green: 0.39, blue: 0.67)
    static let sky = Color(red: 0.25, green: 0.68, blue: 0.95)
    static let paleSky = Color(red: 0.77, green: 0.91, blue: 0.99)
    static let milk = Color(red: 1.0, green: 0.99, blue: 0.96)
    static let ink = Color(red: 0.08, green: 0.19, blue: 0.28)
    static let focusYellow = Color(red: 1.0, green: 0.76, blue: 0.16)
    static let scheduleYellow = Color(red: 1.0, green: 0.91, blue: 0.57)
    static let completedWash = Color(red: 0.82, green: 0.86, blue: 0.85)
}

struct SkyBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.04, green: 0.12, blue: 0.19), Color(red: 0.05, green: 0.22, blue: 0.34)]
                    : [Color(red: 0.90, green: 0.97, blue: 1.0), Color(red: 0.71, green: 0.89, blue: 0.99)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            CloudView(scale: 1.35).opacity(colorScheme == .dark ? 0.08 : 0.46).offset(x: 250, y: -230)
            CloudView(scale: 0.75).opacity(colorScheme == .dark ? 0.05 : 0.25).offset(x: -310, y: 260)
        }
        .ignoresSafeArea()
    }
}

struct CloudView: View {
    var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule().frame(width: 190, height: 62)
            Circle().frame(width: 92, height: 92).offset(x: -35, y: -20)
            Circle().frame(width: 118, height: 118).offset(x: 28, y: -20)
        }
        .foregroundStyle(SkyTheme.milk)
        .scaleEffect(scale)
        .blur(radius: 0.4)
        .accessibilityHidden(true)
    }
}

struct GlassPanel<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.32), lineWidth: 1)
            }
            .shadow(color: SkyTheme.sea.opacity(0.10), radius: 20, y: 8)
    }
}

struct EditorHeader: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(SkyTheme.sea, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

struct EditorField<Content: View>: View {
    let label: String
    let symbol: String
    let content: Content

    init(_ label: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(label, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct QuietInputModifier: ViewModifier {
    let minHeight: CGFloat
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(minHeight: minHeight, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isFocused ? SkyTheme.sky : Color.primary.opacity(0.11), lineWidth: isFocused ? 2 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

extension View {
    func quietInput(minHeight: CGFloat = 42, isFocused: Bool = false) -> some View {
        modifier(QuietInputModifier(minHeight: minHeight, isFocused: isFocused))
    }
}

struct DurationControl: View {
    @Binding var minutes: Int
    var label = "预计用时"

    var body: some View {
        HStack(spacing: 12) {
            Label(label, systemImage: "timer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 6) {
                Button {
                    minutes = max(5, minutes - 5)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 28, height: 26)
                }
                .disabled(minutes <= 5)
                Text("\(minutes) 分钟")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 78)
                Button {
                    minutes = min(720, minutes + 5)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 26)
                }
                .disabled(minutes >= 720)
            }
            .buttonStyle(.plain)
            .padding(5)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

struct QuietIconButton: View {
    let symbol: String
    let helpText: String
    var isActive = false
    var isDisabled = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .frame(width: 27, height: 25)
                .background(
                    isActive || isHovered ? SkyTheme.sky.opacity(0.20) : Color.primary.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 5)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? SkyTheme.sea : .secondary)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.65 : 1)
        .help(helpText)
        .onHover { isHovered = $0 }
        .accessibilityLabel(helpText)
    }
}

struct SourcePill: View {
    let source: TaskSource
    var body: some View {
        Label(source.title, systemImage: source == .project ? "square.grid.2x2" : source == .routine ? "infinity" : "sparkles")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(source == .spontaneous ? SkyTheme.sea : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(source == .spontaneous ? SkyTheme.paleSky.opacity(0.7) : Color.secondary.opacity(0.10), in: Capsule())
    }
}
