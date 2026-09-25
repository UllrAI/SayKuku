import SwiftUI

struct MemoryView: View {
    @Environment(AppState.self) private var appState
    @Binding var search: String
    /// `nil` shows every type.
    @Binding var filter: EntityType?
    @State private var showingImport = false
    @State private var showingAdd = false
    @State private var editingEntity: MemoryEntity?
    @State private var pendingDeletion: MemoryEntity?
    @State private var selection: MemoryEntity.ID?
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool

    /// "All" first, then one tab per type.
    private static let tabs: [EntityType?] = [nil] + EntityType.allCases.map(Optional.some)

    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Suggestions sit above the full list only; a search or category narrows the page to saved items.
    private var showsSuggestions: Bool {
        filter == nil && query.isEmpty && !appState.data.pendingCorrections.isEmpty
    }

    private var filteredEntities: [MemoryEntity] {
        let text = query
        return appState.data.memoryEntities.filter { entity in
            (filter == nil || entity.type == filter) && (text.isEmpty || Self.entity(entity, matches: text))
        }.sorted { $0.createdAt > $1.createdAt }
    }

    private static func entity(_ entity: MemoryEntity, matches text: String) -> Bool {
        entity.name.localizedCaseInsensitiveContains(text)
            || entity.detail.localizedCaseInsensitiveContains(text)
            || entity.aliases.contains { $0.localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            KukuPageTabs(
                items: Self.tabs,
                selection: $filter,
                title: { $0?.pluralTitle ?? localized("All") }
            )
            KukuDivider(inset: 0)

            KukuPageContent {
                entityList
            }
        }
        .sheet(isPresented: $showingImport) {
            MemoryImportSheet()
        }
        .sheet(isPresented: $showingAdd) {
            MemoryFormSheet()
        }
        .sheet(item: $editingEntity) { entity in
            MemoryFormSheet(entity: entity)
        }
        .confirmationDialog(
            pendingDeletion.map { localized("Delete “\($0.name)”?") } ?? "",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { entity in
            Button(localized("Delete"), role: .destructive) { delete(entity) }
            Button(localized("Cancel"), role: .cancel) { }
        } message: { _ in
            Text(localized("This can’t be undone."))
        }
    }

    private var header: some View {
        ScreenHeader(
            title: localized("Memory"),
            subtitle: localized("Names, projects and terms SayKuku remembers. Delete one and it forgets.")
        ) {
            HStack(spacing: KukuSpacing.sm) {
                Button {
                    showingImport = true
                } label: {
                    Label(localized("Import from Text…"), systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.kukuSecondary)

                Button {
                    showingAdd = true
                } label: {
                    Label(localized("Add…"), systemImage: "plus")
                }
                .buttonStyle(.kukuPrimary)
            }
        }
    }

    private var entityList: some View {
        let entities = filteredEntities
        return VStack(spacing: 0) {
            if !appState.data.memoryEntities.isEmpty {
                searchBar(count: entities.count)
            }

            List(selection: $selection) {
                if showsSuggestions {
                    // Untagged, so the list's selection and keyboard commands skip it.
                    CorrectionSuggestions()
                        .kukuListRow(EdgeInsets(
                            top: appState.data.memoryEntities.isEmpty ? KukuLayout.contentTop : 0,
                            leading: 0,
                            bottom: KukuLayout.sectionSpacing,
                            trailing: 0
                        ))
                }
                ForEach(entities) { entity in
                    EntityRow(entity: entity, isSelected: selection == entity.id) {
                        pendingDeletion = entity
                    } onEdit: {
                        editingEntity = entity
                    }
                    .tag(entity.id)
                    .kukuListRow(EdgeInsets(top: 0, leading: 0, bottom: KukuLayout.listSpacing, trailing: 0))
                }
            }
            .kukuList()
            .contentMargins(.bottom, KukuLayout.contentBottom, for: .scrollContent)
            .focused($listFocused)
            .onDeleteCommand {
                if let entity = selectedEntity(in: entities) { pendingDeletion = entity }
            }
            .onCopyCommand {
                guard let entity = selectedEntity(in: entities) else { return [] }
                return [NSItemProvider(object: entity.name as NSString)]
            }
            // A key handler on the focused list: a default-action button would also fire
            // while typing in the search field.
            .onKeyPress(.return) {
                guard let entity = selectedEntity(in: entities) else { return .ignored }
                editingEntity = entity
                return .handled
            }
            .overlay {
                if entities.isEmpty && !showsSuggestions {
                    emptyState
                }
            }
        }
    }

    private func selectedEntity(in entities: [MemoryEntity]) -> MemoryEntity? {
        entities.first { $0.id == selection }
    }

    @ViewBuilder
    private var emptyState: some View {
        if appState.data.memoryEntities.isEmpty {
            KukuEmptyState(
                title: localized("Nothing remembered yet"),
                symbol: "books.vertical",
                message: localized("Add names, projects, and terms for more accurate transcription.")
            ) {
                Button(localized("Add…")) { showingAdd = true }
                    .buttonStyle(.kukuSecondary)
            }
        } else if !query.isEmpty {
            KukuEmptyState(
                title: localized("No matching items"),
                symbol: "magnifyingglass",
                message: localized("Try a different search or category.")
            )
        } else {
            KukuEmptyState(
                title: localized("No items in this category"),
                symbol: filter?.symbol ?? "books.vertical",
                message: localized("Choose All to see your other items.")
            )
        }
    }

    private func searchBar(count: Int) -> some View {
        HStack(spacing: KukuSpacing.sm) {
            KukuSearchField(
                prompt: localized("Search names, aliases, or clues"),
                clearLabel: localized("Clear search"),
                text: $search,
                width: nil,
                focus: $searchFocused,
                onExit: { listFocused = true }
            )
            .focusedSceneValue(\.searchFieldFocus, $searchFocused)
            Text(localized("\(count) items"))
                .font(.kuku(.subheadline))
                .monospacedDigit()
                .foregroundStyle(KukuColor.textSecondary)
                .fixedSize()
            if filter != nil || !search.isEmpty {
                Button(localized("Clear Filters")) {
                    withAnimation(Motion.snappy) {
                        filter = nil
                        search = ""
                    }
                }
                .buttonStyle(.kuku(.secondary, size: .small))
            }
        }
        .padding(.top, KukuLayout.contentTop)
        .padding(.bottom, KukuSpacing.sm)
    }

    private func delete(_ entity: MemoryEntity) {
        if selection == entity.id { selection = filteredEntities.selectionAfterRemoving(entity.id) }
        appState.data.removeMemory(id: entity.id)
    }
}

/// Corrections SayKuku noticed that haven't been added or dismissed yet.
private struct CorrectionSuggestions: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let pending = appState.data.pendingCorrections
        KukuGroup(localized("Suggestions")) {
            ForEach(pending) { item in
                if item.id != pending.first?.id { KukuDivider() }
                CorrectionRow(item: item)
            }
            if !appState.settings.learnFromCorrections {
                KukuDivider()
                KukuRow(
                    localized("Learning from corrections is off"),
                    caption: localized("Turn it on to get new suggestions from words you fix.")
                ) {
                    Button(localized("Turn On")) { appState.settings.learnFromCorrections = true }
                        .buttonStyle(.kukuSecondary)
                }
            }
        }
    }
}

