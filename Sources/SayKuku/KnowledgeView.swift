import SwiftUI

struct KnowledgeView: View {
    @Environment(AppState.self) private var appState
    @State private var search = ""
    @State private var filter: KnowledgeFilter = .all
    @State private var showingImport = false
    @State private var showingAdd = false
    @State private var editingEntity: KnowledgeEntity?

    var filteredEntities: [KnowledgeEntity] {
        appState.knowledgeEntities.filter { entity in
            (filter == .all || entity.type.filter == filter) &&
            (search.isEmpty || entity.name.localizedCaseInsensitiveContains(search) || entity.detail.localizedCaseInsensitiveContains(search) || entity.aliases.contains { $0.localizedCaseInsensitiveContains(search) })
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
        .sheet(isPresented: $showingAdd) {
            KnowledgeFormSheet()
        }
        .sheet(item: $editingEntity) { entity in
            KnowledgeFormSheet(entity: entity)
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
                    showingAdd = true
                } label: {
                    Label(appState.text("手动添加", "Add manually"), systemImage: "plus")
                }
                .buttonStyle(HoverFillButtonStyle(prominent: true))
            }
        }
    }

    private var entityList: some View {
        VStack(spacing: 0) {
            searchField
            listSummary

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredEntities) { entity in
                        EntityRow(entity: entity) {
                            appState.knowledgeRelationships.removeAll { $0.fromEntityID == entity.id || $0.toEntityID == entity.id }
                            appState.knowledgeEntities.removeAll { $0.id == entity.id }
                        } onEdit: {
                            editingEntity = entity
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 32)
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

    private var searchField: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(KukuColor.stone)
            TextField(appState.text("搜索名称、别名或备注", "Search names, aliases, or details"), text: $search)
                .textFieldStyle(.plain)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(KukuColor.stone)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(appState.text("清除搜索", "Clear search"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(KukuColor.surfaceStrong, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(KukuColor.line, lineWidth: 1))
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var listSummary: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(appState.text("知识条目", "Knowledge items"))
                    .font(.system(size: 12, weight: .semibold))
                Text(appState.text("已确认的名称会用于语音识别。", "Confirmed names are used for voice recognition."))
                    .font(.system(size: 10))
                    .foregroundStyle(KukuColor.stone)
            }
            Spacer()
            Text(appState.text("\(filteredEntities.count) 条", "\(filteredEntities.count) items"))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(KukuColor.stone)
            if filter != .all || !search.isEmpty {
                Button(appState.text("清除筛选", "Clear filters")) {
                    withAnimation(Motion.snappy) {
                        filter = .all
                        search = ""
                    }
                }
                .buttonStyle(TintButtonStyle())
            }
        }
        .padding(.bottom, 12)
    }

}

