import SwiftUI

struct KnowledgeView: View {
    @Environment(AppState.self) private var appState
    @State private var search = ""
    @State private var filter: KnowledgeFilter = .all
    @State private var showingImport = false
    @State private var newName = ""
    @State private var entities = KnowledgeEntity.samples

    var filteredEntities: [KnowledgeEntity] {
        entities.filter { entity in
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
            KnowledgeImportSheet { imported in
                entities.insert(contentsOf: imported, at: 0)
                appState.importedEntityCount += imported.count
                appState.showToast(
                    appState.text("已导入 \(imported.count) 项 Knowledge", "Imported \(imported.count) Knowledge items"),
                    symbol: "checkmark.seal.fill"
                )
            }
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
                QuickAddRow(name: $newName) { name in
                    entities.insert(
                        KnowledgeEntity(name: name, detail: appState.text("手动添加", "Added manually"), type: .term, aliases: []),
                        at: 0
                    )
                    appState.importedEntityCount += 1
                    newName = ""
                    appState.showToast(appState.text("已加入 Knowledge", "Added to Knowledge"), symbol: "checkmark.circle.fill")
                }
                .padding(.bottom, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredEntities) { entity in
                        EntityRow(entity: entity)
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
    let onAdd: (String) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.badge.plus")
                .foregroundStyle(KukuColor.coral)
            TextField(appState.text("输入名称", "Enter a name"), text: $name)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { if !name.isEmpty { onAdd(name) } }
            Picker("类型", selection: .constant(EntityType.term)) {
                ForEach(EntityType.allCases) { type in Text(type.title(appState)).tag(type) }
            }
            .labelsHidden()
            .frame(width: 120)
            Button(appState.text("添加", "Add")) { if !name.isEmpty { onAdd(name) } }
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
        }
        .padding(.horizontal, 10)
        .frame(height: KukuLayout.rowHeight)
    }
}

private struct KnowledgeImportSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var source = "姓名：王涛\n部门：产品部\n职位：产品经理\n手机号：18600000000\n\n项目 AniKuku，负责人张越，也叫 Visoar。"
    @State private var selected = Set(
        ImportCandidate.samples
            .filter { $0.status == .new || $0.status == .merge }
            .map(\.id)
    )
    let onImport: ([KnowledgeEntity]) -> Void

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
                        ForEach(ImportCandidate.samples) { candidate in
                            ImportCandidateRow(candidate: candidate, isSelected: selected.contains(candidate.id)) {
                                guard candidate.status != .ignored else { return }
                                if selected.contains(candidate.id) { selected.remove(candidate.id) } else { selected.insert(candidate.id) }
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
                    if step == 0 {
                        withAnimation(Motion.panel) { step = 1 }
                    } else {
                        let entities = ImportCandidate.samples.filter { selected.contains($0.id) }.map(\.entity)
                        onImport(entities)
                        dismiss()
                    }
                }
                .buttonStyle(HoverFillButtonStyle(prominent: true))
            }
            .padding(20)
        }
        .frame(width: 680, height: 580)
        .background(KukuColor.canvas)
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

enum EntityType: String, CaseIterable, Identifiable {
    case person, organization, project, product, term
    var id: String { rawValue }
    @MainActor func title(_ appState: AppState) -> String {
        switch self {
        case .person: appState.text("人物", "Person")
        case .organization: appState.text("组织", "Organization")
        case .project: appState.text("项目", "Project")
        case .product: appState.text("产品", "Product")
        case .term: appState.text("术语", "Term")
        }
    }
    var symbol: String {
        switch self {
        case .person: "person.fill"
        case .organization: "building.2.fill"
        case .project: "folder.fill"
        case .product: "shippingbox.fill"
        case .term: "character.book.closed.fill"
        }
    }
    var color: Color {
        switch self {
        case .person: KukuColor.coral
        case .organization: Color(red: 0.34, green: 0.50, blue: 0.75)
        case .project: Color(red: 0.58, green: 0.43, blue: 0.72)
        case .product: KukuColor.amber
        case .term: KukuColor.mint
        }
    }
    var filter: KnowledgeFilter {
        switch self {
        case .person: .people
        case .organization: .organizations
        case .project, .product: .projects
        case .term: .terms
        }
    }
}

struct KnowledgeEntity: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let type: EntityType
    let aliases: [String]

    static let samples = [
        KnowledgeEntity(name: "张越", detail: "UllrAI Lab · Founder · AniKuku", type: .person, aliases: ["Visoar", "张老师"]),
        KnowledgeEntity(name: "王涛", detail: "产品部 · 产品经理", type: .person, aliases: []),
        KnowledgeEntity(name: "AniKuku", detail: "Project · 负责人 张越", type: .project, aliases: ["Ani Kuku"]),
        KnowledgeEntity(name: "BifroMQ", detail: "Apache Project · 固定大小写", type: .product, aliases: ["B / M / Q"]),
        KnowledgeEntity(name: "UllrAI Lab", detail: "Organization", type: .organization, aliases: ["UllrAI"]),
        KnowledgeEntity(name: "WorkBuddy", detail: "Product · 纠正自 work body", type: .product, aliases: ["work body"]),
        KnowledgeEntity(name: "Semantic VAD", detail: "Voice terminology", type: .term, aliases: [])
    ]
}

struct ImportCandidate: Identifiable {
    enum Status: String {
        case new = "NEW"
        case merge = "MERGE"
        case conflict = "CONFLICT"
        case ignored = "IGNORED"
        var color: Color {
            switch self {
            case .new: KukuColor.mint
            case .merge: Color(red: 0.34, green: 0.50, blue: 0.75)
            case .conflict: KukuColor.amber
            case .ignored: KukuColor.stone
            }
        }
    }
    let id = UUID()
    let entity: KnowledgeEntity
    let status: Status
    let evidence: String

    static let samples = [
        ImportCandidate(entity: KnowledgeEntity(name: "王涛", detail: "产品部", type: .person, aliases: []), status: .merge, evidence: "“姓名：王涛 / 部门：产品部”"),
        ImportCandidate(entity: KnowledgeEntity(name: "产品部", detail: "Organization Unit", type: .organization, aliases: []), status: .new, evidence: "“部门：产品部”"),
        ImportCandidate(entity: KnowledgeEntity(name: "AniKuku", detail: "Project", type: .project, aliases: []), status: .merge, evidence: "“项目 AniKuku”"),
        ImportCandidate(entity: KnowledgeEntity(name: "张越", detail: "负责人", type: .person, aliases: ["Visoar"]), status: .conflict, evidence: "“负责人张越，也叫 Visoar”"),
        ImportCandidate(entity: KnowledgeEntity(name: "186 •••• 0000", detail: "已过滤的电话号码", type: .term, aliases: []), status: .ignored, evidence: "“手机号：18600000000”")
    ]
}
