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
            header
            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    domainSection
                    customTermsSection
                    privacyNote
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 22)
            }

            Divider().opacity(0.5)
            footer
        }
        .frame(width: 720, height: 620)
        .background(KukuColor.canvas)
        .interactiveDismissDisabled(!appState.didCompleteOnboarding)
        .onAppear(perform: loadCurrentProfile)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(KukuColor.coralSoft)
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(KukuColor.coral)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 5) {
                Text(appState.didCompleteOnboarding
                     ? appState.text("调整常用领域", "Edit your domains")
                     : appState.text("先让 SayKuku 认识你的词", "Teach SayKuku your vocabulary"))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text(appState.text(
                    "选择你常聊的领域，识别时会优先考虑相关术语。你也可以添加自己的产品名、技术词或行业词。",
                    "Choose the domains you talk about. SayKuku will consider their terminology during recognition, and you can add your own terms."
                ))
                .font(.system(size: 11.5))
                .foregroundStyle(KukuColor.stone)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            if appState.didCompleteOnboarding {
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(KukuColor.shade.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(appState.text("关闭", "Close"))
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 19)
    }

    private var domainSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionEyebrow(text: appState.text("常用领域（可多选）", "Common domains · select any"))

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
            SectionEyebrow(text: appState.text("自定义词汇", "Custom vocabulary"))

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
                .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.leading, 13)
            .padding(.trailing, 6)
            .frame(height: 42)
            .background(KukuColor.surfaceStrong, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(KukuColor.line, lineWidth: 1))

            if !customTerms.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(customTerms, id: \.self) { term in
                        HStack(spacing: 7) {
                            Text(term).lineLimit(1)
                            Spacer(minLength: 0)
                            Button {
                                customTerms.removeAll { $0 == term }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(appState.text("移除 \(term)", "Remove \(term)"))
                        }
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(KukuColor.ink)
                        .padding(.horizontal, 10)
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
            systemImage: "lock.fill"
        )
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(KukuColor.stone)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(appState.text("以后可在语音输入设置中修改。", "You can edit this later in Voice Input settings."))
                .font(.system(size: 10.5))
                .foregroundStyle(KukuColor.stone)
            Spacer()
            if !appState.didCompleteOnboarding {
                Button(appState.text("跳过", "Skip")) {
                    appState.completeDomainOnboarding(domains: [], customTerms: [])
                }
                .buttonStyle(HoverFillButtonStyle())
            } else {
                Button(appState.text("取消", "Cancel"), action: dismiss.callAsFunction)
                    .buttonStyle(HoverFillButtonStyle())
            }
            Button(appState.didCompleteOnboarding
                   ? appState.text("保存", "Save")
                   : appState.text("保存并继续", "Save & continue")) {
                addPendingTerm()
                appState.completeDomainOnboarding(domains: selectedDomains, customTerms: customTerms)
            }
            .buttonStyle(HoverFillButtonStyle(prominent: true))
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 15)
    }

    private func loadCurrentProfile() {
        guard !didLoad else { return }
        didLoad = true
        selectedDomains = appState.selectedDomains
        customTerms = appState.customDomainTerms
    }

    private func addTerm() {
        addPendingTerm()
    }

    private func addPendingTerm() {
        let value = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        customTerms = AppState.normalizedDomainTerms(customTerms + [value])
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
                    .background((selected ? KukuColor.coral : KukuColor.stone).opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                Text(domain.title(isChineseUI: appState.usesChineseUI))
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? KukuColor.coral.opacity(0.24) : KukuColor.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
