import SwiftUI

struct DomainOnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDomains: Set<DomainPreset> = []
    /// Terms typed in this sheet; they go into Memory when it's saved.
    @State private var terms: [String] = []
    @State private var newTerm = ""
    @State private var didLoad = false

    private let columns = [
        GridItem(.flexible(), spacing: KukuSpacing.sm),
        GridItem(.flexible(), spacing: KukuSpacing.sm),
        GridItem(.flexible(), spacing: KukuSpacing.sm)
    ]

    var body: some View {
        VStack(spacing: 0) {
            KukuSheetHeader(
                eyebrow: appState.setupProgress?.title,
                title: appState.settings.didCompleteOnboarding
                    ? localized("Domains & Vocabulary")
                    : localized("Teach SayKuku Your Vocabulary"),
                description: localized(
                    "Pick the domains you talk about most, and SayKuku will favor their terms when transcribing. You can also add your own product names, technical terms, or industry jargon."
                )
            ) {
                KukuSheetIcon(symbol: "text.bubble.fill")
            }
            KukuDivider(inset: 0)

            ScrollView {
                VStack(alignment: .leading, spacing: KukuLayout.sectionSpacing) {
                    domainSection
                    termsSection
                    privacyNote
                }
                .padding(.horizontal, KukuLayout.sheetPadding)
                .padding(.vertical, KukuSpacing.xl)
            }

            KukuDivider(inset: 0)
            footer
        }
        .frame(width: KukuLayout.sheetWideWidth, height: KukuLayout.sheetHeight)
        .background(KukuColor.canvas)
        .interactiveDismissDisabled(!appState.settings.didCompleteOnboarding)
        .onAppear(perform: loadCurrentProfile)
    }

    private var domainSection: some View {
        VStack(alignment: .leading, spacing: KukuSpacing.md) {
            KukuFieldLabel(text: localized("Common domains (select any)"))

            LazyVGrid(columns: columns, spacing: KukuSpacing.sm) {
                ForEach(DomainPreset.allCases) { domain in
                    DomainChoice(
                        domain: domain,
                        selected: selectedDomains.contains(domain)
                    ) {
                        withAnimation(Motion.snappy) {
                            if selectedDomains.contains(domain) { selectedDomains.remove(domain) }
                            else { selectedDomains.insert(domain) }
                        }
                    }
                }
            }
        }
    }

    private var termsSection: some View {
        VStack(alignment: .leading, spacing: KukuSpacing.md) {
            KukuFieldLabel(text: localized("Custom vocabulary"))

            VStack(alignment: .leading, spacing: KukuSpacing.sm) {
                HStack(spacing: KukuSpacing.sm) {
                    KukuTextField(
                        prompt: localized("For example: Vibe Coding, SayKuku, project names"),
                        text: $newTerm,
                        onSubmit: addTerm
                    )

                    Button(action: addTerm) {
                        Label(localized("Add"), systemImage: "plus")
                    }
                    .buttonStyle(.kukuSecondary)
                    .disabled(!canAddTerm)
                }

                KukuSheetNote(
                    text: termError?.message ?? localized(
                        "SayKuku remembers these words. You can add aliases later in Memory."
                    ),
                    isError: termError != nil
                )
                .padding(.leading, KukuSpacing.xs)
            }

            if !terms.isEmpty {
                // 120 is the narrowest chip that still fits a short term and its remove button.
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120), spacing: KukuSpacing.sm)],
                    alignment: .leading,
                    spacing: KukuSpacing.sm
                ) {
                    ForEach(terms, id: \.self) { term in
                        HStack(spacing: KukuSpacing.xs) {
                            Text(term)
                                .font(.kuku(.subheadline, weight: .medium))
                                .foregroundStyle(KukuColor.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            KukuIconButton(
                                symbol: "xmark",
                                label: localized("Remove \(term)"),
                                size: .small
                            ) {
                                terms.removeAll { $0 == term }
                            }
                        }
                        .padding(.leading, KukuSpacing.md)
                        .padding(.trailing, KukuSpacing.xxs)
                        .frame(minHeight: KukuLayout.controlHeightSmall)
                        .background(KukuColor.fill, in: Capsule())
                    }
                }
            }
        }
    }

    private var privacyNote: some View {
        Label(
            localized("Your selected domains and terms are sent to Qwen with voice requests."),
            systemImage: "paperplane"
        )
        .font(.kuku(.subheadline))
        .foregroundStyle(KukuColor.textSecondary)
    }

    private var footer: some View {
        // Opened from Settings, the sheet is already where changes are made.
        KukuSheetFooter(
            note: appState.settings.didCompleteOnboarding
                ? nil
                : KukuSheetNote(text: localized("You can change this later in Settings › Memory."))
        ) {
            if appState.settings.didCompleteOnboarding {
                Button(localized("Cancel"), action: dismiss.callAsFunction)
                    .buttonStyle(.kukuSecondary)
                    .keyboardShortcut(.cancelAction)
            } else {
                Button(appState.setupSkipTitle) {
                    appState.completeDomainOnboarding(domains: [])
                }
                .buttonStyle(.kukuSecondary)
                .keyboardShortcut(.cancelAction)
            }
            Button(appState.settings.didCompleteOnboarding
                   ? localized("Save")
                   : appState.setupContinueTitle) {
                addTerm()
                // Terms were checked against Memory as they were added.
                for term in terms { _ = appState.data.addMemory(name: term, type: .term) }
                appState.completeDomainOnboarding(domains: selectedDomains)
            }
            .buttonStyle(.kukuPrimary)
            // While a term is being typed, Return adds it instead of closing the sheet.
            .keyboardShortcut(pendingTerm.isEmpty ? KeyboardShortcut.defaultAction : nil)
            // A typed term that can't be added would be lost on save, so saving waits until it's fixed.
            .disabled(termError != nil)
        }
    }

    private var pendingTerm: String {
        newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Why the typed term can't go into Memory, checked as it's typed.
    private var termError: MemorySaveError? {
        guard !pendingTerm.isEmpty else { return nil }
        return appState.data.validateMemory(MemoryEntity(name: pendingTerm, type: .term))
    }

    private var canAddTerm: Bool {
        !pendingTerm.isEmpty && termError == nil
    }

    private func loadCurrentProfile() {
        guard !didLoad else { return }
        didLoad = true
        selectedDomains = appState.settings.selectedDomains
    }

    /// Keeps the typed text when it can't be added, so the hint below the field still applies to it.
    private func addTerm() {
        guard canAddTerm else { return }
        let key = MemoryNormalizer.key(pendingTerm)
        // A term already in the list is visible there, so typing it again just clears the field.
        if !terms.contains(where: { MemoryNormalizer.key($0) == key }) { terms.append(pendingTerm) }
        newTerm = ""
    }
}

private struct DomainChoice: View {
    let domain: DomainPreset
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: KukuSpacing.sm) {
                KukuIconTile(symbol: domain.symbol)
                Text(domain.title)
                    .font(.kuku(.callout, weight: .medium))
                    .foregroundStyle(KukuColor.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                KukuSelectionIndicator(style: .checkbox, isSelected: selected)
            }
            .padding(.horizontal, KukuSpacing.sm)
            // The icon tile plus vertical breathing room, so one- and two-line titles align.
            .frame(maxWidth: .infinity, minHeight: KukuLayout.iconTile + 2 * KukuSpacing.sm, alignment: .leading)
            .kukuInteractiveSurface(isSelected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
