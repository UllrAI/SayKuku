import SwiftUI

struct KnowledgeView: View {
    @Environment(AppState.self) private var appState
    @Binding var search: String
    @Binding var filter: KnowledgeFilter
    @State private var showingImport = false
    @State private var showingAdd = false
    @State private var editingEntity: KnowledgeEntity?
    @State private var pendingDeletion: KnowledgeEntity?

    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var filteredEntities: [KnowledgeEntity] {
        let text = query
        return appState.knowledgeEntities.filter { entity in
            (filter == .all || entity.type.filter == filter) && (text.isEmpty || Self.entity(entity, matches: text))
        }
    }

    private static func entity(_ entity: KnowledgeEntity, matches text: String) -> Bool {
        entity.name.localizedCaseInsensitiveContains(text)
            || entity.detail.localizedCaseInsensitiveContains(text)
            || entity.aliases.contains { $0.localizedCaseInsensitiveContains(text) }
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
        .confirmationDialog(
            pendingDeletion.map { appState.text("删除“\($0.name)”？", "Delete “\($0.name)”?") } ?? "",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { entity in
            Button(appState.text("删除", "Delete"), role: .destructive) { delete(entity) }
            Button(appState.text("取消", "Cancel"), role: .cancel) { }
        } message: { entity in
            Text(deletionMessage(for: entity))
        }
    }

    private var header: some View {
        ScreenHeader(
            eyebrow: appState.text("知识", "Knowledge"),
            title: appState.text("常用的人名和词，一次就听对", "Get names and terms right the first time"),
            subtitle: appState.text(
                "保存常用的人名、项目和术语，让识别更准确。语音 Agent 也会参考这些内容。",
                "Save names, projects, and terms for more accurate transcription. Voice Agent uses them too."
            )
        ) {
            HStack(spacing: 8) {
                Button {
                    showingImport = true
                } label: {
                    Label(appState.text("从文本导入…", "Import from Text…"), systemImage: "doc.on.clipboard")
                }
                .buttonStyle(HoverFillButtonStyle())

                Button {
                    showingAdd = true
                } label: {
                    Label(appState.text("添加…", "Add…"), systemImage: "plus")
                }
                .buttonStyle(HoverFillButtonStyle(prominent: true))
            }
        }
    }

    private var entityList: some View {
        let entities = filteredEntities
        return VStack(spacing: 0) {
            if !appState.knowledgeEntities.isEmpty {
                searchField
                listSummary(count: entities.count)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(entities) { entity in
                        EntityRow(entity: entity) {
                            pendingDeletion = entity
                        } onEdit: {
                            editingEntity = entity
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 32)
            }
            .overlay {
                if entities.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, minHeight: 180)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if appState.knowledgeEntities.isEmpty {
            ContentUnavailableView {
                Label(appState.text("知识里还没有内容", "Nothing in Knowledge yet"), systemImage: "books.vertical")
            } description: {
                Text(appState.text(
                    "添加常用的人名、项目和术语，让识别更准确。",
                    "Add names, projects, and terms for more accurate transcription."
                ))
            } actions: {
                Button(appState.text("添加…", "Add…")) { showingAdd = true }
                    .buttonStyle(HoverFillButtonStyle())
            }
        } else if !query.isEmpty {
            ContentUnavailableView(
                appState.text("没有找到匹配的条目", "No matching items"),
                systemImage: "magnifyingglass",
                description: Text(appState.text("换个关键词或分类试试。", "Try a different search or category."))
            )
        } else {
            ContentUnavailableView(
                appState.text("这个分类还没有条目", "No items in this category"),
                systemImage: filter.symbol,
                description: Text(appState.text("切换到“全部”查看其他条目。", "Choose All to see your other items."))
            )
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(KukuColor.stone)
            TextField(appState.text("搜索名称、别名或备注", "Search names, aliases, or notes"), text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(KukuColor.stone)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(appState.text("清除搜索", "Clear search"))
                .help(appState.text("清除搜索", "Clear search"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: KukuLayout.controlHeight)
        .background(KukuColor.surfaceStrong, in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous).stroke(KukuColor.line, lineWidth: 1))
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private func listSummary(count: Int) -> some View {
        HStack(spacing: 10) {
            Spacer()
            Text(appState.text("\(count) 条", count == 1 ? "1 item" : "\(count) items"))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(KukuColor.stone)
            if filter != .all || !search.isEmpty {
                Button(appState.text("清除筛选", "Clear Filters")) {
                    withAnimation(Motion.snappy) {
                        filter = .all
                        search = ""
                    }
                }
                .buttonStyle(TintButtonStyle())
            }
        }
        .frame(minHeight: KukuLayout.controlHeight)
        .padding(.bottom, 8)
    }

    private func relationshipCount(for entity: KnowledgeEntity) -> Int {
        appState.knowledgeRelationships.filter { $0.fromEntityID == entity.id || $0.toEntityID == entity.id }.count
    }

    private func deletionMessage(for entity: KnowledgeEntity) -> String {
        let count = relationshipCount(for: entity)
        guard count > 0 else {
            return appState.text("删除后无法恢复。", "This can’t be undone.")
        }
        return appState.text(
            "相关的 \(count) 条关系也会一并删除，且无法恢复。",
            count == 1
                ? "This also removes 1 related relationship. This can’t be undone."
                : "This also removes \(count) related relationships. This can’t be undone."
        )
    }

    private func delete(_ entity: KnowledgeEntity) {
        appState.knowledgeRelationships.removeAll { $0.fromEntityID == entity.id || $0.toEntityID == entity.id }
        appState.knowledgeEntities.removeAll { $0.id == entity.id }
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
                .background(entity.type.color.opacity(0.11), in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(entity.name)
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(entity.type.title(appState))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(entity.type.textColor)
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
                    Text(appState.text(
                        "别名：" + entity.aliases.joined(separator: "、"),
                        "Aliases: " + entity.aliases.joined(separator: ", ")
                    ))
                        .font(.system(size: 11))
                        .foregroundStyle(KukuColor.stone)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text(entity.source.title(appState))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(KukuColor.stone.opacity(0.82))
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                Button(action: onEdit) {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                        Text(appState.text("编辑…", "Edit…"))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .buttonStyle(TintButtonStyle())
                .frame(width: 78, height: 32)
                .accessibilityLabel(appState.text("编辑“\(entity.name)”", "Edit “\(entity.name)”"))

                Menu {
                    Button(appState.text("删除…", "Delete…"), role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(KukuColor.stone)
                        .frame(width: 30, height: 32)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .accessibilityLabel(appState.text("更多操作", "More actions"))
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
        .contextMenu {
            Button(appState.text("编辑…", "Edit…"), action: onEdit)
            Divider()
            Button(appState.text("删除…", "Delete…"), role: .destructive, action: onDelete)
        }
    }
}

/// Caption on the leading side of a sheet footer: a quiet hint or an inline error.
private struct SheetNote: View {
    let text: String
    var isError = false

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(isError ? KukuColor.coral : KukuColor.stone)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
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
    @State private var note: SheetNote?

    init(entity: KnowledgeEntity? = nil) {
        self.entity = entity
        _name = State(initialValue: entity?.name ?? "")
        _type = State(initialValue: entity?.type ?? .term)
        _detail = State(initialValue: entity?.detail ?? "")
        _aliases = State(initialValue: entity?.aliases.joined(separator: "、") ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            KukuSheetHeader(
                title: entity == nil ? appState.text("添加到知识", "Add to Knowledge") : appState.text("编辑条目", "Edit Item"),
                description: appState.text("让 SayKuku 认识这个名称。", "Teach SayKuku this name.")
            ) {
                KukuSheetIcon(symbol: entity == nil ? "plus" : "pencil")
            }

            Divider().opacity(0.6)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        formFieldLabel(appState.text("名称", "Name"), required: true)
                        KukuFormInput(
                            text: $name,
                            prompt: appState.text("输入名称", "Enter a name"),
                            autoFocus: entity == nil,
                            onSubmit: { save() }
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
                                    classifying ? appState.text("正在识别…", "Suggesting…") : appState.text("自动识别类别", "Suggest Category"),
                                    systemImage: classifying ? "hourglass" : "sparkles"
                                )
                            }
                            .buttonStyle(TintButtonStyle())
                            .disabled(!canSave || classifying)
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 148, maximum: 220), spacing: 8)], spacing: 8) {
                            ForEach(EntityType.allCases) { option in
                                categoryOption(option)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        formFieldLabel(appState.text("备注", "Notes"))
                        KukuFormInput(
                            text: $detail,
                            prompt: appState.text("例如：团队负责人、常用项目名", "e.g. Team lead, main project"),
                            multiline: true
                        )
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        formFieldLabel(appState.text("别名", "Aliases"))
                        KukuFormInput(
                            text: $aliases,
                            prompt: appState.text("多个别名用顿号或逗号分隔", "Separate aliases with commas")
                        )
                        Text(appState.text("别名同样能被识别", "Aliases are recognized too"))
                            .font(.system(size: 10))
                            .foregroundStyle(KukuColor.stone)
                    }
                }
                .padding(20)
            }
            .frame(maxHeight: .infinity)

            Divider().opacity(0.6)

            HStack(spacing: 10) {
                if let footerNote { footerNote }
                Spacer(minLength: 12)
                Button(appState.text("取消", "Cancel")) { dismiss() }
                    .buttonStyle(HoverFillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(entity == nil ? appState.text("添加", "Add") : appState.text("保存", "Save")) { save() }
                    .buttonStyle(HoverFillButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave || classifying)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 560, height: 540)
        .background(KukuColor.canvas)
        .onChange(of: name) { note = nil }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// An explicit note wins; otherwise explain the disabled primary button.
    private var footerNote: SheetNote? {
        if let note { return note }
        guard !canSave else { return nil }
        return SheetNote(text: entity == nil
            ? appState.text("填写名称后即可添加", "Enter a name to continue")
            : appState.text("填写名称后即可保存", "Enter a name to save"))
    }

    private func categoryOption(_ option: EntityType) -> some View {
        let isSelected = type == option
        return Button {
            type = option
        } label: {
            HStack(spacing: 8) {
                Image(systemName: option.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(option.color)
                    .frame(width: 25, height: 25)
                    .background(option.color.opacity(0.11), in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous))
                Text(option.title(appState))
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? KukuColor.ink : KukuColor.stone)
                Spacer(minLength: 2)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(KukuColor.coral)
                        .font(.system(size: 13))
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 42)
            .background(isSelected ? option.color.opacity(0.10) : KukuColor.highlight.opacity(0.52), in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)
                    .stroke(isSelected ? option.color.opacity(0.35) : KukuColor.line, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
        guard canSave, !classifying else { return }
        let editedAliases = aliases
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "、" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let error: KnowledgeSaveError?
        if let entity {
            error = appState.updateKnowledge(id: entity.id, name: name, type: type, detail: detail, aliases: editedAliases)
        } else {
            error = appState.addKnowledge(name: name, type: type, detail: detail, aliases: editedAliases)
        }
        // The sheet covers the toast area, so failures stay in the footer.
        if let error {
            note = SheetNote(text: error.message(appState), isError: true)
            return
        }
        dismiss()
    }

    private func classify() {
        classifying = true
        note = nil
        Task {
            do {
                let suggested = try await appState.suggestEntityType(for: name)
                type = suggested
                if suggested == .unknown {
                    note = SheetNote(text: appState.text("没能判断类别，请手动选择", "Couldn’t suggest a category. Pick one below."))
                }
            } catch {
                note = SheetNote(text: appState.localizedError(error), isError: true)
            }
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
                    .frame(height: 20)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textFieldStyle(.plain)
        .focused($isFocused)
        .onSubmit { onSubmit?() }
        .padding(.horizontal, 12)
        .padding(.vertical, multiline ? 9 : 0)
        .frame(maxWidth: .infinity, minHeight: multiline ? 52 : 40, alignment: multiline ? .topLeading : .center)
        .background(
            isFocused ? KukuColor.surfaceStrong : KukuColor.highlight.opacity(0.66),
            in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous)
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
    @State private var reviewing = false
    @State private var source = ""
    @State private var selected = Set<UUID>()
    @State private var analysis: KnowledgeAnalysis?
    @State private var analyzing = false
    @State private var errorMessage: String?
    @State private var confirmingDiscard = false

    /// Whether the analysis produced anything the user can import.
    private var hasResults: Bool {
        guard let analysis else { return false }
        return analysis.candidates.contains { $0.status != .ignored } || !analysis.relationships.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            KukuSheetHeader(
                title: reviewing
                    ? appState.text("选择要导入的内容", "Choose What to Import")
                    : appState.text("从文本导入", "Import from Text"),
                description: reviewing
                    ? appState.text("检查建议，选择要保存到知识的内容。", "Review the suggestions and choose what to save to Knowledge.")
                    : appState.text("粘贴一段文字，SayKuku 会找出其中的人名、项目和术语。", "Paste some text and SayKuku will pick out names, projects, and terms.")
            ) {
                KukuSheetIcon(symbol: "doc.on.clipboard")
            }

            Divider().opacity(0.6)

            Group {
                if !reviewing {
                    sourceEditor
                } else if hasResults {
                    reviewList
                } else {
                    ContentUnavailableView(
                        appState.text("没有找到可以保存的名称或术语", "No names or terms found"),
                        systemImage: "text.magnifyingglass",
                        description: Text(appState.text("试试包含人名、项目或产品名的文本。", "Try text that mentions people, projects, or products."))
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.6)

            footer
        }
        .frame(width: 640, height: 540)
        .background(KukuColor.canvas)
        .overlay {
            if analyzing {
                ZStack {
                    Color.black.opacity(0.08)
                    ProgressView(appState.text("正在分析…", "Analyzing…"))
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: KukuLayout.radiusMedium, style: .continuous))
                }
            }
        }
        .onChange(of: source) { errorMessage = nil }
        .confirmationDialog(
            appState.text("放弃这次导入？", "Discard this import?"),
            isPresented: $confirmingDiscard,
            titleVisibility: .visible
        ) {
            Button(appState.text("放弃", "Discard"), role: .destructive) { dismiss() }
            Button(appState.text("继续导入", "Keep Importing"), role: .cancel) { }
        } message: {
            Text(appState.text("分析结果不会保存。", "The analysis results won’t be saved."))
        }
    }

    private var sourceEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $source)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(KukuColor.highlight.opacity(0.62), in: RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: KukuLayout.radiusSmall, style: .continuous).stroke(KukuColor.line, lineWidth: 1))
                .accessibilityLabel(appState.text("要导入的文本", "Text to import"))
            Label(appState.text(
                "分析前会先去掉常见格式的电话号码、邮箱、身份证号和银行卡号，以及标注为地址的内容",
                "Before analysis, SayKuku removes phone numbers, emails, and ID and bank card numbers in common formats, plus labeled addresses"
            ), systemImage: "eye.slash")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(KukuColor.stone)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
    }

    private var reviewList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(analysis?.candidates ?? []) { candidate in
                    let ignored = candidate.status == .ignored
                    ImportRow(
                        title: ignored ? appState.text("已过滤的敏感信息", "Filtered sensitive info") : candidate.entity.name,
                        badge: badge(for: candidate),
                        badgeColor: candidate.status.color,
                        detail: KnowledgePipeline.displayEvidence(candidate.evidence),
                        trailing: ignored ? nil : candidate.entity.type.title(appState),
                        isSelected: selected.contains(candidate.id),
                        isIgnored: ignored
                    ) {
                        toggle(candidate.id)
                    }
                }
                if let relationships = analysis?.relationships, !relationships.isEmpty {
                    Text(appState.text("关系", "Relationships"))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(KukuColor.stone)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                    ForEach(relationships) { candidate in
                        let relationship = candidate.relationship
                        ImportRow(
                            title: "\(relationship.from) \(relationship.type.title(appState)) \(relationship.to)",
                            badge: candidate.status.title(appState),
                            badgeColor: candidate.status.color,
                            detail: KnowledgePipeline.displayEvidence(relationship.evidence),
                            isSelected: selected.contains(candidate.id)
                        ) {
                            toggle(candidate.id)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let footerNote { footerNote }
            Spacer(minLength: 12)
            Button(appState.text("取消", "Cancel")) { cancel() }
                .buttonStyle(HoverFillButtonStyle())
                .keyboardShortcut(.cancelAction)
            if reviewing && hasResults {
                Button(appState.text("返回", "Back")) { goBack() }
                    .buttonStyle(HoverFillButtonStyle())
            }
            primaryButton
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var footerNote: SheetNote? {
        if let errorMessage { return SheetNote(text: errorMessage, isError: true) }
        if !reviewing {
            return SheetNote(text: appState.text(
                "文本会发送给 Qwen 分析，SayKuku 不保存原文",
                "Text is sent to Qwen for analysis. SayKuku doesn’t keep a copy."
            ))
        }
        guard hasResults else { return nil }
        return SheetNote(text: appState.text("已选 \(selected.count) 条", "\(selected.count) selected"))
    }

    @ViewBuilder
    private var primaryButton: some View {
        if !reviewing {
            // Return belongs to the text editor, so analysis uses ⌘Return.
            Button(appState.text("分析", "Analyze")) { analyze() }
                .buttonStyle(HoverFillButtonStyle(prominent: true))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || analyzing)
        } else if hasResults {
            let count = selected.count
            Button(appState.text("导入 \(count) 条", count == 1 ? "Import 1 Item" : "Import \(count) Items")) { importSelection() }
                .buttonStyle(HoverFillButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
        } else {
            Button(appState.text("返回修改", "Edit Text")) { goBack() }
                .buttonStyle(HoverFillButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
        }
    }

    private func badge(for candidate: ImportCandidate) -> String {
        guard candidate.status == .conflict,
              let match = appState.knowledgeEntities.first(where: { $0.id == candidate.matchedEntityID }) else {
            return candidate.status.title(appState)
        }
        return appState.text("可能与“\(match.name)”重复", "May duplicate “\(match.name)”")
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    private func cancel() {
        if reviewing && !selected.isEmpty {
            confirmingDiscard = true
        } else {
            dismiss()
        }
    }

    private func goBack() {
        errorMessage = nil
        withAnimation(Motion.snappy) { reviewing = false }
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
                withAnimation(Motion.panel) { reviewing = true }
            } catch {
                errorMessage = appState.localizedError(error)
            }
            analyzing = false
        }
    }

    private func importSelection() {
        guard let analysis, !selected.isEmpty else { return }
        let count = selected.count
        appState.commitKnowledge(analysis, selectedIDs: selected)
        appState.showToast(
            appState.text("已导入 \(count) 条到知识", count == 1 ? "Imported 1 item to Knowledge" : "Imported \(count) items to Knowledge"),
            symbol: "checkmark.seal.fill"
        )
        dismiss()
    }
}

/// Selectable row shared by entity and relationship suggestions in the import review.
private struct ImportRow: View {
    let title: String
    let badge: String
    let badgeColor: Color
    let detail: String
    var trailing: String? = nil
    let isSelected: Bool
    var isIgnored = false
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: KukuLayout.radiusMedium, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: isIgnored ? "minus.circle.fill" : (isSelected ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? KukuColor.coral : KukuColor.stone)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(badge)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(badgeColor)
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .frame(height: 18)
                            .background(badgeColor.opacity(0.1), in: Capsule())
                    }
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(KukuColor.stone)
                    }
                }
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(KukuColor.stone)
                }
            }
            .padding(14)
            .background(KukuColor.highlight.opacity(0.54), in: shape)
            .overlay(shape.stroke(isSelected ? KukuColor.coral.opacity(0.2) : KukuColor.line, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(isIgnored)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
        case .manual: appState.text("手动添加", "Added manually")
        case .importText: appState.text("从文本导入", "Imported from text")
        case .correction: appState.text("来自纠正建议", "From a correction")
        }
    }
}

private extension ImportStatus {
    /// Badge text color, so it uses the text-safe greens and ambers.
    var color: Color {
        switch self {
        case .new: KukuColor.mintText
        case .merge: Color(red: 0.34, green: 0.50, blue: 0.75)
        case .conflict: KukuColor.amberText
        case .ignored: KukuColor.stone
        }
    }
}
