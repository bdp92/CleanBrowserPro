import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var browser: BrowserModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            Form {
                Section("Safari-achtige bediening") {
                    Picker("Adresbalk", selection: Binding(
                        get: { settings.addressBarPosition },
                        set: { settings.addressBarPosition = $0 }
                    )) {
                        ForEach(AddressBarPosition.allCases) { position in
                            Text(position.rawValue).tag(position)
                        }
                    }

                    Picker("Zoekmachine", selection: Binding(
                        get: { settings.searchEngine },
                        set: { settings.searchEngine = $0 }
                    )) {
                        ForEach(SearchEngine.allCases) { engine in
                            Text(engine.rawValue).tag(engine)
                        }
                    }

                    TextField("Startpagina", text: $settings.homePage)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                Section("Weergave") {
                    Picker("Thema", selection: Binding(
                        get: { settings.theme },
                        set: { settings.theme = $0 }
                    )) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Tekstgrootte")
                            Spacer()
                            Text("\(Int(settings.textScale * 100))%")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.textScale, in: 0.75...1.5, step: 0.05)
                    }

                    Toggle("Desktopwebsite", isOn: Binding(
                        get: { settings.desktopMode },
                        set: {
                            settings.desktopMode = $0
                            browser.rebuildForPrivacySettings()
                        }
                    ))
                }

                Section("Privacy & beveiliging") {
                    Toggle("Wis sessie bij verlaten", isOn: $settings.clearOnBackground)

                    Toggle("Strenge trackerblokkering", isOn: Binding(
                        get: { settings.strictBlocking },
                        set: {
                            settings.strictBlocking = $0
                            browser.rebuildForPrivacySettings()
                        }
                    ))

                    Toggle("HTTPS-only", isOn: $settings.httpsOnly)

                    Toggle("Blokkeer pop-ups", isOn: $settings.blockPopups)

                    Toggle("JavaScript", isOn: Binding(
                        get: { settings.javaScriptEnabled },
                        set: {
                            settings.javaScriptEnabled = $0
                            browser.rebuildForPrivacySettings()
                        }
                    ))

                    Text("JavaScript uitschakelen geeft extra privacy, maar veel websites werken dan niet volledig.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Vertalen") {
                    Picker("Standaardtaal", selection: $settings.targetLanguage) {
                        Text("Nederlands").tag("nl")
                        Text("Engels").tag("en")
                        Text("Frans").tag("fr")
                        Text("Duits").tag("de")
                        Text("Spaans").tag("es")
                        Text("Italiaans").tag("it")
                        Text("Portugees").tag("pt")
                        Text("Pools").tag("pl")
                        Text("Turks").tag("tr")
                        Text("Oekraïens").tag("uk")
                    }
                }

                Section("Privacy-uitleg") {
                    Label("Niet-persistente WebKit-opslag", systemImage: "memorychip")
                    Label("Geen eigen browsegeschiedenis", systemImage: "clock.badge.xmark")
                    Label("Third-party cookies blokkeren", systemImage: "nosign")
                    Label("Advertentie- en trackerdomeinen blokkeren", systemImage: "hand.raised.fill")
                    Label("Lokale favorieten zijn optioneel", systemImage: "star")
                }

                Section {
                    Button(role: .destructive) {
                        browser.clearNow()
                    } label: {
                        Text("Wis alle huidige tabs en sessiegegevens")
                    }
                } footer: {
                    Text("Favorieten worden niet verwijderd wanneer je de privésessie wist.")
                }
            }
            .navigationTitle("Instellingen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gereed") { dismiss() }
                }
            }
        }
    }
}
