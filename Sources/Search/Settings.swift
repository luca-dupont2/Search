import SwiftUI

/// Pages down the left, one page at a time on the right. Searching lands on
/// a matching control and keeps it softly highlighted while results stay in
/// the rail. The same white and hairline as the rest of the app; the same
/// pill for the page you are on as for the tab you are on.
struct SettingsPanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    @ObservedObject private var updater = Updater.shared
    @ObservedObject private var shield = Shield.shared
    @State private var isDefault = Links.isDefault
    /// A site shortcut being written, kept out of Preferences until it's saved.
    @State private var draft: Keyword?
    @State private var page: Page = Page(rawValue: Store.settings.string(forKey: "settings.page") ?? "") ?? .general
    @State private var pageSearch = ""
    @State private var highlightedSettingID: String?
    @State private var highlightedSettingScroll: DispatchWorkItem?
    @FocusState private var focusedSettingsElement: String?

    private static let searchFieldFocusID = "settings.search"

    private static func resultFocusID(for settingID: String) -> String {
        "settings.result.\(settingID)"
    }

    enum Page: String, CaseIterable, Identifiable {
        case general, tabs, shortcuts, extensions, passwords, downloads, privacy, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return "General"
            case .tabs: return "Tabs"
            case .shortcuts: return "Shortcuts"
            case .extensions: return "Extensions"
            case .passwords: return "Passwords"
            case .downloads: return "Downloads"
            case .privacy: return "Privacy"
            case .about: return "About"
            }
        }
        var icon: String {
            switch self {
            case .general: return "macwindow"
            case .tabs: return "rectangle.split.3x1"
            case .shortcuts: return "keyboard"
            case .extensions: return "puzzlepiece.extension"
            case .passwords: return "key"
            case .downloads: return "arrow.down.circle"
            case .privacy: return "hand.raised"
            case .about: return "info.circle"
            }
        }

        /// Names of settings on each page, so a search can find the page that
        /// owns a setting without changing how the page itself is laid out.
        var searchTerms: String {
            switch self {
            case .general:
                return "default browser import bring things over bookmarks history passwords extensions search engine search with site shortcuts custom search theme appearance light dark mode system page zoom spelling autocorrect peek links address bar middle button scroll refresh rate video picture in picture script"
            case .tabs:
                return "tabs in a sidebar sidebar position hide the sidebar toolbar tabs show pins bookmarks bar reading progress sleep tabs background tabs spaces tab groups split view"
            case .shortcuts:
                return "keyboard keys commands hotkeys"
            case .extensions:
                return "add-ons permissions browser extensions"
            case .passwords:
                return "password keychain sign-in autofill offer to save fill in sign-ins import"
            case .downloads:
                return "save file location path ask where to save downloads button"
            case .privacy:
                return "block ads trackers tracking prevent cross-site tracking camera microphone location history cookies cache sign-ins permissions"
            case .about:
                return "version update install updates release notes what's new report bug support"
            }
        }

        func matches(_ query: String) -> Bool {
            let words = query.split(whereSeparator: \.isWhitespace)
            guard !words.isEmpty else { return true }
            let searchable = "\(title) \(searchTerms)"
            return words.allSatisfy { searchable.localizedCaseInsensitiveContains(String($0)) }
        }
    }

    private struct SettingTarget: Identifiable {
        let id: String
        let page: Page
        let title: String
        let terms: String

        func score(for query: String) -> Int? {
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return nil }
            let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
            let pageTitle = page.title
            let titleHas = { (value: String) in title.localizedCaseInsensitiveContains(value) }
            let searchText = "\(title) \(pageTitle) \(terms)"

            if title.caseInsensitiveCompare(query) == .orderedSame { return 0 }
            if title.range(of: query, options: [.anchored, .caseInsensitive]) != nil { return 1 }
            if titleHas(query) { return 2 }
            if words.allSatisfy(titleHas) { return 3 }
            if words.allSatisfy({ searchText.localizedCaseInsensitiveContains($0) }) { return 4 }
            return nil
        }

        static let all: [SettingTarget] = [
            .init(id: "general.default-browser", page: .general, title: "Open links from other apps", terms: "default browser make default external app"),
            .init(id: "general.import", page: .general, title: "Bring things over", terms: "import migrate bookmarks history passwords extensions browser"),
            .init(id: "general.search-engine", page: .general, title: "Search with", terms: "default search engine web search provider google duckduckgo bing custom url"),
            .init(id: "general.site-shortcuts", page: .general, title: "Site shortcuts", terms: "custom search keyword shortcuts sites search address"),
            .init(id: "general.appearance", page: .general, title: "Appearance", terms: "light dark system theme color"),
            .init(id: "general.zoom", page: .general, title: "Page zoom", terms: "scale percentage default 100% magnification"),
            .init(id: "general.spelling", page: .general, title: "Correct spelling as you type", terms: "spelling spell check autocorrect capitalization typing"),
            .init(id: "general.link-peek", page: .general, title: "Peek at a link with a shift-click", terms: "preview peek links shift click panel"),
            .init(id: "general.small-window", page: .general, title: "Open links from other apps in a small window", terms: "external links mini window open app"),
            .init(id: "general.address-commands", page: .general, title: "Address bar commands", terms: "command settings new tab address field url"),
            .init(id: "general.link-address", page: .general, title: "Show where links go", terms: "link address status bottom hover destination"),
            .init(id: "general.middle-scroll", page: .general, title: "Scroll with the middle button", terms: "mouse wheel autoscroll"),
            .init(id: "general.refresh-rate", page: .general, title: "Pages at 120 Hz", terms: "refresh rate 60 120 performance animation smooth"),
            .init(id: "general.swipe-history", page: .general, title: "Hold a swipe to pick from history", terms: "trackpad gesture back forward navigation"),
            .init(id: "general.video-flick", page: .general, title: "Flick the floating video to a corner", terms: "picture in picture pip move gesture"),
            .init(id: "general.video-click", page: .general, title: "Videos wait for a click", terms: "autoplay auto play video playback"),
            .init(id: "general.video-tabs", page: .general, title: "Float the video when you switch tabs", terms: "picture in picture pip tab change"),
            .init(id: "general.video-apps", page: .general, title: "Float the video when you switch apps", terms: "picture in picture pip app change"),
            .init(id: "general.script", page: .general, title: "Let a script drive Search", terms: "automation testing local socket bench"),
            .init(id: "tabs.navigation-left", page: .tabs, title: "Back, forward and reload on the left", terms: "toolbar navigation buttons location"),
            .init(id: "tabs.sidebar", page: .tabs, title: "Tabs in a sidebar", terms: "vertical tabs side column show hide"),
            .init(id: "tabs.sidebar-position", page: .tabs, title: "Sidebar position", terms: "left right side edge"),
            .init(id: "tabs.sidebar-hide", page: .tabs, title: "Hide the sidebar until the pointer reaches the edge", terms: "auto hide reveal show hidden"),
            .init(id: "tabs.glyph", page: .tabs, title: "Tabs show", terms: "tab titles icons favicon label appearance pins pinned square"),
            .init(id: "tabs.bookmarks-bar", page: .tabs, title: "Show the bookmarks bar", terms: "favorites toolbar bookmarks folders"),
            .init(id: "tabs.reading-progress", page: .tabs, title: "Show how far you've read", terms: "reading progress scroll position indicator"),
            .init(id: "tabs.sleep", page: .tabs, title: "Sleep tabs you aren't using", terms: "sleeping hibernate inactive memory"),
            .init(id: "tabs.lazy-load", page: .tabs, title: "Load background tabs when you go to them", terms: "lazy loading background inactive tabs"),
            .init(id: "tabs.spaces", page: .tabs, title: "Spaces", terms: "separate workspaces profiles groups of tabs"),
            .init(id: "tabs.groups", page: .tabs, title: "Tab groups", terms: "organize sections group tabs"),
            .init(id: "tabs.split-view", page: .tabs, title: "Split View", terms: "side by side two tabs split screen"),
            .init(id: "passwords.keychain", page: .passwords, title: "Your passwords", terms: "keychain manage password manager touch id"),
            .init(id: "passwords.save", page: .passwords, title: "Offer to save passwords", terms: "save password prompt remember"),
            .init(id: "passwords.fill", page: .passwords, title: "Fill in sign-ins", terms: "autofill login username accounts"),
            .init(id: "passwords.passkeys", page: .passwords, title: "Offer passkeys", terms: "passkey touch id icloud sign in"),
            .init(id: "passwords.never-ask", page: .passwords, title: "Sites never asked", terms: "password prompt refused forget allow again"),
            .init(id: "passwords.import", page: .passwords, title: "Bring yours in", terms: "import passwords another browser"),
            .init(id: "downloads.location", page: .downloads, title: "Save to", terms: "downloads folder location path directory"),
            .init(id: "downloads.ask", page: .downloads, title: "Ask where to save each file", terms: "download prompt choose destination"),
            .init(id: "downloads.button", page: .downloads, title: "Always show the downloads button", terms: "toolbar icon visible download"),
            .init(id: "privacy.blocking", page: .privacy, title: "Block ads and trackers", terms: "ad blocker tracking protection shield"),
            .init(id: "privacy.site-blocking", page: .privacy, title: "Block on this site", terms: "website host per site exception shield"),
            .init(id: "privacy.cross-site", page: .privacy, title: "Prevent cross-site tracking", terms: "third party cookies sign-ins privacy"),
            .init(id: "privacy.permissions", page: .privacy, title: "Camera, microphone and location", terms: "site permissions forget choices access"),
            .init(id: "privacy.history", page: .privacy, title: "History", terms: "browsing addresses clear recent"),
            .init(id: "privacy.cookies", page: .privacy, title: "Cookies and sign-ins", terms: "cookies sessions log out clear site data"),
            .init(id: "privacy.cache", page: .privacy, title: "Cache", terms: "cached files website data clear"),
            .init(id: "about.updates", page: .about, title: "Updates", terms: "version check for update available new release"),
            .init(id: "about.auto-updates", page: .about, title: "Install updates on its own", terms: "automatic update background"),
            .init(id: "about.feedback", page: .about, title: "Found something wrong?", terms: "feedback report bug issue"),
            .init(id: "about.release-notes", page: .about, title: "What's new", terms: "release notes changelog version"),
        ]
    }

    private static let rail: CGFloat = 168
    private static let width: CGFloat = 660
    private static let height: CGFloat = 500

    private var matchingPages: [Page] { Page.allCases.filter { $0.matches(pageSearch) } }
    private var matchingSettings: [SettingTarget] {
        var scored: [(setting: SettingTarget, score: Int, index: Int)] = []
        for (index, setting) in SettingTarget.all.enumerated() {
            if setting.id == "passwords.never-ask", Vault.never.isEmpty { continue }
            if setting.id == "privacy.site-blocking",
               browser.hereHost == nil || !prefs.shielded || shield.trouble != nil { continue }
            guard let score = setting.score(for: pageSearch) else { continue }
            scored.append((setting: setting, score: score, index: index))
        }
        scored.sort { lhs, rhs in
            lhs.score == rhs.score ? lhs.index < rhs.index : lhs.score < rhs.score
        }
        return scored.map(\.setting)
    }

    private func show(_ setting: SettingTarget) {
        page = setting.page
        highlightedSettingID = setting.id
    }

    private func moveMatch(by offset: Int, focusResultRow: Bool = false) {
        let matches = matchingSettings
        guard !matches.isEmpty else { return }
        let current = matches.firstIndex { $0.id == highlightedSettingID } ?? 0
        let next = min(max(current + offset, 0), matches.count - 1)
        let setting = matches[next]
        show(setting)
        if focusResultRow {
            focusedSettingsElement = Self.resultFocusID(for: setting.id)
        }
    }

    private func focusCurrentMatch() {
        guard let setting = matchingSettings.first(where: { $0.id == highlightedSettingID })
                ?? matchingSettings.first else {
            if let first = matchingPages.first { page = first }
            focusedSettingsElement = nil
            return
        }

        show(setting)
        DispatchQueue.main.async {
            focusedSettingsElement = setting.id
        }
    }

    private func updateSearch(_ query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            highlightedSettingID = nil
            return
        }
        if let first = matchingSettings.first {
            show(first)
        } else if let first = matchingPages.first {
            page = first
            highlightedSettingID = nil
        } else {
            highlightedSettingID = nil
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            pages
            Rectangle().fill(Palette.hairline).frame(width: 1)
            content
        }
        .frame(width: SettingsPanel.width, height: SettingsPanel.height)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 34, y: 12)
        .onChange(of: page) { _, page in Store.settings.set(page.rawValue, forKey: "settings.page") }
        .onChange(of: pageSearch) { _, query in updateSearch(query) }
    }

    // MARK: - the rail

    private var pages: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 8)
            pageSearchField
                .padding(.horizontal, 2)
                .padding(.bottom, 4)
            if pageSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ForEach(Page.allCases) { item in
                    PageRow(page: item, on: page == item) {
                        focusedSettingsElement = nil
                        page = item
                        highlightedSettingID = nil
                    }
                }
            } else if !matchingSettings.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 2) {
                            ForEach(matchingSettings) { setting in
                                let focusID = Self.resultFocusID(for: setting.id)
                                SettingResultRow(
                                    setting: setting,
                                    on: highlightedSettingID == setting.id
                                ) {
                                    show(setting)
                                    focusedSettingsElement = focusID
                                }
                                .id(setting.id)
                                .focusable()
                                .focused($focusedSettingsElement, equals: focusID)
                                .focusEffectDisabled()
                                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                                    guard focusedSettingsElement == focusID else { return .ignored }
                                    moveMatch(
                                        by: press.key == .downArrow ? 1 : -1,
                                        focusResultRow: true
                                    )
                                    return .handled
                                }
                                .onKeyPress(keys: [.return]) { _ in
                                    guard focusedSettingsElement == focusID else { return .ignored }
                                    focusCurrentMatch()
                                    return .handled
                                }
                            }
                        }
                    }
                    .onChange(of: highlightedSettingID) { _, id in
                        guard let id, matchingSettings.contains(where: { $0.id == id }) else { return }
                        withAnimation(Motion.quick) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            } else if !matchingPages.isEmpty {
                ForEach(matchingPages) { item in
                    PageRow(page: item, on: page == item) {
                        focusedSettingsElement = nil
                        page = item
                        highlightedSettingID = nil
                    }
                }
            } else {
                Text("No matching settings")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: SettingsPanel.rail, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.wash.opacity(0.45), in: Rectangle())
    }

    private var pageSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.muted)
            TextField("Search settings", text: $pageSearch)
                .font(.system(size: 12))
                .textFieldStyle(.plain)
                .focused($focusedSettingsElement, equals: Self.searchFieldFocusID)
                .accessibilityLabel("Search settings")
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                    guard !matchingSettings.isEmpty else { return .ignored }
                    moveMatch(by: press.key == .downArrow ? 1 : -1)
                    return .handled
                }
                .onSubmit(focusCurrentMatch)
            if !pageSearch.isEmpty {
                Button {
                    pageSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    /// Search results use the same idle, hover, and selected appearance as
    /// the settings page list.
    private struct RailRowAppearance: ViewModifier {
        let selected: Bool
        let hovering: Bool

        func body(content: Content) -> some View {
            content
                .foregroundStyle(selected ? Palette.ink : (hovering ? Palette.ink.opacity(0.75) : Palette.muted))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Palette.ground : (hovering ? Palette.hover : .clear))
                        .shadow(color: .black.opacity(selected ? 0.06 : 0), radius: 3, y: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private struct PageRow: View {
        let page: Page
        let on: Bool
        let act: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: act) {
                HStack(spacing: 9) {
                    Image(systemName: page.icon)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 16)
                    Text(page.title)
                        .font(.system(size: 13, weight: on ? .medium : .regular))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(on ? Palette.ink : (hovering ? Palette.ink.opacity(0.75) : Palette.muted))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(on ? Palette.ground : (hovering ? Palette.hover : .clear))
                        .shadow(color: .black.opacity(on ? 0.06 : 0), radius: 3, y: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
        }
    }

    private struct SettingResultRow: View {
        let setting: SettingTarget
        let on: Bool
        let act: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: act) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(setting.title)
                        .font(.system(size: 11.5, weight: on ? .medium : .regular))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(setting.page.title)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .modifier(RailRowAppearance(selected: on, hovering: hovering))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
        }
    }

    // MARK: - the page

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(page.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Door(icon: "xmark", help: "Done   esc") { browser.tuning = false }
            }
            .padding(.bottom, 16)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        switch page {
                        case .general: general
                        case .tabs:
                            tabs
                            if !prefs.sidebar || highlightedSettingID == "tabs.navigation-left" { toolbar }
                        case .shortcuts: ShortcutsPage(browser: browser, store: .shared)
                        case .extensions: ExtensionsPage(browser: browser)
                        case .passwords: passwords
                        case .downloads: downloads
                        case .privacy: privacy
                        case .about: about
                        }
                    }
                    .padding(.bottom, 4)
                }
                .onChange(of: highlightedSettingID) { _, id in
                    guard let id else { return }
                    highlightedSettingScroll?.cancel()
                    let scroll = DispatchWorkItem {
                        guard highlightedSettingID == id else { return }
                        withAnimation(Motion.glide) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                    highlightedSettingScroll = scroll
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: scroll)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(
            \.settingsControlFocus,
            SettingsControlFocus(id: nil, title: nil, focus: $focusedSettingsElement)
        )
        .simultaneousGesture(TapGesture().onEnded {
            focusedSettingsElement = nil
        })
    }

    // MARK: - general

    private var general: some View {
        Card {
            Line(
                "Open links from other apps",
                isDefault ? "Search is the default browser on this Mac" : "Mail, Slack and the rest still send links elsewhere",
                searchID: "general.default-browser",
                highlighted: highlightedSettingID == "general.default-browser"
            ) {
                if isDefault {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 24)
                } else {
                    Pill("Make default", filled: true) {
                        Links.becomeDefault { worked in
                            isDefault = Links.isDefault
                            browser.announce(worked && isDefault ? "Links now open here" : "macOS didn't change it")
                        }
                    }
                }
            }
            Rule()
            // Coming from another browser, now or any time later: the same
            // sheet as File › Bring Things Over… and the Welcome's.
            Line("Bring things over", "Bookmarks, history, passwords and extensions from another browser on this Mac, or from a file it exported", searchID: "general.import", highlighted: highlightedSettingID == "general.import") {
                Pill("Bring Things Over…") {
                    browser.tuning = false
                    browser.bringingIn = ""
                }
            }
            Rule()
            Line("Search with", searchDetail, searchID: "general.search-engine", highlighted: highlightedSettingID == "general.search-engine") {
                Picker("", selection: $prefs.engine) {
                    ForEach(Engine.allCases) { engine in
                        Text(engine.title).tag(engine)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .settingsControlFocusTarget()
            }
            if prefs.engine == .custom {
                ZStack(alignment: .leading) {
                    if prefs.customEngine.isEmpty {
                        Text("https://example.com/search?q=%s")
                            .foregroundStyle(Palette.muted.opacity(0.8))
                    }
                    TextField("", text: $prefs.customEngine)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Palette.ink)
                }
                .font(.system(size: 12.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(.horizontal, 14)
                .padding(.bottom, 11)
            }
            Rule()
            Line("Site shortcuts", keywordDetail, searchID: "general.site-shortcuts", highlighted: highlightedSettingID == "general.site-shortcuts") {
                if draft == nil {
                    Pill("Add") { draft = Keyword() }
                } else {
                    HStack(spacing: 6) {
                        Pill("Cancel") { draft = nil }
                        Pill("Save", filled: true, searchFocusTarget: false) { saveDraft() }
                            .disabled(draftProblem != nil)
                            .opacity(draftProblem == nil ? 1 : 0.4)
                    }
                }
            }
            if let current = draft {
                HStack(spacing: 8) {
                    TextField("yt", text: Binding(
                        get: { current.keyword },
                        set: { draft?.keyword = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .frame(width: 50)
                    Text("→").foregroundStyle(Palette.muted)
                    TextField("https://www.youtube.com/results?search_query=%s", text: Binding(
                        get: { current.template },
                        set: { draft?.template = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .onSubmit(saveDraft)
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }
            ForEach(prefs.keywords) { entry in
                HStack(spacing: 8) {
                    Text(entry.keyword)
                        .frame(width: 50, alignment: .leading)
                    Text("→").foregroundStyle(Palette.muted)
                    Text(entry.template)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        prefs.keywords.removeAll { $0.id == entry.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.faint)
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }
            Rule()
            Line("Appearance", "Light, dark, or whatever the Mac is doing — pages follow it too", searchID: "general.appearance", highlighted: highlightedSettingID == "general.appearance") {
                Segmented(options: Look.allCases.map { ($0, $0.title) }, selection: $prefs.look)
            }
            Rule()
            Line("Page zoom", "Where every site starts. ⌘+ and ⌘− are still remembered for each site.", searchID: "general.zoom", highlighted: highlightedSettingID == "general.zoom") {
                // The number itself takes it back to 100%.
                Steps(stops: Preferences.zooms, value: $prefs.pageZoom, home: 1) { "\(Int(($0 * 100).rounded()))%" }
            }
            Rule()
            Line("Correct spelling as you type", "macOS's autocorrect inside pages — the one that capitalises for you", searchID: "general.spelling", highlighted: highlightedSettingID == "general.spelling") {
                Switch(on: $prefs.autocorrect)
            }
            Rule()
            Line("Peek at a link with a shift-click", "Its page opens in a panel over the one you're reading. Escape puts it away; the other button keeps it as a tab", searchID: "general.link-peek", highlighted: highlightedSettingID == "general.link-peek") {
                Switch(on: $prefs.peeksLinks)
            }
            Rule()
            Line("Open links from other apps in a small window", "To read and close, or keep with Open in Search (⌘O)", searchID: "general.small-window", highlighted: highlightedSettingID == "general.small-window") {
                Switch(on: $prefs.littleLinks)
            }
            Rule()
            Line("Address bar commands", "A word like \"settings\" or \"new tab\", typed alone in the address field, goes there instead of searching for it", searchID: "general.address-commands", highlighted: highlightedSettingID == "general.address-commands") {
                Switch(on: $prefs.commandBar)
            }
            Rule()
            Line("Show where links go", "Point at a link and its address shows at the bottom of the page", searchID: "general.link-address", highlighted: highlightedSettingID == "general.link-address") {
                Switch(on: $prefs.showsLinks)
            }
            Rule()
            Line("Scroll with the middle button", "Click the wheel on a page, then move the mouse up or down to scroll, as on Windows. Click again to stop", searchID: "general.middle-scroll", highlighted: highlightedSettingID == "general.middle-scroll") {
                Switch(on: $prefs.autoScroll)
            }
            Rule()
            Line("Pages at 120 Hz", "Animations and scrolling in pages at up to 120 frames a second on a screen that can, instead of 60 as in Safari. Uses more battery. Open tabs follow when reloaded", searchID: "general.refresh-rate", highlighted: highlightedSettingID == "general.refresh-rate") {
                Switch(on: $prefs.fastPages)
            }
            Rule()
            Line("Hold a swipe to pick from history", "Swipe back or forward and keep your fingers down: the pages that way appear, and moving up or down picks one to go to", searchID: "general.swipe-history", highlighted: highlightedSettingID == "general.swipe-history") {
                Switch(on: $prefs.holdsHistory)
            }
            Rule()
            Line("Flick the floating video to a corner", "Two fingers on it send it to the corner or edge they point at, instead of pushing it along; a strong swipe at the side of the screen it is against tucks it in there, a sliver left to bring it back by. Dragging still puts it anywhere", searchID: "general.video-flick", highlighted: highlightedSettingID == "general.video-flick") {
                Switch(on: $prefs.floatFlicks)
            }
            Rule()
            Line("Videos wait for a click", "Videos don't start by themselves, even without sound; they play when you press play. Tabs already open follow once closed and opened again, or after they've slept", searchID: "general.video-click", highlighted: highlightedSettingID == "general.video-click") {
                Switch(on: $prefs.waitsForPlay)
            }
            Rule()
            Line("Float the video when you switch tabs", "A video playing on YouTube and the like comes out into its floating window when you go to another tab, and back when you return. ⇧⌘P still floats one by hand", searchID: "general.video-tabs", highlighted: highlightedSettingID == "general.video-tabs") {
                Switch(on: $prefs.floatsOnLeave)
            }
            Rule()
            Line("Float the video when you switch apps", "A video playing on the site you're on comes out into its floating window as another app comes to the front, and goes back into its tab when you return", searchID: "general.video-apps", highlighted: highlightedSettingID == "general.video-apps") {
                Switch(on: $prefs.floatsAway)
            }
            Rule()
            Line("Let a script drive Search", "A local socket for testing. Its tabs open beside yours with a flask on them and never take over — see ./bench", searchID: "general.script", highlighted: highlightedSettingID == "general.script") {
                Switch(on: $prefs.bench)
            }
        }
    }

    /// Checked when it's saved, not as it's typed into the list: a shortcut
    /// only exists once its address is one it's safe to send words to.
    private var draftProblem: String? {
        guard let draft else { return nil }
        return Keyword.problem(word: draft.keyword, template: draft.template, among: prefs.keywords)
    }

    private var keywordDetail: String {
        guard let draft else {
            return "A word before your search goes straight to that site, whatever engine you've picked — \"yt cats\" to YouTube"
        }
        if draft.keyword.isEmpty, draft.template.isEmpty {
            return "A word, then the site's search address with %s where the words go"
        }
        return draftProblem ?? "\(draft.keyword.trimmingCharacters(in: .whitespacesAndNewlines)) will search \(draft.name)"
    }

    private func saveDraft() {
        guard let current = draft, draftProblem == nil else { return }
        prefs.keywords.append(Keyword(
            keyword: current.keyword.trimmingCharacters(in: .whitespacesAndNewlines),
            template: current.template.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        draft = nil
    }

    private var searchDetail: String {
        guard prefs.engine == .custom else { return "Where words that aren't an address go" }
        guard Engine.accepts(prefs.customEngine) else {
            return "An http or https address with %s where the words go. Until then, Google"
        }
        return "Words go to \(prefs.engine.name(custom: prefs.customEngine))"
    }

    // MARK: - tabs

    /// Where back, forward and reload sit with the tabs across the top. With
    /// the sidebar they are already beside the window's buttons: nothing to
    /// move, and the line isn't shown.
    private var toolbar: some View {
        Card {
            Line("Back, forward and reload on the left", "Beside the window's buttons, before the tabs", searchID: "tabs.navigation-left", highlighted: highlightedSettingID == "tabs.navigation-left") {
                Switch(on: $prefs.navigationLeft)
            }
        }
    }

    private var tabs: some View {
        Card {
            Line("Tabs in a sidebar", "Down the \(prefs.sidePosition.rawValue) instead of across the top. Pull its edge to make it wider; double-click the edge to reset.", searchID: "tabs.sidebar", highlighted: highlightedSettingID == "tabs.sidebar") {
                Switch(on: Binding(
                    get: { prefs.sidebar },
                    set: { on in withAnimation(Motion.glide) { prefs.sidebar = on } }
                ))
            }
            if prefs.sidebar || ["tabs.sidebar-position", "tabs.sidebar-hide"].contains(highlightedSettingID ?? "") {
                Rule()
                Line("Sidebar position", "Tabs down the \(prefs.sidePosition.rawValue) edge of the window", searchID: "tabs.sidebar-position", highlighted: highlightedSettingID == "tabs.sidebar-position") {
                    Segmented(options: SidebarPosition.allCases.map { ($0, $0.title) }, selection: $prefs.sidePosition)
                }
                Rule()
                Line("Hide the sidebar until the pointer reaches the edge", "The page takes the whole window; push against its \(prefs.sidePosition.rawValue) edge for the tabs. ⌘S keeps them out.", searchID: "tabs.sidebar-hide", highlighted: highlightedSettingID == "tabs.sidebar-hide") {
                    Switch(on: $prefs.sideHides)
                }
            }
            Rule()
            Line("Tabs show", "Beside the title, and on a pinned square", searchID: "tabs.glyph", highlighted: highlightedSettingID == "tabs.glyph") {
                Segmented(options: Glyph.allCases.map { ($0, $0.title) }, selection: $prefs.glyph)
            }
            Rule()
            Line("Show the bookmarks bar", "Your bookmarks in a row above the page, folders opening as menus. It folds away with the tabs", searchID: "tabs.bookmarks-bar", highlighted: highlightedSettingID == "tabs.bookmarks-bar") {
                Switch(on: $prefs.bookmarksBar)
            }
            Rule()
            Line("Show how far you've read", "The tab you're on fills with grey as you scroll down the page", searchID: "tabs.reading-progress", highlighted: highlightedSettingID == "tabs.reading-progress") {
                Switch(on: $prefs.showsReading)
            }
            Rule()
            Line("Sleep tabs you aren't using", "After half an hour away they come back where you left them. Pinned tabs, sound, calls and anything typed stay awake.", searchID: "tabs.sleep", highlighted: highlightedSettingID == "tabs.sleep") {
                Switch(on: $prefs.sleepsTabs)
            }
            Rule()
            Line("Load background tabs when you go to them", "A link opened behind the page, with ⌘-click or the middle button, or a batch of links from another app, waits until you go to its tab. ⇧⌘-click still takes you there at once.", searchID: "tabs.lazy-load", highlighted: highlightedSettingID == "tabs.lazy-load") {
                Switch(on: $prefs.lazyTabs)
            }
            Rule()
            Line("Spaces", "Separate sets of tabs, signed in where the others are or starting afresh, switched with ⌃1–⌃9, two fingers sideways over the column, or the space's icon. Mission Control's own ⌃1–⌃9, if you turned them on, take those keys first.", searchID: "tabs.spaces", highlighted: highlightedSettingID == "tabs.spaces") {
                Switch(on: $prefs.usesSpaces)
            }
            Rule()
            Line("Tab groups", "Named sections in the sidebar. Right-click a tab to start a group; click its heading to hide or show its tabs.", searchID: "tabs.groups", highlighted: highlightedSettingID == "tabs.groups") {
                Switch(on: $prefs.usesTabGroups)
            }
            Rule()
            Line("Split View", "Show two tabs side by side. Drag a tab onto a page to pair them.", searchID: "tabs.split-view", highlighted: highlightedSettingID == "tabs.split-view") {
                Switch(on: $prefs.splitView)
            }
        }
    }

    // MARK: - passwords

    /// Says so when a password manager extension has taken the saving over.
    private var savingDetail: String {
        if #available(macOS 15.4, *), let name = Extensions.shared.passwordSavingTakenBy {
            return "\(name) does the saving — it asked Search not to offer"
        }
        return "Asked once per site, never again for a site you refuse"
    }

    private var passwords: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                Line("Your passwords", "In the macOS keychain, shown with Touch ID", searchID: "passwords.keychain", highlighted: highlightedSettingID == "passwords.keychain") {
                    Pill("Open…") {
                        browser.tuning = false
                        browser.managing = true
                    }
                }
                Rule()
                Line("Offer to save passwords", savingDetail, searchID: "passwords.save", highlighted: highlightedSettingID == "passwords.save") {
                    Switch(on: $prefs.savesPasswords)
                }
                Rule()
                Line("Fill in sign-ins", "Click a sign-in box and the accounts kept for the site hang from it", searchID: "passwords.fill", highlighted: highlightedSettingID == "passwords.fill") {
                    Switch(on: $prefs.fillsPasswords)
                }
                Rule()
                Line(
                    "Offer passkeys",
                    !prefs.passkeysPossible
                        ? "Needs an Apple entitlement this build doesn't have — off keeps sites to the password"
                        : Passkeys.access == .denied
                        ? "macOS was told no — System Settings › Privacy & Security › Passkeys Access for Web Browsers"
                        : "Touch ID or an iCloud passkey, on sites that offer one",
                    searchID: "passwords.passkeys",
                    highlighted: highlightedSettingID == "passwords.passkeys"
                ) {
                    Switch(on: $prefs.passkeys)
                }
                if !Vault.never.isEmpty {
                    Rule()
                    Line("Sites never asked", "\(Vault.never.count) sites told to stop offering", searchID: "passwords.never-ask", highlighted: highlightedSettingID == "passwords.never-ask") {
                        Pill("Forget") {
                            Vault.never = []
                            browser.announce("Every site can ask again")
                        }
                    }
                }
            }
            Card {
                Line("Bring yours in", "From another browser on this Mac — nothing leaves it", searchID: "passwords.import", highlighted: highlightedSettingID == "passwords.import") {
                    Pill("Import…") {
                        browser.tuning = false
                        browser.bringingIn = ""
                    }
                }
            }
        }
    }

    // MARK: - downloads

    private var downloads: some View {
        Card {
            Line("Save to", prefs.downloads.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), searchID: "downloads.location", highlighted: highlightedSettingID == "downloads.location") {
                Pill("Change…") { chooseFolder() }
            }
            Rule()
            Line("Ask where to save each file", searchID: "downloads.ask", highlighted: highlightedSettingID == "downloads.ask") {
                Switch(on: $prefs.asksWhereToSave)
            }
            Rule()
            Line("Always show the downloads button", "Beside the other buttons, even with nothing downloading. Off, it shows only while a file comes in", searchID: "downloads.button", highlighted: highlightedSettingID == "downloads.button") {
                Switch(on: $prefs.alwaysShowsDownloads)
            }
        }
    }

    // MARK: - privacy

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                Line("Block ads and trackers", shield.trouble ?? "Third parties whose only job is to watch", searchID: "privacy.blocking", highlighted: highlightedSettingID == "privacy.blocking") {
                    Switch(on: $prefs.shielded)
                }
                if let trouble = shield.trouble {
                    Rule()
                    Line(trouble, "Nothing is being blocked until this clears — try again, or restart Search") {
                        Pill("Try again") { shield.compile() }
                    }
                }
                if let host = browser.hereHost, prefs.shielded, shield.trouble == nil {
                    Rule()
                    Line("Block on \(host)", "Turn off here if the site breaks — the page reloads", searchID: "privacy.site-blocking", highlighted: highlightedSettingID == "privacy.site-blocking") {
                        Switch(on: Binding(
                            get: { !Shield.shared.isPaused(on: host) },
                            set: { on in
                                Shield.shared.pause(host, !on)
                                browser.reload()
                            }
                        ))
                    }
                }
                Rule()
                Line("Prevent cross-site tracking", "As in Safari. Off, sites you rarely open keep their sign-ins, and trackers inside other sites can follow you across them again, as in Chrome. Private tabs keep it on", searchID: "privacy.cross-site", highlighted: highlightedSettingID == "privacy.cross-site") {
                    Switch(on: Binding(get: { !prefs.keepsSignIns }, set: { prefs.keepsSignIns = !$0 }))
                }
                Rule()
                Line("Camera, microphone and location", "What each site was allowed or refused", searchID: "privacy.permissions", highlighted: highlightedSettingID == "privacy.permissions") {
                    Pill("Forget choices") { browser.forgetCaptureChoices() }
                }
            }
            Card {
                Line("History", "Every address you have been to", searchID: "privacy.history", highlighted: highlightedSettingID == "privacy.history") {
                    Pill("Clear") { browser.clearHistory() }
                }
                Rule()
                Line("Cookies and sign-ins", "Signs you out of every site", searchID: "privacy.cookies", highlighted: highlightedSettingID == "privacy.cookies") {
                    Pill("Sign out of everything") { browser.clearSites() }
                }
                Rule()
                Line("Cache", "Only what was fetched to draw pages", searchID: "privacy.cache", highlighted: highlightedSettingID == "privacy.cache") {
                    Pill("Clear") { browser.clearCache() }
                }
            }
        }
    }

    // MARK: - about

    private var about: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Logomark()
                    .fill(Palette.ink, style: FillStyle(eoFill: true))
                    .aspectRatio(Logomark.canvas.width / Logomark.canvas.height, contentMode: .fit)
                    .frame(height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Search")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text("by Office Commun · version \(Updater.version)")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(.bottom, 2)

            Card {
                Line(versionTitle, versionDetail, searchID: "about.updates", highlighted: highlightedSettingID == "about.updates") { versionControl }
                Rule()
                Line("Install updates on its own", "Off, Search still looks every hour and tells you, and installs only when you press Install", searchID: "about.auto-updates", highlighted: highlightedSettingID == "about.auto-updates") {
                    Switch(on: $prefs.installsUpdates)
                }
                Rule()
                Line("Found something wrong?", "Opens a draft with the version already in it", searchID: "about.feedback", highlighted: highlightedSettingID == "about.feedback") {
                    Pill("Send Feedback") { Links.writeFeedback() }
                }
                Rule()
                Line("What's new", "Every version's notes, newest first", searchID: "about.release-notes", highlighted: highlightedSettingID == "about.release-notes") {
                    Pill("What's New…") { browser.notesShowing = true }
                }
            }

            Card {
                Shortcut("⌘L", "Address")
                Rule()
                Shortcut("⌘K", "Switch tab")
                Rule()
                Shortcut("⌘T  ⌘W  ⇧⌘T", "New, close, reopen tab")
                Rule()
                Shortcut("⇧⌘V", "Paste and go")
                Rule()
                Shortcut("⇧⌘C", "Copy address")
                Rule()
                Shortcut("⌃⇥  ⌘1–9", "Next tab, a tab by its place")
                Rule()
                Shortcut("⇧⌘S", "Tabs in a sidebar")
                Rule()
                Shortcut("⌘S", "Fold the sidebar away")
                Rule()
                Shortcut("⇧⌘R", "Reading mode")
                Rule()
                Shortcut("⇧⌘H", "Hide something on this site")
                Rule()
                Shortcut("⇧⌘P", "Float the video")
                Rule()
                Shortcut("⇧⌘⌫", "Clear browsing data")
            }
        }
    }

    /// The version line follows the newer build from found to fetched to
    /// in place; with none, it is simply this one.
    private var versionTitle: String {
        switch updater.stage {
        case .none: return "Updates"
        case .fetching(let next): return "Search \(next.version) is downloading…"
        case .ready(let next): return "Search \(next.version) is ready"
        case .offered(let next), .waiting(let next): return "Search \(next.version) is out"
        }
    }

    private var versionDetail: String {
        switch updater.stage {
        case .none:
            return updater.lastChecked.map { "Checked \($0.formatted(.relative(presentation: .named))) — every hour on its own" }
                ?? "Checked every hour on its own"
        case .fetching(let next):
            return next.notes ?? "Quietly, in the background — nothing you have set is touched"
        case .ready(let next):
            return next.notes ?? "It's there the next time you open Search"
        case .offered(let next):
            return next.notes ?? "Open the disk image, the same as the first time"
        case .waiting(let next):
            return next.notes ?? "Checked and put in place when you press Install"
        }
    }

    @ViewBuilder
    private var versionControl: some View {
        switch updater.stage {
        case .none:
            Pill(updater.checking ? "Checking…" : "Check now") {
                updater.check { found in
                    if found == nil { browser.announce("This is the latest one") }
                }
            }
            .disabled(updater.checking)
        case .fetching:
            Ring(size: 12)
        case .ready:
            Pill("Relaunch now", filled: true) { updater.relaunch() }
        case .offered:
            Pill(updater.fetchingDisk ? "Downloading…" : "Download", filled: true) { updater.openDisk() }
                .disabled(updater.fetchingDisk)
        case .waiting:
            Pill("Install", filled: true) { updater.install() }
        }
    }

    // MARK: - doing

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = prefs.downloads
        panel.prompt = "Use this folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        prefs.downloads = url
    }

    // MARK: - pieces

    /// A keystroke and what it does.
    private struct Shortcut: View {
        let keys: String
        let does: String
        init(_ keys: String, _ does: String) { self.keys = keys; self.does = does }

        var body: some View {
            HStack {
                Text(does)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(keys)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }
}

/// A row of choices in a grey track, one of them lifted out in white. The
/// white slides to the one you pick rather than appearing there.
struct Segmented<Option: Hashable>: View {
    let options: [(Option, String)]
    @Binding var selection: Option
    /// True when the control has the whole width to itself, so the choices
    /// share it evenly instead of each taking only what its word needs.
    var wide = false

    @Namespace private var slide

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { option, title in
                optionButton(option, title: title)
            }
        }
        .padding(2)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .animation(Motion.settle, value: selection)
    }

    private func optionButton(_ option: Option, title: String) -> some View {
        Button {
            withAnimation(Motion.settle) { selection = option }
        } label: {
            Text(title)
                .font(.system(size: 11.5, weight: option == selection ? .medium : .regular))
                .foregroundStyle(option == selection ? Palette.ink : Palette.muted)
                .lineLimit(1)
                .fixedSize(horizontal: !wide, vertical: false)
                .frame(maxWidth: wide ? .infinity : nil)
                .padding(.horizontal, wide ? 4 : 10)
                .padding(.vertical, 5)
                .background {
                    if option == selection {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Palette.ground)
                            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                            .matchedGeometryEffect(id: "chosen", in: slide)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(option == selection ? "Selected" : "")
        .settingsControlFocusTarget(option == selection)
    }
}

/// On or off, in ink rather than in blue.
struct Switch: View {
    @Binding var on: Bool
    @Environment(\.settingsControlFocus) private var settingsFocus

    var body: some View {
        Button {
            withAnimation(Motion.settle) { on.toggle() }
        } label: {
            Capsule()
                .fill(on ? Palette.ink : Palette.faint)
                .frame(width: 30, height: 18)
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle()
                        .fill(Palette.ground)
                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                        .padding(2)
                }
                .contentShape(Capsule())
                .animation(Motion.settle, value: on)
        }
        .buttonStyle(.plain)
        .settingsControlFocusTarget()
        .accessibilityLabel(settingsFocus.title ?? "Setting")
        .accessibilityValue(on ? "On" : "Off")
    }
}

/// A value moved one stop at a time: − and + either side of it, in the same
/// outlined capsule as a pill. Pressing the value itself takes it home.
struct Steps: View {
    let stops: [Double]
    @Binding var value: Double
    let home: Double
    let label: (Double) -> String

    /// The nearest stop either way — a value between stops, from before
    /// there were stops, still moves to a round one.
    private var below: Double? { stops.last { $0 < value - 0.001 } }
    private var above: Double? { stops.first { $0 > value + 0.001 } }

    var body: some View {
        HStack(spacing: 0) {
            Step(icon: "minus", to: below, focusTarget: above == nil && below != nil) { value = $0 }
            Button { value = home } label: {
                Text(label(value))
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .frame(minWidth: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to \(label(home))")
            .settingsControlFocusTarget(above == nil && below == nil)
            Step(icon: "plus", to: above, focusTarget: above != nil) { value = $0 }
        }
        .padding(.horizontal, 2)
        .frame(height: 24)
        .background(Palette.ground, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
    }

    private struct Step: View {
        let icon: String
        let to: Double?
        var focusTarget = false
        let act: (Double) -> Void
        @State private var hovering = false

        var body: some View {
            Button { if let to { act(to) } } label: {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(to == nil ? Palette.faint : Palette.ink)
                    .frame(width: 20, height: 20)
                    .background(hovering && to != nil ? Palette.hover : .clear, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(to == nil)
            .settingsControlFocusTarget(focusTarget)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
        }
    }
}

/// A small capsule that does one thing. Outlined by default; filled in ink
/// when it is the thing you came here to press.
struct Pill: View {
    let title: String
    var filled = false
    var tint: Color = Palette.ink
    var searchFocusTarget = true
    let action: () -> Void

    @State private var hovering = false

    init(
        _ title: String,
        filled: Bool = false,
        tint: Color = Palette.ink,
        searchFocusTarget: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.filled = filled
        self.tint = tint
        self.searchFocusTarget = searchFocusTarget
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(filled ? Palette.ground : tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(filled ? Palette.ink : (hovering ? Palette.hover : Palette.ground), in: Capsule())
                .overlay(Capsule().strokeBorder(filled ? .clear : Palette.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .settingsControlFocusTarget(searchFocusTarget)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }
}
