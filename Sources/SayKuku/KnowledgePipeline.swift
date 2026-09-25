import Foundation

struct KnowledgeAnalysis: Equatable {
    var candidates: [ImportCandidate]
}

enum KnowledgePipeline {
    static func chunks(_ text: String, limit: Int = 12_000) -> [String] {
        guard text.count > limit else { return text.isEmpty ? [] : [text] }
        var result: [String] = []
        var current = ""
        for paragraph in text.components(separatedBy: "\n\n") {
            if current.count + paragraph.count + 2 <= limit {
                current += current.isEmpty ? paragraph : "\n\n\(paragraph)"
                continue
            }
            if !current.isEmpty { result.append(current); current = "" }
            var remainder = paragraph[...]
            while remainder.count > limit {
                let end = remainder.index(remainder.startIndex, offsetBy: limit)
                result.append(String(remainder[..<end]))
                remainder = remainder[end...]
            }
            current = String(remainder)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    // Applied in order; earlier matches are replaced before later patterns run.
    private static let piiPatterns = [
        // Email first, so a phone-like local part cannot leave the domain behind.
        #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
        // Mainland China resident ID: region, birth date, sequence, check digit.
        #"(?<![0-9A-Z])[1-9]\d{5}(?:18|19|20)\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])\d{3}[\dX](?![0-9A-Z])"#,
        // Bank cards: 13-19 contiguous digits, or 16-19 digits in groups of four.
        #"(?<!\d)(?:\d{13,19}|\d{4}(?:[ -]\d{4}){3}(?:[ -]\d{1,3})?)(?!\d)"#,
        // Mainland mobile numbers, optionally with +86 and 3-4-4 grouping.
        #"(?<!\d)(?:\+?86[- ]?)?1[3-9]\d(?:[- ]?\d{4}){2}(?!\d)"#,
        // International numbers written with a leading +.
        #"(?<![0-9A-Z+])\+\d{1,3}(?:[ .()-]{0,2}\d){7,14}(?!\d)"#,
        // Addresses are recognized only when explicitly labeled.
        #"(?:地址|住址|Address)\s*[:：]\s*[^\n]{4,}"#
    ]

    static func redactingPII(in source: String) -> (text: String, ignored: [ImportCandidate]) {
        var redacted = source
        var ignored: [ImportCandidate] = []
        for pattern in piiPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(redacted.startIndex..., in: redacted)
            let matches = regex.matches(in: redacted, range: range).reversed()
            for match in matches {
                guard let swiftRange = Range(match.range, in: redacted) else { continue }
                let value = String(redacted[swiftRange])
                // The row shows a localized label; keep only a masked hint of the original value.
                ignored.append(ImportCandidate(
                    entity: KnowledgeEntity(name: "", type: .term, source: .importText),
                    status: .ignored,
                    evidence: masked(value)
                ))
                redacted.replaceSubrange(swiftRange, with: redactionMarker)
            }
        }
        return (redacted, ignored.reversed())
    }

    /// Model-facing placeholder; a clear marker keeps extraction from treating it as content.
    static let redactionMarker = "[FILTERED]"

    /// Model evidence quotes the redacted text, so show the marker as a mask in the review list.
    static func displayEvidence(_ evidence: String) -> String {
        evidence.replacingOccurrences(of: redactionMarker, with: "••••")
    }

    /// Keeps a few edge characters so the user can recognize what was filtered.
    static func masked(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = min(3, trimmed.count / 4)
        return String(trimmed.prefix(visible)) + "••••" + String(trimmed.suffix(visible))
    }

    static func analyze(
        proposals: [ProposedEntity],
        existing: [KnowledgeEntity],
        ignored: [ImportCandidate]
    ) -> KnowledgeAnalysis {
        let uniqueProposals = proposals.reduce(into: [String: ProposedEntity]()) { result, proposal in
            let key = KnowledgeNormalizer.key(proposal.name)
            guard !key.isEmpty else { return }
            if var current = result[key] {
                current.aliases = Array(Set(current.aliases + proposal.aliases)).sorted()
                if current.detail.isEmpty { current.detail = proposal.detail }
                current.evidence += "\n" + proposal.evidence
                result[key] = current
            } else {
                result[key] = proposal
            }
        }.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var candidates: [ImportCandidate] = uniqueProposals.compactMap { proposal in
            let name = proposal.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !proposal.evidence.isEmpty else { return nil }
            let entity = KnowledgeEntity(
                name: name,
                detail: proposal.detail,
                type: proposal.type,
                aliases: proposal.aliases,
                source: .importText
            )
            if let match = existing.first(where: { exactMatch(entity, $0) }) {
                return ImportCandidate(entity: entity, status: .merge, evidence: proposal.evidence, matchedEntityID: match.id)
            }
            // Short Chinese names differ by one homophone, which the edit ratio cannot catch.
            let pinyin = KnowledgeNormalizer.pinyinKey(entity.name)
            if let match = existing.first(where: {
                similarity(entity.normalizedKey, $0.normalizedKey) >= 0.82
                    || (pinyin != nil && pinyin == KnowledgeNormalizer.pinyinKey($0.name))
            }) {
                return ImportCandidate(entity: entity, status: .conflict, evidence: proposal.evidence, matchedEntityID: match.id)
            }
            return ImportCandidate(entity: entity, status: .new, evidence: proposal.evidence)
        }
        candidates.append(contentsOf: ignored)
        return KnowledgeAnalysis(candidates: candidates)
    }

    static func commit(
        analysis: KnowledgeAnalysis,
        selectedIDs: Set<UUID>,
        existing: [KnowledgeEntity]
    ) -> [KnowledgeEntity] {
        var entities = existing
        let chosen = analysis.candidates.filter { selectedIDs.contains($0.id) && $0.status != .ignored }
        for candidate in chosen {
            if let matchID = candidate.matchedEntityID,
               let index = entities.firstIndex(where: { $0.id == matchID }) {
                let mergedAliases = entities[index].aliases + candidate.entity.aliases + [candidate.entity.name]
                entities[index].aliases = mergedAliases.reduce(into: []) { result, alias in
                    guard KnowledgeNormalizer.key(alias) != entities[index].normalizedKey,
                          !result.contains(where: { KnowledgeNormalizer.key($0) == KnowledgeNormalizer.key(alias) }) else { return }
                    result.append(alias)
                }
                if entities[index].detail.isEmpty { entities[index].detail = candidate.entity.detail }
            } else {
                entities.append(candidate.entity)
            }
        }
        return entities
    }

    private static func exactMatch(_ lhs: KnowledgeEntity, _ rhs: KnowledgeEntity) -> Bool {
        let lhsKeys = Set([lhs.normalizedKey] + lhs.aliases.map(KnowledgeNormalizer.key))
        let rhsKeys = Set([rhs.normalizedKey] + rhs.aliases.map(KnowledgeNormalizer.key))
        return !lhsKeys.isDisjoint(with: rhsKeys)
    }

    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let left = Array(lhs), right = Array(rhs)
        var previous = Array(0...right.count)
        for (i, leftCharacter) in left.enumerated() {
            var current = [i + 1]
            for (j, rightCharacter) in right.enumerated() {
                current.append(min(
                    current[j] + 1,
                    previous[j + 1] + 1,
                    previous[j] + (leftCharacter == rightCharacter ? 0 : 1)
                ))
            }
            previous = current
        }
        return 1 - Double(previous.last ?? max(left.count, right.count)) / Double(max(left.count, right.count))
    }
}
