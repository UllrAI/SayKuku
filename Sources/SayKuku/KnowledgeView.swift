import SwiftUI

struct KnowledgeView: View {
    @Environment(AppState.self) private var appState
    @State private var search = ""
    @State private var filter: KnowledgeFilter = .all
    @State private var showingImport = false
    @State private var newName = ""

    var filteredEntities: [KnowledgeEntity] {
        appState.knowledgeEntities.filter { entity in
            (filter == .all || entity.type.filter == filter) &&
            (search.isEmpty || entity.name.localizedCaseInsensitiveContains(search) || entity.detail.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            KukuPageTabs(
                items: KnowledgeFilter.allCases,
                selection: $filter,
                title: { $0.title(appState) }
            )
            Divider().opacity(0.55)

            KukuPageContent {
                entityList
            }
        }
        .sheet(isPresented: $showingImport) {
            KnowledgeImportSheet()
        }
    }

    private var header: some View {
        ScreenHeader(
            eyebrow: "Knowledge",
            title: appState.text("让熟悉的人和词，被准确听见", "Make familiar names sound right"),
            subtitle: appState.text("只保存确认过的名称，联系方式会自动过滤。", "Only confirmed names are saved; contact details are filtered.")
        ) {
            HStack(spacing: 8) {
                Button {
                    showingImport = true
                } label: {
                    Label(appState.text("粘贴文本导入", "Import pasted text"), systemImage: "doc.on.clipboard")
                }
                .buttonStyle(HoverFillButtonStyle())

                Button {
                    withAnimation(Motion.snappy) { newName = appState.text("新术语", "New term") }
                } label: {
                    Label(appState.text("手动添加", "Add manually"), systemImage: "plus")
                }
                .buttonStyle(HoverFillButtonStyle(prominent: true))
            }
        }
    }

    private var entityList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(KukuColor.stone)
                TextField(appState.text("搜索人名、项目或术语", "Search names, projects, or terms"), text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(KukuColor.stone)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(KukuColor.surfaceStrong, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(KukuColor.line, lineWidth: 1))
            .padding(.vertical, 16)

            if !newName.isEmpty {
                QuickAddRow(name: $newName) { name, type in
                    appState.addKnowledge(name: name, type: type)
                    newName = ""
                }
                .padding(.bottom, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredEntities) { entity in
                        EntityRow(entity: entity) {
                            appState.knowledgeRelationships.removeAll { $0.fromEntityID == entity.id || $0.toEntityID == entity.id }
                            appState.knowledgeEntities.removeAll { $0.id == entity.id }
                        }
                        Divider().padding(.leading, 59).opacity(0.55)
                    }
                }
                .padding(.bottom, 36)
            }
            .overlay {
                if filteredEntities.isEmpty {
                    ContentUnavailableView(
                        appState.text("没有匹配项", "No matches"),
                        systemImage: "text.magnifyingglass",
                        description: Text(appState.text("试试其他关键词或分类。", "Try another term or category."))
                    )
                        .foregroundStyle(KukuColor.stone)
                }
            }
        }
    }

}

private struct QuickAddRow: View {
    @Environment(AppState.self) private var appState
    @Binding var name: String
    let onAdd: (String, EntityType) -> Void
    @FocusState private var focused: Bool
    @State private var type: EntityType = .term
    @State private var classifying = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.badge.plus")
                .foregroundStyle(KukuColor.coral)
            TextField(appState.text("输入名称", "Enter a name"), text: $name)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { if !name.isEmpty { onAdd(name, type) } }
            Picker("类型", selection: $type) {
                ForEach(EntityType.allCases) { type in Text(type.title(appState)).tag(type) }
            }
            .labelsHidden()
            .frame(width: 120)
            Button(classifying ? appState.text("识别中…", "Classifying…") : appState.text("识别类型", "Detect type")) {
                classifying = true
                Task {
                    do { type = try await appState.suggestEntityType(for: name) }
                    catch { appState.showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill") }
                    classifying = false
                }
            }
            .buttonStyle(HoverFillButtonStyle())
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || classifying)
            Button(appState.text("添加", "Add")) { if !name.isEmpty { onAdd(name, type) } }
                .buttonStyle(HoverFillButtonStyle(prominent: true))
        }
        .padding(12)
        .background(KukuColor.surfaceStrong, in: RoundedRectangle(cornerRadius: KukuLayout.radiusMedium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: KukuLayout.radiusMedium, style: .continuous).stroke(KukuColor.coral.opacity(0.22), lineWidth: 1))
        .onAppear { focused = true }
    }
}