private struct CorrectionRow: View {
    @Environment(AppState.self) private var appState
    let item: CorrectionRecord

    var body: some View {
        HStack(spacing: KukuSpacing.md) {
            VStack(alignment: .leading, spacing: KukuSpacing.xxs) {
                HStack(spacing: KukuSpacing.sm) {
                    Text(item.raw)
                        .strikethrough()
                        .foregroundStyle(KukuColor.textSecondary)
                    Image(systemName: "arrow.right")
                        .font(.kukuIcon(.small, weight: .semibold))
                        .foregroundStyle(KukuColor.textTertiary)
                    Text(item.corrected)
                        .fontWeight(.semibold)
                        .foregroundStyle(KukuColor.textPrimary)
                }
                .font(.kuku(.body))
                Text(localized("Corrected \(item.count) times") + " · " + localized("Last in \(item.lastApp)"))
                    .font(.kuku(.subheadline))
                    .foregroundStyle(KukuColor.textSecondary)
            }
            Spacer(minLength: KukuSpacing.md)
            Button(localized("Ignore")) {
                withAnimation(Motion.snappy) { appState.data.ignoreCorrection(item.id) }
                appState.showToast(localized("Suggestion ignored"), symbol: "xmark.circle")
            }
            .buttonStyle(.kukuSecondary)
            Button(localized("Remember")) {
                withAnimation(Motion.spring) { appState.data.acceptCorrection(item.id) }
                appState.showToast(localized("Remembered"), symbol: "checkmark.circle.fill")
            }
            .buttonStyle(.kukuSecondary)
        }
        .kukuRowFrame()
    }
}

