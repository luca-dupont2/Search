import SwiftUI

// The pieces every panel is made of, so that Settings, History, Downloads,
// Passwords and Bookmarks read as one kind of thing: the same plate, the
// same title with the cross beside it, the same hairline cards with a rule
// between lines, the same field for searching. Built once here; each panel
// only says what goes in it.

/// The plate: a rounded card with a title, a cross, whatever the panel is
/// about, and — when there is one — a foot below a hairline.
struct Plate<Content: View, Foot: View>: View {
    let title: String
    var width: CGFloat = 560
    let close: () -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let foot: () -> Foot

    init(
        _ title: String,
        width: CGFloat = 560,
        close: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder foot: @escaping () -> Foot
    ) {
        self.title = title
        self.width = width
        self.close = close
        self.content = content
        self.foot = foot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                Door(icon: "xmark", help: "Done   esc", act: close)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 14)

            content()
                .padding(.horizontal, 22)

            if Foot.self != EmptyView.self {
                Rectangle().fill(Palette.hairline).frame(height: 1)
                    .padding(.top, 18)
                foot()
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
            } else {
                Color.clear.frame(height: 20)
            }
        }
        .frame(width: width, alignment: .leading)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 34, y: 12)
    }
}

extension Plate where Foot == EmptyView {
    init(
        _ title: String,
        width: CGFloat = 560,
        close: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(title, width: width, close: close, content: content, foot: { EmptyView() })
    }
}

/// A group of lines in one hairline box.
struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(Palette.ground)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
    }
}

/// The hairline between two lines of a card, inset like the text.
struct Rule: View {
    var inset: CGFloat = 14
    var body: some View {
        Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, inset)
    }
}

/// Focus target for a searchable setting's control, passed from its row to
/// whichever native control the row contains.
struct SettingsControlFocus {
    var id: String?
    var title: String?
    var focus: FocusState<String?>.Binding?

    var isFocused: Bool {
        guard let id else { return false }
        return focus?.wrappedValue == id
    }
}

private struct SettingsControlFocusKey: EnvironmentKey {
    static let defaultValue = SettingsControlFocus(id: nil, title: nil, focus: nil)
}

extension EnvironmentValues {
    var settingsControlFocus: SettingsControlFocus {
        get { self[SettingsControlFocusKey.self] }
        set { self[SettingsControlFocusKey.self] = newValue }
    }
}

private struct SettingsControlFocusModifier: ViewModifier {
    @Environment(\.settingsControlFocus) private var target
    var enabled = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled, let id = target.id, let focus = target.focus {
            content
                .focusable()
                .focused(focus, equals: id)
        } else {
            content
        }
    }
}

extension View {
    func settingsControlFocusTarget(_ enabled: Bool = true) -> some View {
        modifier(SettingsControlFocusModifier(enabled: enabled))
    }
}

/// One thing to set or do: what it is on the left, the control on the right.
struct Line<Control: View>: View {
    @Environment(\.settingsControlFocus) private var settingsFocus

    let title: String
    let detail: String?
    let searchID: String?
    let highlighted: Bool
    @ViewBuilder let control: () -> Control

    init(
        _ title: String,
        _ detail: String? = nil,
        searchID: String? = nil,
        highlighted: Bool = false,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.detail = detail
        self.searchID = searchID
        self.highlighted = highlighted
        self.control = control
    }

    @ViewBuilder
    var body: some View {
        let row = HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control()
                .environment(
                    \.settingsControlFocus,
                    SettingsControlFocus(id: searchID, title: title, focus: settingsFocus.focus)
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.wash)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            }
        }
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Palette.ink.opacity(0.08), lineWidth: 1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .allowsHitTesting(false)
            }
        }
        .animation(Motion.quick, value: highlighted)

        if let searchID {
            row.id(searchID)
        } else {
            row
        }
    }
}

/// A small heading over a card, for when a panel has more than one.
struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Palette.muted)
            .padding(.leading, 2)
    }
}

/// The field for narrowing a list. The wash, the glass, the caret.
struct Hunt: View {
    @Binding var text: String
    var prompt = "Search"
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.muted)
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(prompt).foregroundStyle(Palette.muted.opacity(0.7))
                }
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Palette.ink)
                    .focused(focus)
            }
            .font(.system(size: 13))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.faint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// What a panel says when its list is empty.
struct Nothing: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
    }
}

/// A small text action inside a row — Show, Copy, Remove.
struct Quick: View {
    let title: String
    var tint: Color = Palette.ink
    let act: () -> Void

    init(_ title: String, tint: Color = Palette.ink, act: @escaping () -> Void) {
        self.title = title
        self.tint = tint
        self.act = act
    }

    var body: some View {
        Button(action: act) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Palette.wash, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
