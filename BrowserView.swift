import SwiftUI
import Translation

struct BrowserView: View {
    @EnvironmentObject private var browser: BrowserModel
    @StateObject private var settings = AppSettings.shared
    @StateObject private var bookmarks = BookmarkStore.shared

    @FocusState private var addressFocused: Bool
    @State private var showingSettings = false
    @State private var showingTabs = false
    @State private var showingBookmarks = false
    @State private var showingLanguagePicker = false
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var pendingSegments: [PageSegment] = []
    @State private var isTranslating = false
    @State private var translationMessage: String?

    private let languages: [(String, String)] = [
        ("nl", "Nederlands"), ("en", "Engels"), ("fr", "Frans"),
        ("de", "Duits"), ("es", "Spaans"), ("it", "Italiaans"),
        ("pt", "Portugees"), ("pl", "Pools"), ("tr", "Turks"),
        ("uk", "Oekraïens")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                privacyHeader

                if settings.addressBarPosition == .top {
                    addressBar
                }

                if browser.isLoading {
                    ProgressView().progressViewStyle(.linear)
                }

                BrowserWebView(browser: browser)
                    .id(browser.selectedTabID)

                if settings.addressBarPosition == .bottom {
                    addressBar
                }

                navigationBar
            }
            .navigationBarHidden(true)
            .preferredColorScheme(settings.theme.colorScheme)
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(browser)
                    .environmentObject(settings)
            }
            .sheet(isPresented: $showingTabs) {
                TabsView()
                    .environmentObject(browser)
            }
            .sheet(isPresented: $showingBookmarks) {
                BookmarksView()
                    .environmentObject(browser)
                    .environmentObject(bookmarks)
            }
            .sheet(isPresented: $showingLanguagePicker) {
                languagePicker
            }
            .alert("Clean Browser Pro", isPresented: Binding(
                get: { browser.lastError != nil || translationMessage != nil },
                set: { value in
                    if !value {
                        browser.lastError = nil
                        translationMessage = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) {
                    browser.lastError = nil
                    translationMessage = nil
                }
            } message: {
                Text(browser.lastError ?? translationMessage ?? "")
            }
            .translationTask(translationConfiguration) { session in
                await translatePendingSegments(using: session)
            }
        }
    }

    private var privacyHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.green)

            Text(browser.shieldStatus)
                .font(.caption)

            Spacer()

            Button {
                browser.addCurrentBookmark()
            } label: {
                Image(systemName: "star")
            }
            .accessibilityLabel("Voeg favoriet toe")

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Instellingen")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private var addressBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Zoeken of website", text: $browser.address)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .focused($addressFocused)
                .onSubmit {
                    browser.load(browser.address)
                    addressFocused = false
                }

            Button {
                browser.isLoading ? browser.stop() : browser.reload()
            } label: {
                Image(systemName: browser.isLoading ? "xmark" : "arrow.clockwise")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private var navigationBar: some View {
        HStack {
            Button { browser.goBack() } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!browser.canGoBack)

            Spacer()

            Button { browser.goForward() } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!browser.canGoForward)

            Spacer()

            Button { showingLanguagePicker = true } label: {
                if isTranslating { ProgressView() }
                else { Image(systemName: "character.bubble") }
            }
            .disabled(isTranslating)

            Spacer()

            Button { showingBookmarks = true } label: {
                Image(systemName: "book")
            }

            Spacer()

            Button { showingTabs = true } label: {
                ZStack {
                    Image(systemName: "square.on.square")
                    Text("\(browser.tabs.count)")
                        .font(.system(size: 8, weight: .bold))
                        .offset(y: -1)
                }
            }

            Spacer()

            Button(role: .destructive) { browser.clearNow() } label: {
                Image(systemName: "flame.fill")
            }
        }
        .font(.title3)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(.bar)
    }

    private var languagePicker: some View {
        NavigationStack {
            List(languages, id: \.0) { code, name in
                Button {
                    settings.targetLanguage = code
                    showingLanguagePicker = false
                    startTranslation()
                } label: {
                    HStack {
                        Text(name)
                        Spacer()
                        if code == settings.targetLanguage {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            .navigationTitle("Vertaal pagina naar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") { showingLanguagePicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func startTranslation() {
        Task {
            do {
                isTranslating = true
                let segments = try await browser.capturePageSegments()
                guard !segments.isEmpty else {
                    isTranslating = false
                    translationMessage = "Ik vond geen zichtbare tekst om te vertalen."
                    return
                }

                pendingSegments = segments
                translationConfiguration = TranslationSession.Configuration(
                    source: nil,
                    target: Locale.Language(identifier: settings.targetLanguage)
                )
            } catch {
                isTranslating = false
                translationMessage = "Vertalen kon niet starten: \(error.localizedDescription)"
            }
        }
    }

    private func translatePendingSegments(using session: TranslationSession) async {
        guard !pendingSegments.isEmpty else { return }

        do {
            let requests = pendingSegments.map {
                TranslationSession.Request(
                    sourceText: $0.text,
                    clientIdentifier: String($0.id)
                )
            }

            let responses = try await session.translations(from: requests)
            var translated: [Int: String] = [:]

            for response in responses {
                if let identifier = response.clientIdentifier,
                   let id = Int(identifier) {
                    translated[id] = response.targetText
                }
            }

            try await browser.applyTranslations(translated)
            pendingSegments = []
            isTranslating = false
        } catch {
            pendingSegments = []
            isTranslating = false
            translationMessage = "Vertalen is mislukt: \(error.localizedDescription)"
        }
    }
}

struct TabsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(browser.tabs) { tab in
                    Button {
                        browser.selectTab(tab.id)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tab.title.isEmpty ? "Nieuwe tab" : tab.title)
                                    .lineLimit(1)
                                Text(tab.urlString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if tab.id == browser.selectedTabID {
                                Image(systemName: "checkmark.circle.fill")
                            }

                            Button(role: .destructive) {
                                browser.closeTab(tab.id)
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .navigationTitle("Tabbladen")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Gereed") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        browser.newTab()
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

struct BookmarksView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var browser: BrowserModel
    @EnvironmentObject private var bookmarks: BookmarkStore

    var body: some View {
        NavigationStack {
            List {
                if bookmarks.items.isEmpty {
                    ContentUnavailableView(
                        "Geen favorieten",
                        systemImage: "star",
                        description: Text("Tik op de ster om een pagina lokaal als favoriet te bewaren.")
                    )
                } else {
                    ForEach(bookmarks.items) { item in
                        Button {
                            browser.load(item.url)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).lineLimit(1)
                                Text(item.url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .onDelete(perform: bookmarks.remove)
                }
            }
            .navigationTitle("Favorieten")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gereed") { dismiss() }
                }
            }
        }
    }
}
