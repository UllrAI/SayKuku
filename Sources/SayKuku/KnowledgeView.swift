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
            KukuDivider(inset: 0)

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
            HStack(spacing: KukuSpacing.sm) {
                Button {
                    showingImport = true
                } label: {
                    Label(appState.text("从文本导入…", "Import from Text…"), systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.kukuSecondary)

                Button {
                    showingAdd = true
                } label: {
                    Label(appState.text("添加…", "Add…"), systemImage: "plus")
                }
                .buttonStyle(.kukuPrimary)
            }
        }
    }

    private var entityList: some View {
        let entities = filteredEntities
        return VStack(spacing: 0) {
            if !appState.knowledgeEntities.isEmpty {
                searchBar(count: entities.count)
            }

            ScrollView {
                LazyVStack(spacing: KukuLayout.listSpacing) {
                    ForEach(entities) { entity in
                        EntityRow(entity: entity) {
                            pendingDeletion = entity
                        } onEdit: {
                            editingEntity = entity
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, KukuLayout.contentBottom)
            }
            .overlay {
                if entities.isEmpty {
                    emptyState
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if appState.knowledgeEntities.isEmpty {
            KukuEmptyState(
                title: appState.text("知识里还没有内容", "Nothing in Knowledge yet"),
                symbol: "books.vertical",
                message: appState.text(
                    "添加常用的人名、项目和术语，让识别更准确。",
                    "Add names, projects, and terms for more accurate transcription."
                )
            ) {
                Button(appState.text("添加…", "Add…")) { showingAdd = true }
                    .buttonStyle(.kukuSecondary)
            }
        } else if !query.isEmpty {
            KukuEmptyState(
                title: appState.text("没有找到匹配的条目", "No matching items"),
                symbol: "magnifyingglass",
                message: appState.text("换个关键词或分类试试。", "Try a different search or category.")
            )
        } else {
            KukuEmptyState(
                title: appState.text("这个分类还没有条目", "No items in this category"),
                symbol: filter.symbol,
                message: appState.text("切换到“全部”查看其他条目。", "Choose All to see your other items.")
            )
        }
    }

    private func searchBar(count: Int) -> some View {
        HStack(spacing: KukuSpacing.sm) {
            KukuSearchField(
                prompt: appState.text("搜索名称、别名或备注", "Search names, aliases, or notes"),
                clearLabel: appState.text("清除搜索", "Clear search"),
                text: $search,
                width: nil
            )
            Text(appState.text("\(count) 条", count == 1 ? "1 item" : "\(count) items"))
                .font(.kuku(.subheadline))
                .monospacedDigit()
                .foregroundStyle(KukuColor.textSecondary)
                .fixedSize()
            if filter != .all || !search.isEmpty {
                Button(appState.text("清除筛选", "Clear Filters")) {
                    withAnimation(Motion.snappy) {
                        filter = .all
                        search = ""
                    }
                }
                .buttonStyle(.kuku(.secondary, size: .small))
            }
        }
        .padding(.top, KukuLayout.contentTop)
        .padding(.bottom, KukuSpacing.sm)
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

    var body: some View {
        HStack(spacing: KukuSpacing.md) {
            KukuIconTile(symbol: entity.type.symbol)
            VStack(alignment: .leading, spacing: KukuSpacing.xxs) {
                HStack(spacing: KukuSpacing.sm) {
                    Text(entity.name)
                        .font(.kuku(.headline))
                        .foregroundStyle(KukuColor.textPrimary)
                    KukuBadge(text: entity.type.title(appState))
                }
                Group {
                    if !entity.detail.isEmpty {
                        Text(entity.detail)
                    } else if !entity.aliases.isEmpty {
                        Text(appState.text(
                            "别名：" + entity.aliases.joined(separator: "、"),
                            "Aliases: " + entity.aliases.joined(separator: ", ")
                        ))
                    } else {
                        Text(entity.source.title(appState))
                    }
                }
                .font(.kuku(.subheadline))
                .foregroundStyle(KukuColor.textSecondary)
                .lineLimit(1)
            }
            Spacer(minLength: KukuSpacing.md)
            HStack(spacing: KukuSpacing.xs) {
                Button(action: onEdit) {
                    HStack(spacing: KukuSpacing.iconText) {
                        Image(systemName: "pencil")
                        Text(appState.text("编辑…", "Edit…"))
                    }
                }
                .buttonStyle(.kukuSecondary)
                .fixedSize()
                .accessibilityLabel(appState.text("编辑“\(entity.name)”", "Edit “\(entity.name)”"))

                Menu {
                    Button(appState.text("删除…", "Delete…"), role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(KukuColor.textSecondary)
                        // Same hit area as a regular KukuIconButton.
                        .frame(width: 28, height: KukuLayout.controlHeight)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .accessibilityLabel(appState.text("更多操作", "More actions"))
                .help(appState.text("更多操作", "More actions"))
            }
            // Fixed action column keeps the edit buttons aligned from row to row.
            .frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, KukuSpacing.lg)
        .padding(.vertical, KukuSpacing.md)
        .frame(maxWidth: .infinity, minHeight: KukuLayout.rowMinHeightWithCaption, alignment: .leading)
        .kukuInteractiveSurface()
        .contextMenu {
            Button(appState.text("编辑…", "Edit…"), action: onEdit)
            Divider()
            Button(appState.text("删除…", "Delete…"), role: .destructive, action: onDelete)
        }
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
    @State private var note: KukuSheetNote?

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

            KukuDivider(inset: 0)

            ScrollView {
                VStack(alignment: .leading, spacing: KukuSpacing.lg) {
                    VStack(alignment: .leading, spacing: KukuSpacing.sm) {
                        KukuFieldLabel(text: appState.text("名称", "Name"), isRequired: true)
                        KukuTextField(
                            prompt: appState.text("输入名称", "Enter a name"),
                            text: $name,
                            autoFocus: entity == nil,
                            onSubmit: { save() }
                        )
                    }

                    VStack(alignment: .leading, spacing: KukuSpacing.sm) {
                        HStack(alignment: .firstTextBaseline) {
                            KukuFieldLabel(text: appState.text("类别", "Category"), isRequired: true)
                            Spacer()
                            Button {
                                classify()
                            } label: {
                                Label(
                                    classifying ? appState.text("正在识别…", "Suggesting…") : appState.text("自动识别类别", "Suggest Category"),
                                    systemImage: classifying ? "hourglass" : "sparkles"
                                )
                            }
                            .buttonStyle(.kuku(.secondary, size: .small))
                            .disabled(!canSave || classifying)
                        }

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 148, maximum: 220), spacing: KukuSpacing.sm)],
                            spacing: KukuSpacing.sm
                        ) {
                            ForEach(EntityType.allCases) { option in
                                categoryOption(option)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: KukuSpacing.sm) {
                        KukuFieldLabel(text: appState.text("备注", "Notes"))
                        KukuTextField(
                            prompt: appState.text("例如：团队负责人、常用项目名", "e.g. Team lead, main project"),
                            text: $detail,
                            multiline: true
                        )
                    }

                    VStack(alignment: .leading, spacing: KukuSpacing.sm) {
                        KukuFieldLabel(text: appState.text("别名", "Aliases"))
                        KukuTextField(
                            prompt: appState.text("多个别名用顿号或逗号分隔", "Separate aliases with commas"),
                            text: $aliases
                        )
                        Text(appState.text("别名同样能被识别", "Aliases are recognized too"))
                            .font(.kuku(.subheadline))
                            .foregroundStyle(KukuColor.textSecondary)
                    }
                }
                .padding(.horizontal, KukuLayout.sheetPadding)
                .padding(.vertical, KukuSpacing.xl)
            }
            .frame(maxHeight: .infinity)

            KukuDivider(inset: 0)

            KukuSheetFooter(note: footerNote) {
                Button(appState.text("取消", "Cancel")) { dismiss() }
                    .buttonStyle(.kukuSecondary)
                    .keyboardShortcut(.cancelAction)
                Button(entity == nil ? appState.text("添加", "Add") : appState.text("保存", "Save")) { save() }
                    .buttonStyle(.kukuPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave || classifying)
            }
        }
        .frame(width: KukuLayout.sheetWidth, height: KukuLayout.sheetHeight)
        .background(KukuColor.canvas)
        .onChange(of: name) { note = nil }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// An explicit note wins; otherwise explain the disabled primary button.
    private var footerNote: KukuSheetNote? {
        if let note { return note }
        guard !canSave else { return nil }
        return KukuSheetNote(text: entity == nil
            ? appState.text("填写名称后即可添加", "Enter a name to continue")
            : appState.text("填写名称后即可保存", "Enter a name to save"))
    }

    private func categoryOption(_ option: EntityType) -> some View {
        let isSelected = type == option
        return Button {
            type = option
        } label: {
            HStack(spacing: KukuSpacing.sm) {
                KukuSelectionIndicator(style: .radio, isSelected: isSelected)
                Image(systemName: option.symbol)
                    .font(.kukuIcon(.regular))
                    .foregroundStyle(KukuColor.textSecondary)
                Text(option.title(appState))
                    .font(.kuku(.callout, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? KukuColor.textPrimary : KukuColor.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, KukuSpacing.md)
            // Taller than a control so the grid reads as a set of choices.
            .frame(height: 40)
            .kukuInteractiveSurface(isSelected: isSelected, radius: KukuLayout.radiusSmall)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
            note = KukuSheetNote(text: error.message(appState), isError: true)
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
                    note = KukuSheetNote(text: appState.text("没能判断类别，请手动选择", "Couldn’t suggest a category. Pick one below."))
                }
            } catch {
                note = KukuSheetNote(text: appState.localizedError(error), isError: true)
            }
            classifying = false
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
    @FocusState private var sourceFocused: Bool

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

            KukuDivider(inset: 0)

            Group {
                if !reviewing {
                    sourceEditor
                } else if hasResults {
                    reviewList
                } else {
                    KukuEmptyState(
                        title: appState.text("没有找到可以保存的名称或术语", "No names or terms found"),
                        symbol: "text.magnifyingglass",
                        message: appState.text("试试包含人名、项目或产品名的文本。", "Try text that mentions people, projects, or products.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            KukuDivider(inset: 0)

            footer
        }
        .frame(width: KukuLayout.sheetWideWidth, height: KukuLayout.sheetHeight)
        .background(KukuColor.canvas)
        .overlay {
            if analyzing {
                ZStack {
                    KukuColor.fill
                    ProgressView(appState.text("正在分析…", "Analyzing…"))
                        .padding(KukuSpacing.lg)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: KukuLayout.radiusMedium, style: .continuous))
                        .kukuShadow(.floating)
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
        VStack(alignment: .leading, spacing: KukuSpacing.md) {
            TextEditor(text: $source)
                .font(.kuku(.body))
                .scrollContentBackground(.hidden)
                .focused($sourceFocused)
                .padding(KukuSpacing.md)
                .kukuFieldChrome(isFocused: sourceFocused)
                .accessibilityLabel(appState.text("要导入的文本", "Text to import"))
            Label(appState.text(
                "分析前会先去掉常见格式的电话号码、邮箱、身份证号和银行卡号，以及标注为地址的内容",
                "Before analysis, SayKuku removes phone numbers, emails, and ID and bank card numbers in common formats, plus labeled addresses"
            ), systemImage: "eye.slash")
                .font(.kuku(.subheadline))
                .foregroundStyle(KukuColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(KukuLayout.sheetPadding)
    }

    private var reviewList: some View {
        ScrollView {
            VStack(spacing: KukuLayout.listSpacing) {
                ForEach(analysis?.candidates ?? []) { candidate in
                    let ignored = candidate.status == .ignored
                    ImportRow(
                        title: ignored ? appState.text("已过滤的敏感信息", "Filtered sensitive info") : candidate.entity.name,
                        badge: badge(for: candidate),
                        badgeTone: candidate.status.tone,
                        badgeSymbol: candidate.status.symbol,
                        detail: KnowledgePipeline.displayEvidence(candidate.evidence),
                        trailing: ignored ? nil : candidate.entity.type.title(appState),
                        isSelected: selected.contains(candidate.id),
                        isIgnored: ignored
                    ) {
                        toggle(candidate.id)
                    }
                }
                if let relationships = analysis?.relationships, !relationships.isEmpty {
                    SectionEyebrow(text: appState.text("关系", "Relationships"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, KukuSpacing.sm)
                    ForEach(relationships) { candidate in
                        let relationship = candidate.relationship
                        ImportRow(
                            title: "\(relationship.from) \(relationship.type.title(appState)) \(relationship.to)",
                            badge: candidate.status.title(appState),
                            badgeTone: candidate.status.tone,
                            badgeSymbol: candidate.status.symbol,
                            detail: KnowledgePipeline.displayEvidence(relationship.evidence),
                            isSelected: selected.contains(candidate.id)
                        ) {
                            toggle(candidate.id)
                        }
                    }
                }
            }
            .padding(KukuLayout.sheetPadding)
        }
    }

    private var footer: some View {
        KukuSheetFooter(note: footerNote) {
            Button(appState.text("取消", "Cancel")) { cancel() }
                .buttonStyle(.kukuSecondary)
                .keyboardShortcut(.cancelAction)
            if reviewing && hasResults {
                Button(appState.text("返回", "Back")) { goBack() }
                    .buttonStyle(.kukuSecondary)
            }
            primaryButton
        }
    }

    private var footerNote: KukuSheetNote? {
        if let errorMessage { return KukuSheetNote(text: errorMessage, isError: true) }
        if !reviewing {
            return KukuSheetNote(text: appState.text(
                "文本会发送给 Qwen 分析，SayKuku 不保存原文",
                "Text is sent to Qwen for analysis. SayKuku doesn’t keep a copy."
            ))
        }
        guard hasResults else { return nil }
        return KukuSheetNote(text: appState.text("已选 \(selected.count) 条", "\(selected.count) selected"))
    }

    @ViewBuilder
    private var primaryButton: some View {
        if !reviewing {
            // Return belongs to the text editor, so analysis uses ⌘Return.
            Button(appState.text("分析", "Analyze")) { analyze() }
                .buttonStyle(.kukuPrimary)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || analyzing)
        } else if hasResults {
            let count = selected.count
            Button(appState.text("导入 \(count) 条", count == 1 ? "Import 1 Item" : "Import \(count) Items")) { importSelection() }
                .buttonStyle(.kukuPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
        } else {
            Button(appState.text("返回修改", "Edit Text")) { goBack() }
                .buttonStyle(.kukuPrimary)
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
    let badgeTone: KukuStatusTone
    let badgeSymbol: String
    let detail: String
    var trailing: String? = nil
    let isSelected: Bool
    var isIgnored = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: KukuSpacing.md) {
                if isIgnored {
                    Image(systemName: "minus.circle.fill")
                        .font(.kukuIcon(.medium))
                        .foregroundStyle(KukuColor.textTertiary)
                        .accessibilityHidden(true)
                } else {
                    KukuSelectionIndicator(style: .checkbox, isSelected: isSelected)
                }
                VStack(alignment: .leading, spacing: KukuSpacing.xs) {
                    HStack(spacing: KukuSpacing.sm) {
                        Text(title)
                            .font(.kuku(.headline))
                            .foregroundStyle(KukuColor.textPrimary)
                        KukuBadge(text: badge, tone: badgeTone, symbol: badgeSymbol)
                    }
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.kuku(.subheadline))
                            .foregroundStyle(KukuColor.textSecondary)
                    }
                }
                Spacer(minLength: KukuSpacing.sm)
                if let trailing {
                    Text(trailing)
                        .font(.kuku(.caption))
                        .foregroundStyle(KukuColor.textSecondary)
                }
            }
            .padding(KukuLayout.cardPadding)
            .kukuInteractiveSurface(isSelected: isSelected)
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
    /// Only a possible duplicate needs attention; the icon tells the other states apart.
    var tone: KukuStatusTone {
        self == .conflict ? .warning : .neutral
    }

    var symbol: String {
        switch self {
        case .new: "plus.circle"
        case .merge: "arrow.triangle.merge"
        case .conflict: "exclamationmark.triangle.fill"
        case .ignored: "eye.slash"
        }
    }
}
