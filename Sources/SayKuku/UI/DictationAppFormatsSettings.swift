import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct DictationAppIdentity: Identifiable {
    let bundleID: String
    let name: String
    let url: URL?

    var id: String { bundleID }

    static func isSayKuku(_ bundleID: String) -> Bool {
        bundleID == Bundle.main.bundleIdentifier
            || bundleID == "com.saykuku.app" || bundleID == "com.saykuku.dev"
    }

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
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> DictationAppIdentity? in
            guard app.activationPolicy == .regular,
                  let id = app.bundleIdentifier, !DictationAppIdentity.isSayKuku(id),
                  let url = app.bundleURL else { return nil }
            return DictationAppIdentity(bundleID: id, url: url)
        }
        return Dictionary(apps.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
            .values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        KukuGroup(localized("Per-app settings")) {
            Text(localized("Customize cleanup and writing format for each app. Unchanged options follow the defaults above."))
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
        if let value = rule.cleanup { items.append(value.title) }
        if let value = rule.structure {
            items.append("\(localized("Automatic paragraphs and lists")): \(value ? localized("On") : localized("Off"))")
        }
        if let value = rule.refine { items.append(DictationFormatLabels.refinement(value)) }
        if let value = rule.keepEndingPunctuation {
            items.append("\(localized("Ending punctuation")): \(DictationFormatLabels.endingPunctuation(value))")
        }
        if let value = rule.numberFormat { items.append("\(localized("Number format")): \(value.title)") }
        if let value = rule.matchAppTone {
            items.append("\(localized("Adapt to the app")): \(value ? localized("On") : localized("Off"))")
        }
        if !rule.expressionPreference.isEmpty { items.append(localized("Style preference")) }
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
              !DictationAppIdentity.isSayKuku(id) else { return }
        editingApp = DictationAppIdentity(bundleID: id, url: url)
    }
}