private struct EntityRow: View {
    let entity: MemoryEntity
    let isSelected: Bool
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
                    KukuBadge(text: entity.type.title)
                }
                Group {
                    if !entity.detail.isEmpty {
                        Text(entity.detail)
                    } else if !entity.aliases.isEmpty {
                        Text(localized("Aliases: \(entity.aliases.joined(separator: localized(", ")))"))
                    }
                }
                .font(.kuku(.subheadline))
                .foregroundStyle(KukuColor.textSecondary)
                .lineLimit(1)
                Text(entity.source.title + " · " + entity.createdAt.dayLabel)
                    .font(.kuku(.caption))
                    .foregroundStyle(KukuColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: KukuSpacing.md)
            HStack(spacing: KukuSpacing.xs) {
                Button(action: onEdit) {
                    HStack(spacing: KukuSpacing.iconText) {
                        Image(systemName: "pencil")
                        Text(localized("Edit…"))
                    }
                }
                .buttonStyle(.kukuSecondary)
                .fixedSize()
                .accessibilityLabel(localized("Edit “\(entity.name)”"))

                Menu {
                    Button(localized("Delete…"), role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(KukuColor.textSecondary)
                        // Same width as a regular KukuIconButton, as tall as the Edit button beside it.
                        .frame(width: KukuLayout.iconButton, height: KukuLayout.controlHeight)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .accessibilityLabel(localized("More actions"))
                .help(localized("More actions"))
            }
            // Fixed action column keeps the edit buttons aligned from row to row.
            .frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, KukuLayout.rowPadding)
        .padding(.vertical, KukuSpacing.md)
        .frame(maxWidth: .infinity, minHeight: KukuLayout.rowMinHeightWithCaption, alignment: .leading)
        .kukuInteractiveSurface(isSelected: isSelected)
        .contextMenu {
            Button(localized("Edit…"), action: onEdit)
            Divider()
            Button(localized("Delete…"), role: .destructive, action: onDelete)
        }
    }
}

