import SwiftUI

struct DomainOnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDomains: Set<DomainPreset> = []
    @State private var customTerms: [String] = []
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
                eyebrow: appState.setupProgress?.title(appState),
                title: appState.didCompleteOnboarding
                    ? appState.text("常用领域与词汇", "Domains & Vocabulary")
                    : appState.text("先让 SayKuku 认识你的词", "Teach SayKuku Your Vocabulary"),
                description: appState.text(
                    "选择你常聊的领域，识别时会优先考虑相关术语。你也可以添加自己的产品名、技术词或行业词。",
                    "Pick the domains you talk about most, and SayKuku will favor their terms when transcribing. You can also add your own product names, technical terms, or industry jargon."
                )
            ) {
                KukuSheetIcon(symbol: "text.bubble.fill")
            }
            KukuDivider(inset: 0)

            ScrollView {
                VStack(alignment: .leading, spacing: KukuLayout.sectionSpacing) {
                    domainSection
                    customTermsSection
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
        .interactiveDismissDisabled(!appState.didCompleteOnboarding)
        .onAppear(perform: loadCurrentProfile)
    }

    private var domainSection: some View {
        VStack(alignment: .leading, spacing: KukuSpacing.md) {
            KukuFieldLabel(text: appState.text("常用领域（可多选）", "Common domains (select any)"))

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

    private var customTermsSection: some View {
        VStack(alignment: .leading, spacing: KukuSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                KukuFieldLabel(text: appState.text("自定义词汇", "Custom vocabulary"))
                Spacer()
                if !customTerms.isEmpty {
                    Text("\(customTerms.count)/\(AppState.maxDomainTerms)")
                        .font(.kuku(.caption).monospacedDigit())
                        .foregroundStyle(KukuColor.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: KukuSpacing.sm) {
                HStack(spacing: KukuSpacing.sm) {
                    KukuTextField(
                        prompt: appState.text("例如：Vibe Coding、SayKuku、项目代号", "For example: Vibe Coding, SayKuku, project names"),
                        text: $newTerm,
                        onSubmit: addTerm
                    )

                    Button(action: addTerm) {
                        Label(appState.text("添加", "Add"), systemImage: "plus")
                    }
                    .buttonStyle(.kukuSecondary)
                    .disabled(!canAddTerm)
                }

                if let termHint {
                    KukuSheetNote(text: termHint, isError: hasBlockedTerm)
                        .padding(.leading, KukuSpacing.xs)
                }
            }

            if !customTerms.isEmpty {
                // 120 is the narrowest chip that still fits a short term and its remove button.
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120), spacing: KukuSpacing.sm)],
                    alignment: .leading,
                    spacing: KukuSpacing.sm
                ) {
                    ForEach(customTerms, id: \.self) { term in
                        HStack(spacing: KukuSpacing.xs) {
                            Text(term)
                                .font(.kuku(.subheadline, weight: .medium))
                                .foregroundStyle(KukuColor.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            KukuIconButton(
                                symbol: "xmark",
                                label: appState.text("移除 \(term)", "Remove \(term)"),
                                size: .small
                            ) {
                                customTerms.removeAll { $0 == term }
                            }
                        }
                        .padding(.leading, KukuSpacing.md)
                        .padding(.trailing, KukuSpacing.xxs)
                        .frame(height: KukuLayout.controlHeightSmall)
                        .background(KukuColor.fill, in: Capsule())
                    }
                }
            }
        }
    }

    private var privacyNote: some View {
        Label(
            appState.text("选中的领域和词汇会随语音请求发送给 Qwen。", "Your selected domains and terms are sent to Qwen with voice requests."),
            systemImage: "paperplane"
        )
        .font(.kuku(.subheadline))
        .foregroundStyle(KukuColor.textSecondary)
    }

    private var footer: some View {
        // Opened from Settings, the sheet is already where changes are made.
        KukuSheetFooter(
            note: appState.didCompleteOnboarding
                ? nil
                : KukuSheetNote(text: appState.text("以后可在“设置 › 语音输入”中修改。", "You can change this later in Settings › Voice Input."))
        ) {
            if appState.didCompleteOnboarding {
                Button(appState.text("取消", "Cancel"), action: dismiss.callAsFunction)
                    .buttonStyle(.kukuSecondary)
                    .keyboardShortcut(.cancelAction)
            } else {
                Button(appState.text("跳过", "Skip")) {
                    appState.completeDomainOnboarding(domains: [], customTerms: [])
                }
                .buttonStyle(.kukuSecondary)
                .keyboardShortcut(.cancelAction)
            }
            Button(appState.didCompleteOnboarding
                   ? appState.text("保存", "Save")
                   : appState.text("继续", "Continue")) {
                addTerm()
                appState.completeDomainOnboarding(domains: selectedDomains, customTerms: customTerms)
            }
            .buttonStyle(.kukuPrimary)
            // While a term is being typed, Return adds it instead of closing the sheet.
            .keyboardShortcut(pendingTerm.isEmpty ? KeyboardShortcut.defaultAction : nil)
            .disabled(hasBlockedTerm)
        }
    }

    private var pendingTerm: String {
        newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isTermTooLong: Bool {
        pendingTerm.count > AppState.maxDomainTermLength
    }

    private var isAtTermLimit: Bool {
        customTerms.count >= AppState.maxDomainTerms
    }

    private var canAddTerm: Bool {
        !pendingTerm.isEmpty && !isTermTooLong && !isAtTermLimit
    }

    /// A typed term that can't be added would be lost on save, so saving waits until it's fixed.
    private var hasBlockedTerm: Bool {
        !pendingTerm.isEmpty && !canAddTerm
    }

    private var termHint: String? {
        if isTermTooLong {
            return appState.text(
                "每个词最多 \(AppState.maxDomainTermLength) 个字符",
                "Keep each term to \(AppState.maxDomainTermLength) characters or fewer"
            )
        }
        if isAtTermLimit {
            return appState.text(
                "最多添加 \(AppState.maxDomainTerms) 个，移除一个后才能继续添加",
                "You can add up to \(AppState.maxDomainTerms) terms. Remove one to add another."
            )
        }
        return nil
    }

    private func loadCurrentProfile() {
        guard !didLoad else { return }
        didLoad = true
        selectedDomains = appState.selectedDomains
        customTerms = appState.customDomainTerms
    }

    /// Keeps the typed text when it can't be added, so the hint below the field still applies to it.
    private func addTerm() {
        guard canAddTerm else { return }
        customTerms = AppState.normalizedDomainTerms(customTerms + [pendingTerm])
        newTerm = ""
    }
}

private struct DomainChoice: View {
    @Environment(AppState.self) private var appState
    let domain: DomainPreset
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: KukuSpacing.sm) {
                KukuIconTile(symbol: domain.symbol)
                Text(domain.title(isChineseUI: appState.usesChineseUI))
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
