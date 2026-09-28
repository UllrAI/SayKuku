import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct DictationAppIdentity: Identifiable {
    let bundleID: String
    let name: String
    let url: URL?

    var id: String { bundleID }

    init(bundleID: String, url: URL?) {
        self.bundleID = bundleID
        self.url = url
        let bundle = url.flatMap(Bundle.init(url:))
        name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? bundleID
    }

    var icon: NSImage {
        url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .application)
    }
}

struct DictationAppFormatsSettings: View {
    @Environment(AppState.self) private var appState
    @State private var editingApp: DictationAppIdentity?

    private var runningApps: [DictationAppIdentity] {
        let ownID = Bundle.main.bundleIdentifier
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> DictationAppIdentity? in
            guard app.activationPolicy == .regular,
                  let id = app.bundleIdentifier, id != ownID,
                  let url = app.bundleURL else { return nil }
            return DictationAppIdentity(bundleID: id, url: url)
        }
        return Dictionary(apps.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
            .values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        KukuGroup(localized("App-specific formatting")) {
            Text(localized("Items not set for an app follow the global settings above."))
                .font(.kuku(.subheadline))
                .foregroundStyle(KukuColor.textSecondary)
                .kukuRowFrame()

            ForEach(appState.settings.dictationAppFormats) { rule in
                let app = DictationAppIdentity(
                    bundleID: rule.bundleID,
                    url: NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleID)
                )
                KukuDivider()
                KukuRow(app.name, caption: summary(for: rule)) {
                    Image(nsImage: app.icon).resizable().frame(width: 24, height: 24)
                    Button(localized("Edit…")) { editingApp = app }
                        .buttonStyle(.kukuSecondary)
                }
            }

            KukuDivider()
            KukuRow(appState.settings.dictationAppFormats.isEmpty
                    ? localized("No app rules yet") : localized("Add another app")) {
                Menu {
                    ForEach(runningApps) { app in
                        Button {
                            editingApp = app
                        } label: {
                            Label { Text(app.name) } icon: { Image(nsImage: app.icon) }
                        }
                    }
                    Divider()
                    Button(localized("Choose Application…")) { chooseApplication() }
                } label: {
                    Text(localized("Add App…"))
                }
                .buttonStyle(.kukuSecondary)
            }
        }
        .sheet(item: $editingApp) { app in
            DictationAppFormatEditor(app: app, settings: appState.settings)
        }
    }

    private func summary(for rule: DictationAppFormat) -> String {
        var items: [String] = []
        if let value = rule.keepEndingPunctuation {
            items.append("\(localized("Keep ending punctuation")): \(value ? localized("On") : localized("Off"))")
        }
        if let value = rule.cleanup { items.append("\(localized("Speech cleanup")): \(value.title)") }
        if let value = rule.numberFormat { items.append("\(localized("Number format")): \(value.title)") }
        if let value = rule.matchAppTone {
            items.append("\(localized("Match the app’s tone")): \(value ? localized("On") : localized("Off"))")
        }
        if !rule.expressionPreference.isEmpty { items.append(localized("Expression preference")) }
        return items.joined(separator: localized(", "))
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsOtherFileTypes = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier,
              id != Bundle.main.bundleIdentifier else { return }
        editingApp = DictationAppIdentity(bundleID: id, url: url)
    }
}

private struct DictationAppFormatEditor: View {
    @Environment(\.dismiss) private var dismiss
    let app: DictationAppIdentity
    let settings: AppSettings
    @State private var draft: DictationAppFormat

    init(app: DictationAppIdentity, settings: AppSettings) {
        self.app = app
        self.settings = settings
        _draft = State(initialValue: settings.dictationAppFormats.first { $0.bundleID == app.bundleID }
            ?? DictationAppFormat(bundleID: app.bundleID))
    }

    private var effectiveCleanup: DictationCleanup { draft.cleanup ?? settings.dictationCleanup }

