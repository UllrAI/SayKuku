import SwiftUI

struct DomainOnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDomains: Set<DomainPreset> = []
    @State private var customTerms: [String] = []
    @State private var newTerm = ""
    @State private var didLoad = false

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
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
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(KukuColor.coral)
            }
            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    domainSection
                    customTermsSection
                    privacyNote
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }

            Divider().opacity(0.5)
            footer
        }
        .frame(width: 640, height: 540)
        .background(KukuColor.canvas)
        .interactiveDismissDisabled(!appState.didCompleteOnboarding)
        .onAppear(perform: loadCurrentProfile)
    }

    private var domainSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle(appState.text("常用领域（可多选）", "Common domains (select any)"))

            LazyVGrid(columns: columns, spacing: 10) {
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
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle(appState.text("自定义词汇", "Custom vocabulary"))
                Spacer()
                if !customTerms.isEmpty {
                    Text("\(customTerms.count)/\(AppState.maxDomainTerms)")
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(KukuColor.stone)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 9) {
                    TextField(
                        appState.text("例如：Vibe Coding、SayKuku、项目代号", "For example: Vibe Coding, SayKuku, project names"),
                        text: $newTerm
                    )
                    .textFieldStyle(.plain)
                    .onSubmit(addTerm)

                    Button(action: addTerm) {
                        Label(appState.text("添加", "Add"), systemImage: "plus")
                    }
                    .buttonStyle(TintButtonStyle())
                    .disabled(!canAddTerm)
                }
                .padding(.leading, 13)
                .padding(.trailing, 4)
                .frame(height: 40)
                .background(KukuColor.surfaceStrong, in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous).stroke(KukuColor.line, lineWidth: 1))

                if let termHint {
                    Text(termHint)
                        .font(.system(size: 10.5))
                        .foregroundStyle(hasBlockedTerm ? KukuColor.coral : KukuColor.stone)
                        .padding(.leading, 4)
                }
            }

            if !customTerms.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(customTerms, id: \.self) { term in
                        HStack(spacing: 5) {
                            Text(term).lineLimit(1)
                            Spacer(minLength: 0)
                            Button {
                                customTerms.removeAll { $0 == term }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .frame(width: 16, height: 16)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(appState.text("移除", "Remove"))
                            .accessibilityLabel(appState.text("移除 \(term)", "Remove \(term)"))
                        }
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(KukuColor.ink)
                        .padding(.leading, 10)
                        .padding(.trailing, 5)
                        .frame(height: 28)
                        .background(KukuColor.coralSoft.opacity(0.55), in: Capsule())
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
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(KukuColor.stone)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(appState.text("以后可在“设置 › 语音输入”中修改。", "You can change this later in Settings › Voice Input."))
                .font(.system(size: 10.5))
                .foregroundStyle(KukuColor.stone)
            Spacer()
            if appState.didCompleteOnboarding {
                Button(appState.text("取消", "Cancel"), action: dismiss.callAsFunction)
                    .buttonStyle(HoverFillButtonStyle())
                    .keyboardShortcut(.cancelAction)
            } else {
                Button(appState.text("跳过", "Skip")) {
                    appState.completeDomainOnboarding(domains: [], customTerms: [])
                }
                .buttonStyle(HoverFillButtonStyle())
                .keyboardShortcut(.cancelAction)
            }
            Button(appState.didCompleteOnboarding
                   ? appState.text("保存", "Save")
                   : appState.text("继续", "Continue")) {
                addTerm()
                appState.completeDomainOnboarding(domains: selectedDomains, customTerms: customTerms)
            }
            .buttonStyle(HoverFillButtonStyle(prominent: true))
            // While a term is being typed, Return adds it instead of closing the sheet.
            .keyboardShortcut(pendingTerm.isEmpty ? KeyboardShortcut.defaultAction : nil)
            .disabled(hasBlockedTerm)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(KukuColor.stone)
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
            HStack(spacing: 9) {
                Image(systemName: domain.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? KukuColor.coral : KukuColor.stone)
                    .frame(width: 28, height: 28)
                    .background(
                        (selected ? KukuColor.coral : KukuColor.stone).opacity(0.09),
                        in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)
                    )
                Text(domain.title(isChineseUI: appState.usesChineseUI))
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? KukuColor.coral : KukuColor.stone.opacity(0.45))
            }
            .foregroundStyle(KukuColor.ink)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(selected ? KukuColor.coralSoft.opacity(0.42) : KukuColor.surfaceStrong)
            .overlay(
                RoundedRectangle(cornerRadius: KukuLayout.radiusMedium, style: .continuous)
                    .stroke(selected ? KukuColor.coral.opacity(0.24) : KukuColor.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: KukuLayout.radiusMedium, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