private struct DictationAppFormatEditor: View {
    @Environment(\.dismiss) private var dismiss
    let app: DictationAppIdentity
    let settings: AppSettings
    @State private var showsWritingFormat = false
    @State private var showsStylePreference = false
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
                    KukuGroup(localized("Speech cleanup")) {
                        choiceRow(localized("Cleanup"), selection: $draft.cleanup,
                                  global: settings.dictationCleanup, values: DictationCleanup.allCases) { $0.title }
                        Text(DictationFormatLabels.cleanupCaption(effectiveCleanup))
                            .font(.kuku(.subheadline))
                            .foregroundStyle(KukuColor.textSecondary)
                            .padding(.horizontal, KukuLayout.rowPadding)
                            .padding(.bottom, KukuSpacing.md)
                        KukuDivider()
                        choiceRow(localized("Automatic paragraphs and lists"), selection: $draft.structure,
                                  global: settings.structureDictation, values: [true, false], label: booleanTitle)
                            .disabled(effectiveCleanup == .verbatim)
                        KukuDivider()
                        choiceRow(localized("Cleanup preference"), selection: $draft.refine,
                                  global: settings.refineDictation, values: [true, false], label: DictationFormatLabels.refinement)
                            .disabled(effectiveCleanup == .verbatim)
                        Text(effectiveCleanup == .verbatim ? DictationFormatLabels.inactiveCaption
                             : DictationFormatLabels.refinementCaption(draft.refine ?? settings.refineDictation))
                            .font(.kuku(.subheadline))
                            .foregroundStyle(KukuColor.textSecondary)
                            .kukuRowFrame()
                    }
                    KukuGroup {
                        DisclosureGroup(localized("Writing format"), isExpanded: $showsWritingFormat) {
                            choiceRow(localized("Adapt to the app"), selection: $draft.matchAppTone,
                                      global: settings.matchAppTone, values: [true, false], label: booleanTitle)
                                .disabled(effectiveCleanup == .verbatim)
                            KukuDivider()
                            choiceRow(localized("Ending punctuation"), selection: $draft.keepEndingPunctuation,
                                      global: settings.keepEndingPunctuation, values: [true, false],
                                      caption: DictationFormatLabels.endingPunctuationCaption, label: DictationFormatLabels.endingPunctuation)
                            KukuDivider()
                            choiceRow(localized("Number format"), selection: $draft.numberFormat,
                                      global: settings.dictationNumberFormat, values: DictationNumberFormat.allCases) { $0.title }
                        }
                        .disclosureGroupStyle(KukuDisclosureGroupStyle())
                    }
                    KukuGroup {
                        DisclosureGroup(localized("Style preference (optional)"), isExpanded: $showsStylePreference) {
                            VStack(alignment: .leading, spacing: KukuSpacing.sm) {
                                TextEditor(text: $draft.expressionPreference)
                                    .accessibilityLabel(localized("Style preference"))
                                    .frame(height: 90)
                                    .onChange(of: draft.expressionPreference) { _, newValue in
                                        if newValue.count > 300 { draft.expressionPreference = String(newValue.prefix(300)) }
                                    }
                                Text(localized("Example: Use a natural, relaxed tone in chat and keep tone particles."))
                                Text(localized("Sent with voice input for this app. The options above take priority; spoken meaning and details are preserved."))
                                Text(localized("\(draft.expressionPreference.count) / 300 characters"))
                            }
                            .font(.kuku(.subheadline))
                            .foregroundStyle(KukuColor.textSecondary)
                            .padding(.top, KukuSpacing.sm)
                            .padding(.horizontal, KukuLayout.rowPadding)
                            .padding(.bottom, KukuSpacing.sm)
                        }
                        .disclosureGroupStyle(KukuDisclosureGroupStyle())
                    }
                }
                .padding(.horizontal, KukuLayout.sheetPadding)
            }
            KukuSheetFooter {
                if settings.dictationAppFormats.contains(where: { $0.bundleID == app.bundleID }) {
                    Button(localized("Use default settings"), role: .destructive) {
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
        .frame(width: 650, height: 680)
    }

    private func choiceRow<Value: Hashable>(
        _ title: String, selection: Binding<Value?>, global: Value, values: [Value],
        caption: String? = nil,
        label: @escaping (Value) -> String
    ) -> some View {
        let captions = [selection.wrappedValue == nil ? localized("Default: \(label(global))") : nil, caption]
            .compactMap { $0 }
        return KukuRow(title, caption: captions.isEmpty ? nil : captions.joined(separator: "\n")) {
            KukuPicker(title, options: [nil] + values.map(Optional.some), selection: selection) { value in
                value.map(label) ?? localized("Follow global")
            }
        }
    }

    private func booleanTitle(_ value: Bool) -> String { value ? localized("On") : localized("Off") }
}

/// Shared labels keep global settings and app overrides consistent without changing stored values.
enum DictationFormatLabels {
    static func refinement(_ value: Bool) -> String {
        value ? localized("Prefer quality") : localized("Prefer speed")
    }

    static func endingPunctuation(_ value: Bool) -> String {
        value ? localized("Automatic") : localized("Omit")
    }

    static var endingPunctuationCaption: String {
        localized("Automatic lets the model choose. With Adapt to the app on, short chats may omit a period, documents use full punctuation, and code adds no final mark. Omit removes the final period, question mark, or exclamation mark.")
    }

    static func cleanupCaption(_ value: DictationCleanup) -> String {
        value == .light
            ? localized("Removes fillers and accidental repeats; self-corrections keep only the final wording.")
            : localized("Keeps fillers, repeats, and self-corrections; only adds punctuation.")
    }

    static func refinementCaption(_ value: Bool) -> String {
        value
            ? localized("Checks the first result again. May add a few seconds and uses an extra model request; keeps the first result if it fails.")
            : localized("Cleans up speech and applies your layout settings during recognition, without an extra check.")
    }

    static var inactiveCaption: String {
        localized("Automatic layout, extra checks, and app tone are inactive with Keep spoken wording. Your choices are saved.")
    }
}