private struct EntityRow: View {
    @Environment(AppState.self) private var appState
    let entity: KnowledgeEntity
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: entity.type.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(entity.type.color)
                .frame(width: 34, height: 34)
                .background(entity.type.color.opacity(0.11), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(entity.name)
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(entity.type.title(appState))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(entity.type.color)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(entity.type.color.opacity(0.09), in: Capsule())
                }
                Text(entity.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(KukuColor.stone)
            }
            Spacer()
            if !entity.aliases.isEmpty {
                Text(entity.aliases.joined(separator: " · "))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(KukuColor.stone)
            }
            Menu {
                Button(appState.text("删除", "Delete"), role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(KukuColor.stone)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .padding(.horizontal, 10)
        .frame(height: KukuLayout.rowHeight)
    }
}

private struct KnowledgeImportSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var source = ""
    @State private var selected = Set<UUID>()
    @State private var analysis: KnowledgeAnalysis?
    @State private var analyzing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(step == 0 ? appState.text("粘贴文本", "Paste text") : appState.text("确认抽取结果", "Review extracted data"))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(step == 0
                         ? appState.text("只会抽取对 Voice 有价值的实体和关系。", "Only voice-relevant entities and relationships are extracted.")
                         : appState.text("逐项确认 New、Merge、Conflict 与 Ignored。", "Review New, Merge, Conflict, and Ignored items."))
                        .font(.system(size: 11))
                        .foregroundStyle(KukuColor.stone)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.black.opacity(0.05), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(24)

            Divider().opacity(0.6)