private struct MemoryFormSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let entity: MemoryEntity?
    @State private var name: String
    @State private var type: EntityType
    @State private var detail: String
    @State private var aliases: String
    @State private var note: KukuSheetNote?

    init(entity: MemoryEntity? = nil) {
        self.entity = entity
        _name = State(initialValue: entity?.name ?? "")
        _type = State(initialValue: entity?.type ?? .term)
        _detail = State(initialValue: entity?.detail ?? "")
        _aliases = State(initialValue: entity?.aliases.joined(separator: "、") ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            KukuSheetHeader(
                title: entity == nil ? localized("Add to Memory") : localized("Edit Item"),
                description: localized("Teach SayKuku this name.")
            ) {
                KukuSheetIcon(symbol: entity == nil ? "plus" : "pencil")
            }

            KukuDivider(inset: 0)

            ScrollView {
                VStack(alignment: .leading, spacing: KukuSpacing.lg) {
                    VStack(alignment: .leading, spacing: KukuSpacing.sm) {
                        KukuFieldLabel(text: localized("Name"), isRequired: true)
                        KukuTextField(
                            prompt: localized("Enter a name"),
                            text: $name,
                            autoFocus: entity == nil,
                            onSubmit: save
                        )
                    }

                    VStack(alignment: .leading, spacing: KukuSpacing.sm) {
                        KukuFieldLabel(text: localized("Category"), isRequired: true)
                        KukuPicker(
                            localized("Category"),
                            options: EntityType.allCases,
                            selection: $type,
                            label: { $0.title }
                        )
                    }

                    VStack(alignment: .leading, spacing: KukuSpacing.sm) {
                        KukuFieldLabel(text: localized("Clue"))
                        KukuTextField(
                            prompt: localized("e.g. Yue Zhang, product manager on AniKuku"),
                            text: $detail,
                            multiline: true
                        )
                        Text(localized("When names sound alike, SayKuku uses the clue to pick the right one"))
                            .font(.kuku(.subheadline))
                            .foregroundStyle(KukuColor.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: KukuSpacing.sm) {
                        KukuFieldLabel(text: localized("Aliases"))
                        KukuTextField(
                            prompt: localized("Separate aliases with commas"),
                            text: $aliases
                        )
                        Text(localized("Aliases are recognized too"))
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
                Button(localized("Cancel")) { dismiss() }
                    .buttonStyle(.kukuSecondary)
                    .keyboardShortcut(.cancelAction)
                Button(entity == nil ? localized("Remember") : localized("Save")) { save() }
                    .buttonStyle(.kukuPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
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
            ? localized("Enter a name to continue")
            : localized("Enter a name to save"))
    }

    private func save() {
        guard canSave else { return }
        let editedAliases = aliases
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "、" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let error: MemorySaveError?
        if let entity {
            error = appState.data.updateMemory(id: entity.id, name: name, type: type, detail: detail, aliases: editedAliases)
        } else {
            error = appState.data.addMemory(name: name, type: type, detail: detail, aliases: editedAliases)
        }
        // The sheet covers the toast area, so failures stay in the footer.
        if let error {
            note = KukuSheetNote(text: error.message, isError: true)
            return
        }
        dismiss()
    }
}

private struct MemoryImportSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var reviewing = false
    @State private var source = ""
    @State private var selected = Set<UUID>()
    @State private var analysis: MemoryAnalysis?
    @State private var analysisTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var confirmingDiscard = false
    @FocusState private var sourceFocused: Bool

    private var analyzing: Bool { analysisTask != nil }

    /// Whether the analysis produced anything the user can import.
    private var hasResults: Bool {
        guard let analysis else { return false }
        return analysis.candidates.contains { $0.status != .ignored }
    }

    var body: some View {
        VStack(spacing: 0) {
            KukuSheetHeader(
                title: reviewing
                    ? localized("Choose What to Import")
                    : localized("Import from Text"),
                description: reviewing
                    ? localized("Review the suggestions and choose what SayKuku should remember.")
                    : localized("Paste some text and SayKuku will pick out names, projects, and terms.")
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
                        title: localized("No names or terms found"),
                        symbol: "text.magnifyingglass",
                        message: localized("Try text that mentions people, projects, or products.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Covers only the content so Cancel in the footer still works while waiting.
            .overlay {
                if analyzing {
                    ZStack {
                        KukuColor.fill
                        ProgressView(localized("Analyzing…"))
                            .padding(KukuSpacing.lg)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: KukuLayout.radiusMedium, style: .continuous))
                            .kukuShadow(.floating)
                    }
                }
            }

            KukuDivider(inset: 0)

            footer
        }
        .frame(width: KukuLayout.sheetWideWidth, height: KukuLayout.sheetHeight)
        .background(KukuColor.canvas)
        .onChange(of: source) { errorMessage = nil }
        .onDisappear { analysisTask?.cancel() }
        .confirmationDialog(
            localized("Discard this import?"),
            isPresented: $confirmingDiscard,
            titleVisibility: .visible
        ) {
            Button(localized("Discard"), role: .destructive) { dismiss() }
            Button(localized("Keep Importing"), role: .cancel) { }
        } message: {
            Text(localized("The analysis results won’t be saved."))
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
                .accessibilityLabel(localized("Text to import"))
            Label(localized(
                "Before analysis, SayKuku removes phone numbers, emails, and ID and bank card numbers in common formats, plus labeled addresses"
            ), systemImage: "eye.slash")
                .font(.kuku(.subheadline))
                .foregroundStyle(KukuColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, KukuLayout.sheetPadding)
        .padding(.vertical, KukuSpacing.xl)
    }

    private var reviewList: some View {
        ScrollView {
            VStack(spacing: KukuLayout.listSpacing) {
                ForEach(analysis?.candidates ?? []) { candidate in
                    let ignored = candidate.status == .ignored
                    ImportRow(
                        title: ignored ? localized("Filtered sensitive info") : candidate.entity.name,
                        badge: badge(for: candidate),
                        badgeTone: candidate.status.tone,
                        badgeSymbol: candidate.status.symbol,
                        detail: MemoryPipeline.displayEvidence(candidate.evidence),
                        trailing: ignored ? nil : candidate.entity.type.title,
                        isSelected: selected.contains(candidate.id),
                        isIgnored: ignored
                    ) {
                        toggle(candidate.id)
                    }
                }
            }
            .padding(.horizontal, KukuLayout.sheetPadding)
            .padding(.vertical, KukuSpacing.xl)
        }
    }

    private var footer: some View {
        KukuSheetFooter(note: footerNote) {
            Button(localized("Cancel")) { cancel() }
                .buttonStyle(.kukuSecondary)
                .keyboardShortcut(.cancelAction)
            if reviewing && hasResults {
                Button(localized("Back")) { goBack() }
                    .buttonStyle(.kukuSecondary)
            }
            primaryButton
        }
    }

    private var footerNote: KukuSheetNote? {
        if let errorMessage { return KukuSheetNote(text: errorMessage, isError: true) }
        if !reviewing {
            return KukuSheetNote(text: localized("Text is sent to Qwen for analysis. SayKuku doesn’t keep a copy."))
        }
        guard hasResults else { return nil }
        return KukuSheetNote(text: localized("\(selected.count) selected"))
    }

    @ViewBuilder
    private var primaryButton: some View {
        if !reviewing {
            // Return belongs to the text editor, so analysis uses ⌘Return.
            Button(localized("Analyze")) { analyze() }
                .buttonStyle(.kukuPrimary)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || analyzing)
        } else if hasResults {
            let count = selected.count
            Button(localized("Import \(count) Items")) { importSelection() }
                .buttonStyle(.kukuPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
        } else {
            Button(localized("Edit Text")) { goBack() }
                .buttonStyle(.kukuPrimary)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func badge(for candidate: ImportCandidate) -> String {
        guard candidate.status == .conflict,
              let match = appState.data.memoryEntities.first(where: { $0.id == candidate.matchedEntityID }) else {
            return candidate.status.title
        }
        return localized("May duplicate “\(match.name)”")
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
        errorMessage = nil
        analysisTask = Task {
            do {
                let value = try await appState.analyzeMemory(source)
                analysis = value
                selected = Set(value.candidates.filter { $0.status == .new || $0.status == .merge }.map(\.id))
                withAnimation(Motion.panel) { reviewing = true }
            } catch {
                errorMessage = localizedError(error)
            }
            analysisTask = nil
        }
    }

    private func importSelection() {
        guard let analysis, !selected.isEmpty else { return }
        let count = selected.count
        appState.data.commitMemory(analysis, selectedIDs: selected)
        appState.showToast(
            localized("Imported \(count) items to Memory"),
            symbol: "checkmark.seal.fill"
        )
        dismiss()
    }
}

/// Selectable suggestion row in the import review.
private struct ImportRow: View {
    let title: String
    let badge: String
    let badgeTone: KukuStatusTone
    let badgeSymbol: String
    let detail: String
    let trailing: String?
    let isSelected: Bool
    let isIgnored: Bool
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

private extension EntitySource {
    var title: String {
        switch self {
        case .manual: localized("You added it")
        case .importText: localized("Imported from text")
        case .correction: localized("Learned from a correction")
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