private struct EntityRow: View {
    @Environment(AppState.self) private var appState
    let entity: KnowledgeEntity
    let onDelete: () -> Void
    let onEdit: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: entity.type.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(entity.type.color)
                .frame(width: 38, height: 38)
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
                if !entity.detail.isEmpty {
                    Text(entity.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(KukuColor.stone)
                        .lineLimit(1)
                } else if !entity.aliases.isEmpty {
                    Text(appState.text("别名：", "Aliases: ") + entity.aliases.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(KukuColor.stone)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text(appState.text("来源：\(entity.source.title(appState))", "Source: \(entity.source.title(appState))"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(KukuColor.stone.opacity(0.82))
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                Button(action: onEdit) {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                        Text(appState.text("编辑", "Edit"))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .buttonStyle(TintButtonStyle())
                .frame(width: 78, height: 32)
                .accessibilityLabel(appState.text("编辑 \(entity.name)", "Edit \(entity.name)"))

                Menu {
                    Button(appState.text("删除", "Delete"), role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(KukuColor.stone)
                        .frame(width: 30, height: 32)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help(appState.text("更多操作", "More actions"))
            }
            .frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background((isHovering ? KukuColor.surfaceStrong : KukuColor.surface), in: RoundedRectangle(cornerRadius: KukuLayout.radiusMedium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: KukuLayout.radiusMedium, style: .continuous).stroke(KukuColor.line, lineWidth: 1))
        .onHover { isHovering = $0 }
    }
}

private struct KnowledgeFormSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let entity: KnowledgeEntity?
    @State private var name: String
    @State private var type: EntityType
    @State private var detail: String
    @State private var aliases: String
    @State private var classifying = false

    init(entity: KnowledgeEntity? = nil) {
        self.entity = entity
        _name = State(initialValue: entity?.name ?? "")
        _type = State(initialValue: entity?.type ?? .term)
        _detail = State(initialValue: entity?.detail ?? "")
        _aliases = State(initialValue: entity?.aliases.joined(separator: "、") ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: entity == nil ? "plus.circle.fill" : "pencil.circle.fill")
                    .font(.system(size: 25))
                    .foregroundStyle(KukuColor.coral)
                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.text(entity == nil ? "添加知识" : "编辑知识", entity == nil ? "Add knowledge" : "Edit knowledge"))
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Text(appState.text("让 SayKuku 认识这个名称。", "Teach SayKuku this name."))
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
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider().opacity(0.6)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        formFieldLabel(appState.text("名称", "Name"), required: true)
                        KukuFormInput(
                            text: $name,
                            prompt: appState.text("输入名称", "Enter a name"),
                            autoFocus: entity == nil,
                            onSubmit: { if canSave { save() } }
                        )
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .firstTextBaseline) {
                            formFieldLabel(appState.text("类别", "Category"), required: true)
                            Spacer()
                            Button {
                                classify()
                            } label: {
                                Label(
                                    classifying ? appState.text("识别中…", "Detecting…") : appState.text("根据名称识别", "Detect from name"),
                                    systemImage: classifying ? "hourglass" : "sparkles"
                                )
                            }
                            .buttonStyle(TintButtonStyle())
                            .disabled(!canSave || classifying)
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 148, maximum: 220), spacing: 8)], spacing: 8) {
                            ForEach(EntityType.allCases) { option in
                                Button {
                                    type = option
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: option.symbol)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(option.color)
                                            .frame(width: 25, height: 25)
                                            .background(option.color.opacity(0.11), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                        Text(option.title(appState))
                                            .font(.system(size: 11.5, weight: type == option ? .semibold : .medium))
                                            .foregroundStyle(type == option ? KukuColor.ink : KukuColor.stone)
                                        Spacer(minLength: 2)
                                        if type == option {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(KukuColor.coral)
                                                .font(.system(size: 13))
                                        }
                                    }
                                    .padding(.horizontal, 9)
                                    .frame(height: 42)
                                    .background(type == option ? option.color.opacity(0.10) : Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .stroke(type == option ? option.color.opacity(0.35) : KukuColor.line, lineWidth: 1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        formFieldLabel(appState.text("备注", "Detail"))
                        KukuFormInput(
                            text: $detail,
                            prompt: appState.text("例如：团队负责人、常用项目名", "For example: team lead or project name"),
                            multiline: true
                        )
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        formFieldLabel(appState.text("别名", "Aliases"))
                        KukuFormInput(
                            text: $aliases,
                            prompt: appState.text("多个别名用顿号或逗号分隔", "Separate aliases with commas")
                        )
                        Text(appState.text("别名也会参与语音识别。", "Aliases are also used for voice recognition."))
                            .font(.system(size: 10))
                            .foregroundStyle(KukuColor.stone)
                    }
                }
                .padding(20)
            }
            .frame(maxHeight: .infinity)

            Divider().opacity(0.6)

            HStack(spacing: 10) {
                if canSave {
                    Text(appState.text("确认类别后即可保存", "Review the category, then save"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(KukuColor.stone)
                } else {
                    Text(appState.text("名称不能为空", "A name is required"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(KukuColor.coral)
                }
                Spacer()
                Button(appState.text("取消", "Cancel")) { dismiss() }
                    .buttonStyle(HoverFillButtonStyle())
                Button(appState.text(entity == nil ? "添加" : "保存", entity == nil ? "Add" : "Save")) { save() }
                    .buttonStyle(HoverFillButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave || classifying)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 560, height: 640)
        .background(KukuColor.canvas)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func formFieldLabel(_ title: String, required: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(KukuColor.ink)
            if required {
                Text("*")
                    .foregroundStyle(KukuColor.coral)
            }
        }
    }

    private func save() {
        let editedAliases = aliases
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "、" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let entity {
            guard appState.updateKnowledge(
                id: entity.id,
                name: name,
                type: type,
                detail: detail,
                aliases: editedAliases
            ) else { return }
        } else {
            guard appState.addKnowledge(name: name, type: type, detail: detail, aliases: editedAliases) else { return }
        }
        dismiss()
    }

    private func classify() {
        classifying = true
        Task {
            do { type = try await appState.suggestEntityType(for: name) }
            catch { appState.showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill") }
            classifying = false
        }
    }
}

private struct KukuFormInput: View {
    @Binding var text: String
    let prompt: String
    var multiline = false
    var autoFocus = false
    var onSubmit: (() -> Void)? = nil
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if multiline {
                TextField(prompt, text: $text, axis: .vertical)
                    .lineLimit(1...2)
            } else {
                TextField(prompt, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .focused($isFocused)
        .onSubmit { onSubmit?() }
        .padding(.horizontal, 12)
        .padding(.vertical, multiline ? 9 : 0)
        .frame(maxWidth: .infinity, minHeight: multiline ? 52 : 40, alignment: .topLeading)
        .background(
            isFocused ? KukuColor.surfaceStrong : Color.white.opacity(0.66),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isFocused ? KukuColor.coral.opacity(0.58) : KukuColor.line, lineWidth: isFocused ? 1.5 : 1)
        }
        .shadow(color: isFocused ? KukuColor.coral.opacity(0.08) : .clear, radius: 5)
        .onAppear {
            if autoFocus { isFocused = true }
        }
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
                            appState.text("已导入 \(selected.count) 项知识", "Imported \(selected.count) Knowledge items"),
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

private extension EntitySource {
    @MainActor func title(_ appState: AppState) -> String {
        switch self {
        case .manual: appState.text("手动添加", "Manual")
        case .importText: appState.text("文本导入", "Text import")
        case .correction: appState.text("纠正记忆", "Correction")
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