            if step == 0 {
                VStack(alignment: .leading, spacing: 14) {
                    TextEditor(text: $source)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(KukuColor.line, lineWidth: 1))
                    Label(appState.text("检测到的手机号、邮箱与地址会被默认忽略", "Phone numbers, email addresses, and addresses are ignored"), systemImage: "eye.slash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(KukuColor.stone)
                }
                .padding(24)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(analysis?.candidates ?? []) { candidate in
                            ImportCandidateRow(candidate: candidate, isSelected: selected.contains(candidate.id)) {
                                guard candidate.status != .ignored else { return }
                                if selected.contains(candidate.id) { selected.remove(candidate.id) } else { selected.insert(candidate.id) }
                            }
                        }
                        if let relationships = analysis?.relationships, !relationships.isEmpty {
                            Text(appState.text("关系", "Relationships"))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(KukuColor.stone)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                            ForEach(relationships) { candidate in
                                ImportRelationshipRow(candidate: candidate, isSelected: selected.contains(candidate.id)) {
                                    if selected.contains(candidate.id) { selected.remove(candidate.id) }
                                    else { selected.insert(candidate.id) }
                                }
                            }
                        }
                    }
                    .padding(24)
                }
            }

            Divider().opacity(0.6)

            HStack {
                if step == 1 {
                    Button(appState.text("返回", "Back")) { withAnimation(Motion.snappy) { step = 0 } }
                        .buttonStyle(HoverFillButtonStyle())
                }
                Spacer()
                Text(step == 1
                     ? appState.text("将导入 \(selected.count) 项", "Import \(selected.count) items")
                     : appState.text("原文不会被保存", "Source text will not be saved"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(KukuColor.stone)
                Button(step == 0 ? appState.text("分析文本", "Analyze text") : appState.text("确认导入", "Confirm import")) {
                    if step == 0 { analyze() }
                    else if let analysis {
                        appState.commitKnowledge(analysis, selectedIDs: selected)
                        appState.showToast(
                            appState.text("已导入 \(selected.count) 项 Knowledge", "Imported \(selected.count) Knowledge items"),
                            symbol: "checkmark.seal.fill"
                        )
                        dismiss()
                    }
                }
                .buttonStyle(HoverFillButtonStyle(prominent: true))
                .disabled(step == 0 ? source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || analyzing : selected.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 680, height: 580)
        .background(KukuColor.canvas)
        .overlay {
            if analyzing {
                ZStack {
                    Color.black.opacity(0.08)
                    ProgressView(appState.text("正在分析…", "Analyzing…"))
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .alert(appState.text("分析失败", "Analysis failed"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button(appState.text("好", "OK"), role: .cancel) { } } message: { Text(errorMessage ?? "") }
    }

    private func analyze() {
        analyzing = true
        errorMessage = nil
        Task {
            do {
                let value = try await appState.analyzeKnowledge(source)
                analysis = value
                selected = Set(value.candidates.filter { $0.status == .new || $0.status == .merge }.map(\.id)
                    + value.relationships.filter { $0.status == .new || $0.status == .merge }.map(\.id))
                withAnimation(Motion.panel) { step = 1 }
            } catch {
                errorMessage = error.localizedDescription
            }
            analyzing = false
        }
    }
}

private struct ImportRelationshipRow: View {
    let candidate: ImportRelationshipCandidate
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? KukuColor.coral : KukuColor.stone)
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(candidate.relationship.from) → \(candidate.relationship.type.rawValue) → \(candidate.relationship.to)")
                        .font(.system(size: 13, weight: .semibold))
                    Text(candidate.relationship.evidence)
                        .font(.system(size: 11))
                        .foregroundStyle(KukuColor.stone)
                }
                Spacer()
                Text(candidate.status.rawValue)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(candidate.status.color)
            }
            .padding(14)
            .background(Color.white.opacity(0.54), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ImportCandidateRow: View {
    @Environment(AppState.self) private var appState
    let candidate: ImportCandidate
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: candidate.status == .ignored ? "minus.circle.fill" : (isSelected ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? KukuColor.coral : KukuColor.stone)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(candidate.entity.name)
                            .font(.system(size: 13, weight: .semibold))
                        Text(candidate.status.rawValue)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(candidate.status.color)
                            .padding(.horizontal, 7)
                            .frame(height: 18)
                            .background(candidate.status.color.opacity(0.1), in: Capsule())
                    }
                    Text(candidate.evidence)
                        .font(.system(size: 11))
                        .foregroundStyle(KukuColor.stone)
                }
                Spacer()
                Text(candidate.entity.type.title(appState))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(KukuColor.stone)
            }
            .padding(14)
            .background(Color.white.opacity(0.54), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(isSelected ? KukuColor.coral.opacity(0.2) : KukuColor.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(candidate.status == .ignored)
    }
}

enum KnowledgeFilter: String, CaseIterable, Identifiable {
    case all, people, organizations, projects, terms
    var id: String { rawValue }
    @MainActor func title(_ appState: AppState) -> String {
        switch self {
        case .all: appState.text("全部", "All")
        case .people: appState.text("人物", "People")
        case .organizations: appState.text("组织", "Organizations")
        case .projects: appState.text("项目", "Projects")
        case .terms: appState.text("术语", "Terms")
        }
    }
    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .people: "person.2"
        case .organizations: "building.2"
        case .projects: "folder"
        case .terms: "textformat.abc"
        }
    }
}

private extension ImportStatus {
    var color: Color {
        switch self {
        case .new: KukuColor.mint
        case .merge: Color(red: 0.34, green: 0.50, blue: 0.75)
        case .conflict: KukuColor.amber
        case .ignored: KukuColor.stone
        }
    }
}