    var body: some View {
        VStack(alignment: .leading, spacing: KukuSpacing.lg) {
            HStack(spacing: KukuSpacing.md) {
                Image(nsImage: app.icon).resizable().frame(width: 32, height: 32)
                Text(app.name).font(.kuku(.title))
            }
            .padding(.horizontal, KukuLayout.sheetPadding)
            .padding(.top, KukuLayout.sheetPadding)

            ScrollView {
                VStack(alignment: .leading, spacing: KukuSpacing.lg) {
                    KukuGroup(localized("Formatting")) {
                        choiceRow(localized("Keep ending punctuation"), selection: $draft.keepEndingPunctuation,
                                  global: settings.keepEndingPunctuation, values: [true, false]) { booleanTitle($0) }
                        KukuDivider()
                        choiceRow(localized("Speech cleanup"), selection: $draft.cleanup,
                                  global: settings.dictationCleanup, values: DictationCleanup.allCases) { $0.title }
                        KukuDivider()
                        choiceRow(localized("Number format"), selection: $draft.numberFormat,
                                  global: settings.dictationNumberFormat, values: DictationNumberFormat.allCases) { $0.title }
                        KukuDivider()
                        choiceRow(localized("Match the app’s tone"), selection: $draft.matchAppTone,
                                  global: settings.matchAppTone, values: [true, false]) { booleanTitle($0) }
                            .disabled(effectiveCleanup == .verbatim)
                        if effectiveCleanup == .verbatim {
                            Text(localized("Verbatim keeps the spoken words. App tone has no effect; expression preference can only affect punctuation and paragraphs."))
                                .font(.kuku(.subheadline))
                                .foregroundStyle(KukuColor.textSecondary)
                                .kukuRowFrame()
                        }
                    }
                    KukuGroup(localized("Expression preference (optional)")) {
                        VStack(alignment: .leading, spacing: KukuSpacing.sm) {
                            TextEditor(text: $draft.expressionPreference)
                                .frame(height: 90)
                                .onChange(of: draft.expressionPreference) { _, newValue in
                                    if newValue.count > 300 { draft.expressionPreference = String(newValue.prefix(300)) }
                                }
                            Text(localized("Example: Write naturally in chat and keep tone particles; break long sentences by meaning."))
                            Text(localized("Sent to Qwen with new Voice Input requests for this app. It cannot change the spoken meaning or override a formatting setting."))
                            Text(localized("\(draft.expressionPreference.count) / 300 characters"))
                        }
                        .font(.kuku(.subheadline))
                        .foregroundStyle(KukuColor.textSecondary)
                        .kukuRowFrame()
                    }
                }
                .padding(.horizontal, KukuLayout.sheetPadding)
            }
            KukuSheetFooter {
                if settings.dictationAppFormats.contains(where: { $0.bundleID == app.bundleID }) {
                    Button(localized("Delete this app rule"), role: .destructive) {
                        settings.removeDictationAppFormat(for: app.bundleID)
                        dismiss()
                    }
                }
                Button(localized("Cancel")) { dismiss() }
                    .buttonStyle(.kukuSecondary)
                Button(localized("Save")) {
                    settings.saveDictationAppFormat(draft)
                    dismiss()
                }
                .buttonStyle(.kukuPrimary)
            }
        }
        .frame(width: 610, height: 620)
    }

    private func choiceRow<Value: Hashable>(
        _ title: String, selection: Binding<Value?>, global: Value, values: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        KukuRow(title, caption: selection.wrappedValue == nil
                ? localized("Current global value: \(label(global))") : nil) {
            KukuPicker(title, options: [nil] + values.map(Optional.some), selection: selection) { value in
                value.map(label) ?? localized("Follow global (current: \(label(global)))")
            }
        }
    }

    private func booleanTitle(_ value: Bool) -> String { value ? localized("On") : localized("Off") }
}
